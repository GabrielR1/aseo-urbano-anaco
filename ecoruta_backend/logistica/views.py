from datetime import timedelta
from decimal import Decimal, InvalidOperation, ROUND_HALF_UP

from django.db.models import Prefetch
from django.utils import timezone
from django.utils.dateparse import parse_datetime
from drf_spectacular.types import OpenApiTypes
from drf_spectacular.utils import extend_schema
from rest_framework import status, viewsets
from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response

from administracion.models import (
    Chofer,
    IncentivoChofer,
    RegistroAuditoria,
    RegistroCombustible,
    Ruta,
    Vehiculo,
)
from security.permissions import EsAdministrador, es_administrador

from .models import Incidencia, Jornada, PuntoGeolocalizacion
from .optimizador import calcular_eficiencia_ecologica
from .gamificacion import evaluar_y_actualizar_puntaje_chofer
from .serializers import (
    IncidenciaSerializer,
    JornadaSerializer,
    PuntoGeolocalizacionSerializer,
)
from .services import serializar_camion, serializar_incidencia

MAX_PUNTOS_POR_LOTE = 5000


def _safe_decimal_coord(value):
    try:
        return Decimal(str(value)).quantize(Decimal('0.000001'), rounding=ROUND_HALF_UP)
    except (InvalidOperation, ValueError, TypeError):
        return None


def _safe_float(value):
    """Normaliza valores numéricos opcionales que llegan como texto desde la app."""
    if value is None or str(value).strip() == '':
        return None
    try:
        return float(value)
    except (ValueError, TypeError):
        return None


def _prefetch_puntos():
    return Prefetch(
        'puntos',
        queryset=PuntoGeolocalizacion.objects.order_by('timestamp', 'id'),
    )


def _timestamp_offline(value):
    """Convierte el sello de tiempo enviado por la app; si es inválido usa la hora actual."""
    if not value:
        return timezone.now()
    fecha = parse_datetime(str(value))
    if fecha is None:
        return timezone.now()
    if timezone.is_naive(fecha):
        fecha = timezone.make_aware(fecha, timezone.get_current_timezone())
    ahora = timezone.now()
    if fecha > ahora + timedelta(minutes=5):
        return ahora
    return fecha


class JornadaViewSet(viewsets.ModelViewSet):
    queryset = Jornada.objects.all()
    serializer_class = JornadaSerializer
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        queryset = Jornada.objects.select_related(
            'vehiculo', 'ruta', 'chofer', 'chofer__usuario'
        )
        if self.action == 'retrieve':
            queryset = queryset.prefetch_related(_prefetch_puntos())
        queryset = queryset.order_by('-fecha', '-id')
        if es_administrador(self.request.user):
            return queryset
        return queryset.filter(chofer__usuario=self.request.user)

    def get_permissions(self):
        # Los conductores solo consultan sus jornadas; las altas y bajas son administrativas.
        if self.action in ('list', 'retrieve'):
            return [IsAuthenticated()]
        return [IsAuthenticated(), EsAdministrador()]


class PuntoGeolocalizacionViewSet(viewsets.ModelViewSet):
    queryset = PuntoGeolocalizacion.objects.all()
    serializer_class = PuntoGeolocalizacionSerializer
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        queryset = PuntoGeolocalizacion.objects.select_related(
            'jornada', 'jornada__chofer', 'jornada__chofer__usuario'
        )
        if es_administrador(self.request.user):
            return queryset
        return queryset.filter(jornada__chofer__usuario=self.request.user)

    def get_permissions(self):
        if self.action in ('list', 'retrieve', 'create'):
            return [IsAuthenticated()]
        return [IsAuthenticated(), EsAdministrador()]

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

    def get_queryset(self):
        queryset = Incidencia.objects.select_related(
            'jornada', 'jornada__vehiculo', 'jornada__chofer', 'jornada__chofer__usuario'
        )
        if es_administrador(self.request.user):
            return queryset
        return queryset.filter(jornada__chofer__usuario=self.request.user)

    def get_permissions(self):
        if self.action in ('list', 'retrieve', 'create'):
            return [IsAuthenticated()]
        return [IsAuthenticated(), EsAdministrador()]


