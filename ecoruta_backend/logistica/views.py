from decimal import Decimal, InvalidOperation, ROUND_HALF_UP
from django.utils import timezone
from rest_framework import viewsets, status
from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from drf_spectacular.utils import extend_schema
from .models import Jornada, PuntoGeolocalizacion, Incidencia
from .serializers import JornadaSerializer, PuntoGeolocalizacionSerializer, IncidenciaSerializer
from .optimizador import calcular_eficiencia_ecologica
from .gamificacion import evaluar_y_actualizar_puntaje_chofer
from administracion.models import Ruta, Chofer, IncentivoChofer, RegistroAuditoria


def _safe_decimal_coord(value):
    try:
        return Decimal(str(value)).quantize(Decimal('0.000001'), rounding=ROUND_HALF_UP)
    except (InvalidOperation, ValueError, TypeError):
        return None


class JornadaViewSet(viewsets.ModelViewSet):
    queryset = Jornada.objects.select_related('vehiculo', 'ruta', 'chofer').all()
    serializer_class = JornadaSerializer
    permission_classes = [IsAuthenticated]


class PuntoGeolocalizacionViewSet(viewsets.ModelViewSet):
    queryset = PuntoGeolocalizacion.objects.all()
    serializer_class = PuntoGeolocalizacionSerializer
    permission_classes = [IsAuthenticated]

    def perform_create(self, serializer):
        punto = serializer.save()
        # Si llega telemetría GPS real para una jornada pendiente, activarla automáticamente
        jornada = punto.jornada
        if jornada.estado == 'pendiente':
            jornada.estado = 'en_curso'
            if not jornada.inicio_real:
                jornada.inicio_real = timezone.now()
            jornada.save(update_fields=['estado', 'inicio_real', 'actualizado_en'])


class IncidenciaViewSet(viewsets.ModelViewSet):
    queryset = Incidencia.objects.all()
    serializer_class = IncidenciaSerializer
    permission_classes = [IsAuthenticated]


@extend_schema(
    summary="Sincronización Masiva GPS Offline",
    description="Endpoint para recibir un listado de puntos GPS guardados mientras la app móvil estuvo fuera de línea.",
    request=PuntoGeolocalizacionSerializer(many=True),
    responses={201: dict}
)
@api_view(['POST'])
@permission_classes([IsAuthenticated])
def sincronizar_puntos_lote(request):
    """
    Endpoint para sincronización masiva offline.
    Permite recibir un arreglo de puntos GPS acumulados cuando el chofer estuvo sin conexión.
    """
    puntos_data = request.data if isinstance(request.data, list) else request.data.get('puntos', [])
    if not isinstance(puntos_data, list):
        return Response({'detail': 'Se esperaba un listado de objetos JSON de puntos GPS.'}, status=status.HTTP_400_BAD_REQUEST)

    objetos_crear = []
    jornadas_tocadas = set()
    for item in puntos_data:
        jornada_id = item.get('jornada')
        lat = _safe_decimal_coord(item.get('latitud'))
        lng = _safe_decimal_coord(item.get('longitud'))
        if jornada_id and lat is not None and lng is not None:
            objetos_crear.append(PuntoGeolocalizacion(
                jornada_id=jornada_id,
                latitud=lat,
                longitud=lng,
                precision_metros=item.get('precision_metros'),
                velocidad_kmh=item.get('velocidad_kmh')
            ))
            jornadas_tocadas.add(jornada_id)

    if objetos_crear:
        PuntoGeolocalizacion.objects.bulk_create(objetos_crear)
        Jornada.objects.filter(id__in=jornadas_tocadas, estado='pendiente').update(
            estado='en_curso',
            inicio_real=timezone.now()
        )
        return Response({
            'mensaje': f'¡Se sincronizaron con éxito {len(objetos_crear)} puntos GPS!',
            'procesados': len(objetos_crear)
        }, status=status.HTTP_201_CREATED)
    else:
        return Response({'detail': 'No se encontraron registros de GPS válidos para procesar.'}, status=status.HTTP_400_BAD_REQUEST)


