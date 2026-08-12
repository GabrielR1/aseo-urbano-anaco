from rest_framework import viewsets, status
from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from drf_spectacular.utils import extend_schema
from .models import Jornada, PuntoGeolocalizacion, Incidencia
from .serializers import JornadaSerializer, PuntoGeolocalizacionSerializer, IncidenciaSerializer

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