@extend_schema(
    summary="Sincronización Masiva GPS Offline",
    description=(
        "Endpoint para recibir un listado de puntos GPS guardados mientras la app móvil "
        "estuvo fuera de línea. Cada punto puede incluir su marca de tiempo original."
    ),
    request=PuntoGeolocalizacionSerializer(many=True),
    responses={201: OpenApiTypes.OBJECT},
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
        return Response(
            {'detail': 'Se esperaba un listado de objetos JSON de puntos GPS.'},
            status=status.HTTP_400_BAD_REQUEST,
        )
    if len(puntos_data) > MAX_PUNTOS_POR_LOTE:
        return Response(
            {'detail': f'El lote excede el máximo de {MAX_PUNTOS_POR_LOTE} puntos.'},
            status=status.HTTP_400_BAD_REQUEST,
        )

    # Resolver en una sola consulta las jornadas válidas para el usuario.
    ids_solicitados = set()
    for item in puntos_data:
        if isinstance(item, dict):
            jornada_id = str(item.get('jornada') or '')
            if jornada_id.isdigit():
                ids_solicitados.add(int(jornada_id))

    jornadas_qs = Jornada.objects.filter(id__in=ids_solicitados)
    if not es_administrador(request.user):
        jornadas_qs = jornadas_qs.filter(chofer__usuario=request.user)
    ids_permitidos = {str(pk) for pk in jornadas_qs.values_list('id', flat=True)}

    objetos_crear = []
    jornadas_tocadas = set()
    descartados = 0

    for item in puntos_data:
        if not isinstance(item, dict):
            descartados += 1
            continue
        jornada_id = str(item.get('jornada') or '')
        lat = _safe_decimal_coord(item.get('latitud'))
        lng = _safe_decimal_coord(item.get('longitud'))
        if not (
            jornada_id in ids_permitidos
            and lat is not None
            and lng is not None
            and Decimal('-90') <= lat <= Decimal('90')
            and Decimal('-180') <= lng <= Decimal('180')
        ):
            descartados += 1
            continue

        objetos_crear.append(
            PuntoGeolocalizacion(
                jornada_id=int(jornada_id),
                latitud=lat,
                longitud=lng,
                precision_metros=_safe_float(item.get('precision_metros')),
                velocidad_kmh=_safe_float(item.get('velocidad_kmh')),
                timestamp=_timestamp_offline(item.get('timestamp')),
            )
        )
        jornadas_tocadas.add(int(jornada_id))

    if not objetos_crear:
        return Response(
            {'detail': 'No se encontraron registros de GPS válidos para procesar.'},
            status=status.HTTP_400_BAD_REQUEST,
        )

    PuntoGeolocalizacion.objects.bulk_create(objetos_crear)
    Jornada.objects.filter(id__in=jornadas_tocadas, estado='pendiente').update(
        estado='en_curso', inicio_real=timezone.now()
    )

    return Response(
        {
            'mensaje': f'¡Se sincronizaron con éxito {len(objetos_crear)} puntos GPS!',
            'procesados': len(objetos_crear),
            'descartados': descartados,
        },
        status=status.HTTP_201_CREATED,
    )


@extend_schema(
    summary="Jornadas Asignadas del Conductor",
    description=(
        "Devuelve las jornadas en curso y pendientes asignadas al conductor autenticado "
        "(o todas si es administrador)."
    ),
    responses={200: OpenApiTypes.OBJECT},
)
@api_view(['GET'])
@permission_classes([IsAuthenticated])
def mis_jornadas(request):
    qs = Jornada.objects.select_related(
        'vehiculo', 'ruta', 'chofer', 'chofer__usuario'
    ).filter(estado__in=['en_curso', 'pendiente']).prefetch_related(_prefetch_puntos())
    if not es_administrador(request.user):
        qs = qs.filter(chofer__usuario=request.user)

    # Priorizar jornadas en_curso primero, luego por fecha más reciente
    jornadas = sorted(qs, key=lambda j: (0 if j.estado == 'en_curso' else 1, -j.id))

    data = []
    for j in jornadas:
        puntos = list(j.puntos.all())
        ultimo = puntos[-1] if puntos else None
        data.append(
            {
                'id': j.id,
                'estado': j.estado,
                'estado_display': j.get_estado_display(),
                'fecha': j.fecha.strftime('%d/%m/%Y'),
                'vehiculo_id': j.vehiculo_id,
                'vehiculo_placa': j.vehiculo.placa,
                'vehiculo_modelo': f"{j.vehiculo.marca} {j.vehiculo.modelo}",
                'ruta_nombre': j.ruta.nombre,
                'ruta_zona': j.ruta.zona or 'Municipio Anaco',
                'ruta_descripcion': j.ruta.descripcion or '',
                'distancia_estimada_km': float(j.ruta.distancia_estimada_km or 0),
                'chofer': j.chofer.usuario.get_full_name() or j.chofer.usuario.username,
                'distancia_real_km': j.calcular_distancia_real_km(puntos=puntos),
                'puntos_count': len(puntos),
                'toneladas_recolectadas': float(j.toneladas_recolectadas or 0),
                'ultima_actualizacion': (
                    timezone.localtime(ultimo.timestamp).strftime('%H:%M:%S') if ultimo else None
                ),
            }
        )

    return Response({'jornadas': data, 'total': len(data)}, status=status.HTTP_200_OK)


@extend_schema(
    summary="Iniciar Jornada de Recolección",
    description="Cambia el estado de una jornada a 'en_curso' y registra la hora real de inicio.",
    request=None,
    responses={200: OpenApiTypes.OBJECT},
)
@api_view(['POST'])
@permission_classes([IsAuthenticated])
def iniciar_jornada_api(request, pk):
    try:
        jornada = Jornada.objects.select_related('vehiculo', 'ruta', 'chofer', 'chofer__usuario').get(pk=pk)
    except Jornada.DoesNotExist:
        return Response({'detail': 'Jornada no encontrada.'}, status=status.HTTP_404_NOT_FOUND)

    if not (es_administrador(request.user) or jornada.chofer.usuario_id == request.user.id):
        return Response(
            {'detail': 'No tienes permiso para iniciar esta jornada.'},
            status=status.HTTP_403_FORBIDDEN,
        )

    if jornada.estado != 'en_curso':
        jornada.estado = 'en_curso'
        if not jornada.inicio_real:
            jornada.inicio_real = timezone.now()
        jornada.save(update_fields=['estado', 'inicio_real', 'actualizado_en'])

        RegistroAuditoria.objects.create(
            usuario=request.user,
            accion='MODIFICAR',
            tabla_afectada='Jornada Asignada',
            detalles=(
                f"Inicio real de jornada #{jornada.id} ({jornada.ruta.nombre}) "
                f"con unidad [{jornada.vehiculo.placa}] desde dispositivo móvil."
            ),
        )

    return Response(
        {
            'mensaje': 'Jornada iniciada. Transmitiendo GPS en tiempo real.',
            'jornada_id': jornada.id,
            'estado': jornada.estado,
            'inicio_real': (
                timezone.localtime(jornada.inicio_real).strftime('%d/%m/%Y %H:%M:%S')
                if jornada.inicio_real
                else None
            ),
        },
        status=status.HTTP_200_OK,
    )


@extend_schema(
    summary="Finalizar Jornada de Recolección",
    description=(
        "Cierra una jornada en curso, guarda toneladas reales recolectadas y actualiza "
        "el puntaje del chofer."
    ),
    request=OpenApiTypes.OBJECT,
    responses={200: OpenApiTypes.OBJECT},
)
@api_view(['POST'])
@permission_classes([IsAuthenticated])
def finalizar_jornada_api(request, pk):
    try:
        jornada = Jornada.objects.select_related('vehiculo', 'ruta', 'chofer', 'chofer__usuario').get(pk=pk)
    except Jornada.DoesNotExist:
        return Response({'detail': 'Jornada no encontrada.'}, status=status.HTTP_404_NOT_FOUND)

    if not (es_administrador(request.user) or jornada.chofer.usuario_id == request.user.id):
        return Response(
            {'detail': 'No tienes permiso para finalizar esta jornada.'},
            status=status.HTTP_403_FORBIDDEN,
        )

    if jornada.estado == 'finalizada':
        return Response(
            {'detail': 'La jornada ya se encuentra finalizada.'},
            status=status.HTTP_400_BAD_REQUEST,
        )

    toneladas_raw = request.data.get('toneladas_recolectadas')
    if toneladas_raw is not None and str(toneladas_raw).strip() != '':
        try:
            toneladas = Decimal(str(toneladas_raw)).quantize(Decimal('0.01'), rounding=ROUND_HALF_UP)
            if toneladas < 0:
                return Response(
                    {'detail': 'Las toneladas recolectadas no pueden ser negativas.'},
                    status=status.HTTP_400_BAD_REQUEST,
                )
            jornada.toneladas_recolectadas = toneladas
        except (InvalidOperation, ValueError, TypeError):
            return Response(
                {'detail': 'Valor de toneladas no válido.'},
                status=status.HTTP_400_BAD_REQUEST,
            )

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
            f"Finalización de jornada #{jornada.id} ({jornada.ruta.nombre}) unidad "
            f"[{jornada.vehiculo.placa}]. Distancia real GPS: {distancia_real} Km | "
            f"Recolección registrada: {jornada.toneladas_recolectadas} Ton."
        ),
    )

    return Response(
        {
            'mensaje': 'Jornada finalizada y métricas reales registradas.',
            'jornada_id': jornada.id,
            'estado': jornada.estado,
            'distancia_real_km': distancia_real,
            'toneladas_recolectadas': float(jornada.toneladas_recolectadas),
            'fin_real': timezone.localtime(jornada.fin_real).strftime('%d/%m/%Y %H:%M:%S'),
        },
        status=status.HTTP_200_OK,
    )