@extend_schema(
    summary="Jornadas Asignadas del Conductor",
    description="Devuelve las jornadas en curso y pendientes asignadas al conductor autenticado (o todas si es administrador).",
    responses={200: dict}
)
@api_view(['GET'])
@permission_classes([IsAuthenticated])
def mis_jornadas(request):
    qs = Jornada.objects.select_related('vehiculo', 'ruta', 'chofer', 'chofer__usuario').filter(
        estado__in=['en_curso', 'pendiente']
    )
    if not (request.user.is_staff or request.user.is_superuser):
        qs = qs.filter(chofer__usuario=request.user)

    # Priorizar jornadas en_curso primero, luego por fecha más reciente
    jornadas = sorted(qs, key=lambda j: (0 if j.estado == 'en_curso' else 1, -j.id))

    data = []
    for j in jornadas:
        ultimo = j.puntos.order_by('-timestamp').first()
        data.append({
            'id': j.id,
            'estado': j.estado,
            'estado_display': j.get_estado_display(),
            'fecha': j.fecha.strftime('%d/%m/%Y'),
            'vehiculo_placa': j.vehiculo.placa,
            'vehiculo_modelo': f"{j.vehiculo.marca} {j.vehiculo.modelo}",
            'ruta_nombre': j.ruta.nombre,
            'ruta_zona': j.ruta.zona or 'Municipio Anaco',
            'chofer': j.chofer.usuario.get_full_name() or j.chofer.usuario.username,
            'distancia_real_km': j.calcular_distancia_real_km(),
            'puntos_count': j.puntos.count(),
            'toneladas_recolectadas': float(j.toneladas_recolectadas),
            'ultima_actualizacion': timezone.localtime(ultimo.timestamp).strftime('%H:%M:%S') if ultimo else None,
        })

    return Response({'jornadas': data, 'total': len(data)}, status=status.HTTP_200_OK)


@extend_schema(
    summary="Iniciar Jornada de Recolección",
    description="Cambia el estado de una jornada a 'en_curso' y registra la hora real de inicio.",
    responses={200: dict}
)
@api_view(['POST'])
@permission_classes([IsAuthenticated])
def iniciar_jornada_api(request, pk):
    try:
        jornada = Jornada.objects.select_related('vehiculo', 'ruta', 'chofer', 'chofer__usuario').get(pk=pk)
    except Jornada.DoesNotExist:
        return Response({'detail': 'Jornada no encontrada.'}, status=status.HTTP_404_NOT_FOUND)

    if not (request.user.is_staff or request.user.is_superuser or jornada.chofer.usuario_id == request.user.id):
        return Response({'detail': 'No tienes permiso para iniciar esta jornada.'}, status=status.HTTP_403_FORBIDDEN)

    if jornada.estado != 'en_curso':
        jornada.estado = 'en_curso'
        if not jornada.inicio_real:
            jornada.inicio_real = timezone.now()
        jornada.save(update_fields=['estado', 'inicio_real', 'actualizado_en'])

        RegistroAuditoria.objects.create(
            usuario=request.user,
            accion='MODIFICAR',
            tabla_afectada='Jornada Asignada',
            detalles=f"Inicio real de jornada #{jornada.id} ({jornada.ruta.nombre}) con unidad [{jornada.vehiculo.placa}] desde dispositivo móvil."
        )

    return Response({
        'mensaje': 'Jornada iniciada. Transmitiendo GPS en tiempo real.',
        'jornada_id': jornada.id,
        'estado': jornada.estado,
        'inicio_real': timezone.localtime(jornada.inicio_real).strftime('%d/%m/%Y %H:%M:%S') if jornada.inicio_real else None,
    }, status=status.HTTP_200_OK)


@extend_schema(
    summary="Finalizar Jornada de Recolección",
    description="Cierra una jornada en curso, guarda toneladas reales recolectadas y actualiza el puntaje del chofer.",
    responses={200: dict}
)
@api_view(['POST'])
@permission_classes([IsAuthenticated])
def finalizar_jornada_api(request, pk):
    try:
        jornada = Jornada.objects.select_related('vehiculo', 'ruta', 'chofer', 'chofer__usuario').get(pk=pk)
    except Jornada.DoesNotExist:
        return Response({'detail': 'Jornada no encontrada.'}, status=status.HTTP_404_NOT_FOUND)

    if not (request.user.is_staff or request.user.is_superuser or jornada.chofer.usuario_id == request.user.id):
        return Response({'detail': 'No tienes permiso para finalizar esta jornada.'}, status=status.HTTP_403_FORBIDDEN)

    toneladas_raw = request.data.get('toneladas_recolectadas')
    if toneladas_raw is not None and str(toneladas_raw).strip() != '':
        try:
            toneladas = Decimal(str(toneladas_raw)).quantize(Decimal('0.01'), rounding=ROUND_HALF_UP)
            if toneladas < 0:
                return Response({'detail': 'Las toneladas recolectadas no pueden ser negativas.'}, status=status.HTTP_400_BAD_REQUEST)
            jornada.toneladas_recolectadas = toneladas
        except (InvalidOperation, ValueError, TypeError):
            return Response({'detail': 'Valor de toneladas no válido.'}, status=status.HTTP_400_BAD_REQUEST)

    jornada.estado = 'finalizada'
    jornada.fin_real = timezone.now()
    if not jornada.inicio_real:
        jornada.inicio_real = jornada.fin_real
    jornada.save()

    distancia_real = jornada.calcular_distancia_real_km()
    evaluar_y_actualizar_puntaje_chofer(jornada.chofer)

    RegistroAuditoria.objects.create(
        usuario=request.user,
        accion='MODIFICAR',
        tabla_afectada='Jornada Asignada',
        detalles=(
            f"Finalización de jornada #{jornada.id} ({jornada.ruta.nombre}) unidad [{jornada.vehiculo.placa}]. "
            f"Distancia real GPS: {distancia_real} Km | Recolección registrada: {jornada.toneladas_recolectadas} Ton."
        )
    )

    return Response({
        'mensaje': 'Jornada finalizada y métricas reales registradas.',
        'jornada_id': jornada.id,
        'estado': jornada.estado,
        'distancia_real_km': distancia_real,
        'toneladas_recolectadas': float(jornada.toneladas_recolectadas),
        'fin_real': timezone.localtime(jornada.fin_real).strftime('%d/%m/%Y %H:%M:%S'),
    }, status=status.HTTP_200_OK)


