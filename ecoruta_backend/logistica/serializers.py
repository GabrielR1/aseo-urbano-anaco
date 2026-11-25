from decimal import Decimal, InvalidOperation, ROUND_HALF_UP
from rest_framework import serializers
from .models import PuntoGeolocalizacion, Incidencia, Jornada


def _round_coord(value):
    if value is None or value == '':
        return value
    try:
        dec = Decimal(str(value)).quantize(Decimal('0.000001'), rounding=ROUND_HALF_UP)
        return str(dec)
    except (InvalidOperation, ValueError, TypeError):
        return value


class PuntoGeolocalizacionSerializer(serializers.ModelSerializer):
    class Meta:
        model = PuntoGeolocalizacion
        fields = ['id', 'jornada', 'latitud', 'longitud', 'precision_metros', 'velocidad_kmh', 'timestamp']

    def to_internal_value(self, data):
        mutable = data.copy() if hasattr(data, 'copy') else dict(data)
        if 'latitud' in mutable:
            mutable['latitud'] = _round_coord(mutable.get('latitud'))
        if 'longitud' in mutable:
            mutable['longitud'] = _round_coord(mutable.get('longitud'))
        return super().to_internal_value(mutable)


class IncidenciaSerializer(serializers.ModelSerializer):
    class Meta:
        model = Incidencia
        fields = [
            'id', 'jornada', 'descripcion', 'foto', 'latitud', 'longitud',
            'estado', 'resolucion_detalles', 'resuelta_en', 'timestamp'
        ]

    def to_internal_value(self, data):
        mutable = data.copy() if hasattr(data, 'copy') else dict(data)
        if 'latitud' in mutable:
            mutable['latitud'] = _round_coord(mutable.get('latitud'))
        if 'longitud' in mutable:
            mutable['longitud'] = _round_coord(mutable.get('longitud'))
        return super().to_internal_value(mutable)


class JornadaSerializer(serializers.ModelSerializer):
    distancia_real_km = serializers.SerializerMethodField()

    class Meta:
        model = Jornada
        fields = [
            'id', 'vehiculo', 'ruta', 'chofer', 'fecha',
            'inicio_real', 'fin_real', 'estado',
            'toneladas_recolectadas', 'distancia_real_km'
        ]

    def get_distancia_real_km(self, obj):
        return obj.calcular_distancia_real_km()


