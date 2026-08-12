from rest_framework import serializers
from .models import PuntoGeolocalizacion, Incidencia, Jornada

class PuntoGeolocalizacionSerializer(serializers.ModelSerializer):
    class Meta:
        model = PuntoGeolocalizacion
        fields = ['jornada', 'latitud', 'longitud', 'timestamp']

class IncidenciaSerializer(serializers.ModelSerializer):
    class Meta:
        model = Incidencia
        fields = ['jornada', 'descripcion', 'foto', 'latitud', 'longitud', 'timestamp']

class JornadaSerializer(serializers.ModelSerializer):
    class Meta:
        model = Jornada
        fields = ['id', 'vehiculo', 'ruta', 'chofer', 'fecha', 'estado']