@extend_schema(
    summary="Datos de Monitoreo GPS en Vivo y Telemetría",
    description="Devuelve el estado real en tiempo real de los camiones en ruta, histórico de puntos GPS e incidencias activas.",
    responses={200: dict}
)
@api_view(['GET'])
@permission_classes([IsAuthenticated])
def monitoreo_en_vivo(request):
    """
    Devuelve las jornadas activas y pendientes, la última posición GPS real de cada camión,
    velocidad, trayectoria real (breadcrumbs), distancia recorrida real e incidencias.
    """
    jornadas_qs = Jornada.objects.select_related(
        'vehiculo', 'ruta', 'chofer', 'chofer__usuario'
    ).filter(estado__in=['en_curso', 'pendiente']).order_by('-id')

    camiones = []
    for j in jornadas_qs:
        puntos_queryset = list(j.puntos.order_by('-timestamp', '-id')[:120])
        ultimo_punto = puntos_queryset[0] if puntos_queryset else None

        trayectoria = [[float(p.latitud), float(p.longitud)] for p in reversed(puntos_queryset)]

        camiones.append({
            'jornada_id': j.id,
            'vehiculo': f"{j.vehiculo.marca} {j.vehiculo.modelo} ({j.vehiculo.placa})",
            'modelo': f"{j.vehiculo.marca} {j.vehiculo.modelo}",
            'placa': j.vehiculo.placa,
            'ruta': j.ruta.nombre,
            'zona': j.ruta.zona or 'Municipio Anaco',
            'chofer': j.chofer.usuario.get_full_name() or j.chofer.usuario.username,
            'estado': j.estado,
            'estado_display': j.get_estado_display(),
            'tiene_gps': ultimo_punto is not None,
            'latitud': float(ultimo_punto.latitud) if ultimo_punto else None,
            'longitud': float(ultimo_punto.longitud) if ultimo_punto else None,
            'velocidad_kmh': round(float(ultimo_punto.velocidad_kmh or 0.0), 1) if ultimo_punto else 0.0,
            'precision_metros': round(float(ultimo_punto.precision_metros), 1) if (ultimo_punto and ultimo_punto.precision_metros is not None) else None,
            'distancia_real_km': j.calcular_distancia_real_km(),
            'puntos_count': j.puntos.count(),
            'trayectoria': trayectoria,
            'ultima_actualizacion': timezone.localtime(ultimo_punto.timestamp).strftime('%H:%M:%S') if ultimo_punto else None,
        })

    incidencias_qs = Incidencia.objects.select_related('jornada', 'jornada__vehiculo').order_by('-timestamp')[:25]
    incidencias_data = []
    for inc in incidencias_qs:
        incidencias_data.append({
            'id': inc.id,
            'jornada_id': inc.jornada_id,
            'vehiculo_placa': inc.jornada.vehiculo.placa if inc.jornada and inc.jornada.vehiculo else "S/V",
            'descripcion': inc.descripcion,
            'latitud': float(inc.latitud) if inc.latitud is not None else None,
            'longitud': float(inc.longitud) if inc.longitud is not None else None,
            'estado': inc.estado,
            'estado_display': inc.get_estado_display(),
            'foto_url': inc.foto.url if inc.foto else None,
            'resolucion_detalles': inc.resolucion_detalles,
            'timestamp': timezone.localtime(inc.timestamp).strftime('%d/%m/%Y %H:%M'),
        })

    activos_con_gps = sum(1 for c in camiones if c['tiene_gps'])

    return Response({
        'camiones_activos': camiones,
        'total_activos': len(camiones),
        'total_con_gps': activos_con_gps,
        'incidencias': incidencias_data,
        'incidencias_pendientes': sum(1 for i in incidencias_data if i['estado'] == 'pendiente'),
        'hora_servidor': timezone.localtime(timezone.now()).strftime('%H:%M:%S'),
    })


