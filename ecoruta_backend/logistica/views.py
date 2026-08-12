from rest_framework import viewsets
from rest_framework.permissions import IsAuthenticated
from .models import Jornada, PuntoGeolocalizacion, Incidencia
from .serializers import JornadaSerializer, PuntoGeolocalizacionSerializer, IncidenciaSerializer

class JornadaViewSet(viewsets.ModelViewSet):
    queryset = Jornada.objects.all()
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