@extend_schema(
    summary="Datos de Monitoreo GPS en Vivo y Telemetría",
    description=(
        "Devuelve el estado real en tiempo real de los camiones en ruta, histórico de "
        "puntos GPS e incidencias activas. Uso exclusivo del panel administrativo."
    ),
    responses={200: OpenApiTypes.OBJECT},
)
@api_view(['GET'])
@permission_classes([IsAuthenticated, EsAdministrador])
def monitoreo_en_vivo(request):
    """
    Devuelve las jornadas activas y pendientes, la última posición GPS real de cada camión,
    velocidad, trayectoria real (breadcrumbs), distancia recorrida real e incidencias.
    """
    jornadas_qs = (
        Jornada.objects.select_related('vehiculo', 'ruta', 'chofer', 'chofer__usuario')
        .filter(estado__in=['en_curso', 'pendiente'])
        .prefetch_related(_prefetch_puntos())
        .order_by('-id')
    )

    camiones = [serializar_camion(j) for j in jornadas_qs]

    incidencias_qs = (
        Incidencia.objects.select_related('jornada', 'jornada__vehiculo')
        .order_by('-timestamp')[:25]
    )
    incidencias_data = [serializar_incidencia(inc) for inc in incidencias_qs]

    activos_con_gps = sum(1 for c in camiones if c['tiene_gps'])

    return Response(
        {
            'camiones_activos': camiones,
            'total_activos': len(camiones),
            'total_con_gps': activos_con_gps,
            'incidencias': incidencias_data,
            'incidencias_pendientes': sum(
                1 for i in incidencias_data if i['estado'] == 'pendiente'
            ),
            'hora_servidor': timezone.localtime(timezone.now()).strftime('%H:%M:%S'),
        }
    )