@extend_schema(
    summary="Gestionar / Resolver Incidencia",
    description="Actualiza el estado operativo y notas de una incidencia.",
    responses={200: dict}
)
@api_view(['POST'])
@permission_classes([IsAuthenticated])
def gestionar_incidencia_api(request, pk):
    """
    Permite actualizar el estado de una incidencia (en_atencion o resuelta) y registrar notas.
    """
    try:
        inc = Incidencia.objects.get(pk=pk)
        nuevo_estado = request.data.get('estado')
        detalles = request.data.get('resolucion_detalles', '')

        if nuevo_estado in ['pendiente', 'en_atencion', 'resuelta']:
            inc.estado = nuevo_estado
            if detalles:
                inc.resolucion_detalles = detalles
            if nuevo_estado == 'resuelta':
                inc.resuelta_en = timezone.now()
            inc.save()
            return Response({'mensaje': f'Incidencia actualizada a {inc.get_estado_display()}', 'estado': inc.estado})
        else:
            return Response({'detail': 'Estado no válido.'}, status=status.HTTP_400_BAD_REQUEST)
    except Incidencia.DoesNotExist:
        return Response({'detail': 'Incidencia no encontrada.'}, status=status.HTTP_404_NOT_FOUND)


@extend_schema(
    summary="Cálculo de Eficiencia Ecológica y CO2 de una Ruta",
    description="Devuelve el consumo proyectado de litros, costo en USD y estimación de emisiones de CO2 reducidas.",
    responses={200: dict}
)
@api_view(['GET'])
@permission_classes([IsAuthenticated])
def optimizar_ruta_api(request, pk):
    try:
        ruta = Ruta.objects.get(pk=pk)
        analisis = calcular_eficiencia_ecologica(ruta.distancia_estimada_km)
        analisis['ruta'] = ruta.nombre
        analisis['zona'] = ruta.zona
        return Response(analisis, status=status.HTTP_200_OK)
    except Ruta.DoesNotExist:
        return Response({'detail': 'Ruta no encontrada.'}, status=status.HTTP_404_NOT_FOUND)


@extend_schema(
    summary="Notificaciones y Alertas para Conductor",
    description="Devuelve las notificaciones activas de jornadas asignadas para el chofer autenticado.",
    responses={200: dict}
)
@api_view(['GET'])
@permission_classes([IsAuthenticated])
def notificaciones_chofer(request):
    jornadas_pendientes = Jornada.objects.select_related('ruta', 'vehiculo').filter(
        chofer__usuario=request.user,
        estado__in=['en_curso', 'pendiente']
    ).order_by('-fecha', '-id')

    notificaciones = []
    for j in jornadas_pendientes:
        titulo = '🟢 Jornada en Curso' if j.estado == 'en_curso' else '🌿 Nueva Jornada Asignada'
        notificaciones.append({
            'id': j.id,
            'titulo': titulo,
            'mensaje': f"Ruta '{j.ruta.nombre}' ({j.ruta.zona}) en el vehículo {j.vehiculo.placa}.",
            'fecha': j.fecha.strftime('%d/%m/%Y'),
            'estado': j.estado
        })

    return Response({'notificaciones': notificaciones, 'total': len(notificaciones)})


@extend_schema(
    summary="Gamificación y Perfil de Puntos del Chofer",
    description="Devuelve el nivel, puntos acumulados, kilómetros reales recorridos e insignias obtenidas por el conductor.",
    responses={200: dict}
)
@api_view(['GET'])
@permission_classes([IsAuthenticated])
def chofer_gamificacion_api(request):
    chofer = Chofer.objects.filter(usuario=request.user).first()
    if not chofer:
        return Response({'detail': 'El usuario autenticado no tiene perfil de conductor asignado.'}, status=status.HTTP_404_NOT_FOUND)

    puntaje = evaluar_y_actualizar_puntaje_chofer(chofer)
    insignias = IncentivoChofer.objects.filter(chofer=chofer).order_by('-otorgado_en')

    insignias_list = []
    for inc in insignias:
        insignias_list.append({
            'id': inc.id,
            'titulo': inc.titulo,
            'descripcion': inc.descripcion,
            'insignia': inc.get_tipo_insignia_display(),
            'bono_usd': float(inc.monto_bono_usd),
            'fecha': inc.otorgado_en.strftime('%d/%m/%Y')
        })

    return Response({
        'chofer': chofer.usuario.get_full_name() or chofer.usuario.username,
        'puntos_totales': puntaje.puntos_totales,
        'km_recorridos_totales': float(puntaje.km_recorridos_totales),
        'jornadas_exitosas': puntaje.jornadas_exitosas,
        'nivel': puntaje.get_nivel_display(),
        'insignias': insignias_list
    }, status=status.HTTP_200_OK)
