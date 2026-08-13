from rest_framework import viewsets, status
from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from drf_spectacular.utils import extend_schema
from .models import Jornada, PuntoGeolocalizacion, Incidencia
from .serializers import JornadaSerializer, PuntoGeolocalizacionSerializer, IncidenciaSerializer
from .optimizador import calcular_eficiencia_ecologica
from .gamificacion import evaluar_y_actualizar_puntaje_chofer
from administracion.models import Ruta, Chofer, IncentivoChofer

class JornadaViewSet(viewsets.ModelViewSet):
    queryset = Jornada.objects.select_related('vehiculo', 'ruta', 'chofer').all()
    serializer_class = JornadaSerializer
    permission_classes = [IsAuthenticated]

class PuntoGeolocalizacionViewSet(viewsets.ModelViewSet):
    queryset = PuntoGeolocalizacion.objects.all()
    serializer_class = PuntoGeolocalizacionSerializer
    permission_classes = [IsAuthenticated]

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
    for item in puntos_data:
        jornada_id = item.get('jornada')
        latitud = item.get('latitud')
        longitud = item.get('longitud')
        if jornada_id and latitud and longitud:
            objetos_crear.append(PuntoGeolocalizacion(
                jornada_id=jornada_id,
                latitud=latitud,
                longitud=longitud,
                precision_metros=item.get('precision_metros'),
                velocidad_kmh=item.get('velocidad_kmh')
            ))
            
    if objetos_crear:
        PuntoGeolocalizacion.objects.bulk_create(objetos_crear)
        return Response({
            'mensaje': f'¡Se sincronizaron con éxito {len(objetos_crear)} puntos GPS!',
            'procesados': len(objetos_crear)
        }, status=status.HTTP_201_CREATED)
    else:
        return Response({'detail': 'No se encontraron registros de GPS válidos para procesar.'}, status=status.HTTP_400_BAD_REQUEST)

@extend_schema(
    summary="Datos de Monitoreo GPS en Vivo",
    description="Devuelve el estado en tiempo real de los camiones activos en ruta y su última posición GPS.",
    responses={200: dict}
)
@api_view(['GET'])
@permission_classes([IsAuthenticated])
def monitoreo_en_vivo(request):
    """
    Devuelve las jornadas activas, la última posición GPS de cada camión y la velocidad actual.
    """
    jornadas_activas = Jornada.objects.select_related('vehiculo', 'ruta', 'chofer', 'chofer__usuario').filter(estado='en_curso')
    resultado = []
    
    for j in jornadas_activas:
        ultimo_punto = j.puntos.order_by('-timestamp').first()
        resultado.append({
            'jornada_id': j.id,
            'vehiculo': f"{j.vehiculo.marca} {j.vehiculo.modelo} ({j.vehiculo.placa})",
            'placa': j.vehiculo.placa,
            'ruta': j.ruta.nombre,
            'zona': j.ruta.zona,
            'chofer': j.chofer.usuario.get_full_name() or j.chofer.usuario.username,
            'estado': j.estado,
            'latitud': float(ultimo_punto.latitud) if ultimo_punto else None,
            'longitud': float(ultimo_punto.longitud) if ultimo_punto else None,
            'velocidad_kmh': ultimo_punto.velocidad_kmh if ultimo_punto else 0,
            'ultima_actualizacion': ultimo_punto.timestamp.strftime('%Y-%m-%d %H:%M:%S') if ultimo_punto else None,
        })
        
    return Response({'camiones_activos': resultado, 'total_activos': len(resultado)})

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
        estado='pendiente'
    ).order_by('-fecha')
    
    notificaciones = []
    for j in jornadas_pendientes:
        notificaciones.append({
            'id': j.id,
            'titulo': '🌿 Nueva Jornada Asignada',
            'mensaje': f"Se te ha asignado la ruta '{j.ruta.nombre}' ({j.ruta.zona}) en el vehículo {j.vehiculo.placa}.",
            'fecha': j.fecha.strftime('%d/%m/%Y'),
            'estado': j.estado
        })
        
    return Response({'notificaciones': notificaciones, 'total': len(notificaciones)})

@extend_schema(
    summary="Gamificación y Perfil de Puntos del Chofer",
    description="Devuelve el nivel, puntos acumulados, kilómetros recorridos e insignias obtenidas por el conductor.",
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