@extend_schema(
    summary="Gestionar / Resolver Incidencia",
    description="Actualiza el estado operativo y notas de una incidencia.",
    request=OpenApiTypes.OBJECT,
    responses={200: OpenApiTypes.OBJECT},
)
@api_view(['POST'])
@permission_classes([IsAuthenticated])
def gestionar_incidencia_api(request, pk):
    """
    Permite actualizar el estado de una incidencia (en_atencion o resuelta) y registrar notas.
    """
    try:
        inc = Incidencia.objects.select_related(
            'jornada', 'jornada__chofer', 'jornada__chofer__usuario'
        ).get(pk=pk)
    except Incidencia.DoesNotExist:
        return Response({'detail': 'Incidencia no encontrada.'}, status=status.HTTP_404_NOT_FOUND)

    if not (
        es_administrador(request.user)
        or (inc.jornada and inc.jornada.chofer.usuario_id == request.user.id)
    ):
        return Response(
            {'detail': 'No tienes permiso para gestionar esta incidencia.'},
            status=status.HTTP_403_FORBIDDEN,
        )

    nuevo_estado = request.data.get('estado')
    detalles = request.data.get('resolucion_detalles', '')

    if nuevo_estado not in ['pendiente', 'en_atencion', 'resuelta']:
        return Response({'detail': 'Estado no válido.'}, status=status.HTTP_400_BAD_REQUEST)

    inc.estado = nuevo_estado
    if detalles:
        inc.resolucion_detalles = detalles
    inc.resuelta_en = timezone.now() if nuevo_estado == 'resuelta' else None
    inc.save(update_fields=['estado', 'resolucion_detalles', 'resuelta_en'])

    return Response(
        {'mensaje': f'Incidencia actualizada a {inc.get_estado_display()}', 'estado': inc.estado}
    )


@extend_schema(
    summary="Cálculo de Eficiencia Ecológica y CO2 de una Ruta",
    description=(
        "Devuelve el consumo proyectado de litros, costo en USD y estimación de "
        "emisiones de CO2 reducidas."
    ),
    responses={200: OpenApiTypes.OBJECT},
)
@api_view(['GET'])
@permission_classes([IsAuthenticated])
def optimizar_ruta_api(request, pk):
    try:
        ruta = Ruta.objects.get(pk=pk)
    except Ruta.DoesNotExist:
        return Response({'detail': 'Ruta no encontrada.'}, status=status.HTTP_404_NOT_FOUND)

    analisis = calcular_eficiencia_ecologica(ruta.distancia_estimada_km)
    analisis['ruta'] = ruta.nombre
    analisis['zona'] = ruta.zona
    return Response(analisis, status=status.HTTP_200_OK)


@extend_schema(
    summary="Notificaciones y Alertas para Conductor",
    description=(
        "Devuelve las notificaciones activas de jornadas asignadas para el chofer autenticado."
    ),
    responses={200: OpenApiTypes.OBJECT},
)
@api_view(['GET'])
@permission_classes([IsAuthenticated])
def notificaciones_chofer(request):
    jornadas_pendientes = Jornada.objects.select_related('ruta', 'vehiculo').filter(
        chofer__usuario=request.user,
        estado__in=['en_curso', 'pendiente'],
    ).order_by('-fecha', '-id')

    notificaciones = []
    for j in jornadas_pendientes:
        titulo = '🟢 Jornada en Curso' if j.estado == 'en_curso' else '🌿 Nueva Jornada Asignada'
        notificaciones.append(
            {
                'id': j.id,
                'titulo': titulo,
                'mensaje': f"Ruta '{j.ruta.nombre}' ({j.ruta.zona}) en el vehículo {j.vehiculo.placa}.",
                'fecha': j.fecha.strftime('%d/%m/%Y'),
                'estado': j.estado,
            }
        )

    return Response({'notificaciones': notificaciones, 'total': len(notificaciones)})


@extend_schema(
    summary="Gamificación y Perfil de Puntos del Chofer",
    description=(
        "Devuelve el nivel, puntos acumulados, kilómetros reales recorridos e insignias "
        "obtenidas por el conductor."
    ),
    responses={200: OpenApiTypes.OBJECT},
)
@api_view(['GET'])
@permission_classes([IsAuthenticated])
def chofer_gamificacion_api(request):
    chofer = Chofer.objects.filter(usuario=request.user).first()
    if not chofer:
        return Response(
            {'detail': 'El usuario autenticado no tiene perfil de conductor asignado.'},
            status=status.HTTP_404_NOT_FOUND,
        )

    puntaje = evaluar_y_actualizar_puntaje_chofer(chofer)
    insignias = IncentivoChofer.objects.filter(chofer=chofer).order_by('-otorgado_en')

    insignias_list = []
    for inc in insignias:
        insignias_list.append(
            {
                'id': inc.id,
                'titulo': inc.titulo,
                'descripcion': inc.descripcion,
                'insignia': inc.get_tipo_insignia_display(),
                'bono_usd': float(inc.monto_bono_usd),
                'fecha': inc.otorgado_en.strftime('%d/%m/%Y'),
            }
        )

    return Response(
        {
            'chofer': chofer.usuario.get_full_name() or chofer.usuario.username,
            'puntos_totales': puntaje.puntos_totales,
            'km_recorridos_totales': float(puntaje.km_recorridos_totales),
            'jornadas_exitosas': puntaje.jornadas_exitosas,
            'nivel': puntaje.get_nivel_display(),
            'insignias': insignias_list,
        },
        status=status.HTTP_200_OK,
    )


@extend_schema(
    summary="Registro de Carga de Combustible desde App Móvil",
    description=(
        "GET devuelve las unidades activas para seleccionar; POST registra una recarga real "
        "de combustible (litros, costo, kilometraje y comprobante opcional) y actualiza el panel."
    ),
    responses={200: OpenApiTypes.OBJECT, 201: OpenApiTypes.OBJECT},
)
@api_view(['GET', 'POST'])
@permission_classes([IsAuthenticated])
def combustible_chofer_api(request):
    if request.method == 'GET':
        vehiculos = [
            {
                'id': v.id,
                'placa': v.placa,
                'modelo': f'{v.marca} {v.modelo}',
            }
            for v in Vehiculo.objects.filter(estado='activo').order_by('placa')
        ]
        return Response({'vehiculos': vehiculos}, status=status.HTTP_200_OK)

    vehiculo_raw = request.data.get('vehiculo')
    try:
        vehiculo_id = int(str(vehiculo_raw).strip())
    except (TypeError, ValueError):
        return Response(
            {'detail': 'Selecciona un vehículo válido.'},
            status=status.HTTP_400_BAD_REQUEST,
        )

    vehiculo = Vehiculo.objects.filter(pk=vehiculo_id).first()
    if not vehiculo:
        return Response(
            {'detail': 'La unidad seleccionada no existe.'},
            status=status.HTTP_404_NOT_FOUND,
        )

    litros_raw = str(request.data.get('litros', '')).strip().replace(',', '.')
    costo_raw = str(request.data.get('costo_total', '0')).strip().replace(',', '.') or '0'
    km_raw = str(request.data.get('kilometraje_actual', '0')).strip() or '0'

    try:
        litros = Decimal(litros_raw)
        costo_total = Decimal(costo_raw)
        kilometraje = int(float(km_raw))
    except (InvalidOperation, ValueError, TypeError):
        return Response(
            {'detail': 'Verifica los valores de litros, costo y kilometraje.'},
            status=status.HTTP_400_BAD_REQUEST,
        )

    if litros <= 0 or litros > Decimal('1000'):
        return Response(
            {'detail': 'Los litros deben ser mayores que 0 y menores o iguales a 1000.'},
            status=status.HTTP_400_BAD_REQUEST,
        )
    if costo_total < 0 or kilometraje < 0:
        return Response(
            {'detail': 'El costo y el kilometraje no pueden ser negativos.'},
            status=status.HTTP_400_BAD_REQUEST,
        )

    comprobante = request.FILES.get('comprobante')
    registro = RegistroCombustible.objects.create(
        vehiculo=vehiculo,
        litros=litros.quantize(Decimal('0.01'), rounding=ROUND_HALF_UP),
        costo_total=costo_total.quantize(Decimal('0.01'), rounding=ROUND_HALF_UP),
        kilometraje_actual=kilometraje,
        comprobante=comprobante,
    )

    nombre_usuario = request.user.get_full_name() or request.user.username
    RegistroAuditoria.objects.create(
        usuario=request.user,
        accion='CREAR',
        tabla_afectada='Registro de Combustible',
        detalles=(
            f"{nombre_usuario} registró carga de {registro.litros} L "
            f"(${registro.costo_total}) para la unidad [{vehiculo.placa}] desde la app móvil."
        ),
    )

    return Response(
        {
            'id': registro.id,
            'vehiculo_placa': vehiculo.placa,
            'litros': float(registro.litros),
            'costo_total': float(registro.costo_total),
            'kilometraje_actual': registro.kilometraje_actual,
            'mensaje': f'Carga de {registro.litros} L registrada para {vehiculo.placa}.',
        },
        status=status.HTTP_201_CREATED,
    )
