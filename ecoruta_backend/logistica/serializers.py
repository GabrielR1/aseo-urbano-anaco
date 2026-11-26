from decimal import Decimal, InvalidOperation, ROUND_HALF_UP

from drf_spectacular.types import OpenApiTypes
from drf_spectacular.utils import extend_schema_field
from rest_framework import serializers

from security.permissions import es_administrador

from .models import Incidencia, Jornada, PuntoGeolocalizacion


def _round_coord(value):
    if value is None or value == '':
        return value
    try:
        dec = Decimal(str(value)).quantize(Decimal('0.000001'), rounding=ROUND_HALF_UP)
        return str(dec)
    except (InvalidOperation, ValueError, TypeError):
        return value


def _validar_rango(valor, minimo, maximo, etiqueta):
    if valor is None:
        return valor
    if not (Decimal(minimo) <= valor <= Decimal(maximo)):
        raise serializers.ValidationError(
            f"{etiqueta} fuera de rango: debe estar entre {minimo} y {maximo}."
        )
    return valor


class PuntoGeolocalizacionSerializer(serializers.ModelSerializer):
    class Meta:
        model = PuntoGeolocalizacion
        fields = ['id', 'jornada', 'latitud', 'longitud', 'precision_metros', 'velocidad_kmh', 'timestamp']
        read_only_fields = ['timestamp']

    def to_internal_value(self, data):
        mutable = data.copy() if hasattr(data, 'copy') else dict(data)
        if 'latitud' in mutable:
            mutable['latitud'] = _round_coord(mutable.get('latitud'))
        if 'longitud' in mutable:
            mutable['longitud'] = _round_coord(mutable.get('longitud'))
        return super().to_internal_value(mutable)

    def validate_latitud(self, value):
        return _validar_rango(value, -90, 90, 'Latitud')

    def validate_longitud(self, value):
        return _validar_rango(value, -180, 180, 'Longitud')

    def validate_precision_metros(self, value):
        if value is not None and value < 0:
            raise serializers.ValidationError('La precisión no puede ser negativa.')
        return value

    def validate_velocidad_kmh(self, value):
        if value is not None and value < 0:
            raise serializers.ValidationError('La velocidad no puede ser negativa.')
        return value

    def validate_jornada(self, jornada):
        request = self.context.get('request')
        if request and not es_administrador(request.user):
            if jornada.chofer.usuario_id != request.user.id:
                raise serializers.ValidationError(
                    'No puedes registrar telemetría para una jornada de otro conductor.'
                )
        return jornada


class IncidenciaSerializer(serializers.ModelSerializer):
    class Meta:
        model = Incidencia
        fields = [
            'id', 'jornada', 'descripcion', 'foto', 'latitud', 'longitud',
            'estado', 'resolucion_detalles', 'resuelta_en', 'timestamp'
        ]
        read_only_fields = ['resuelta_en', 'timestamp']

    def to_internal_value(self, data):
        mutable = data.copy() if hasattr(data, 'copy') else dict(data)
        if 'latitud' in mutable:
            mutable['latitud'] = _round_coord(mutable.get('latitud'))
        if 'longitud' in mutable:
            mutable['longitud'] = _round_coord(mutable.get('longitud'))
        return super().to_internal_value(mutable)

    def validate_latitud(self, value):
        return _validar_rango(value, -90, 90, 'Latitud')

    def validate_longitud(self, value):
        return _validar_rango(value, -180, 180, 'Longitud')

    def validate_jornada(self, jornada):
        request = self.context.get('request')
        if request and not es_administrador(request.user):
            if jornada.chofer.usuario_id != request.user.id:
                raise serializers.ValidationError(
                    'No puedes reportar incidencias en la jornada de otro conductor.'
                )
        return jornada

    def validate(self, attrs):
        request = self.context.get('request')
        if self.instance is None and request and not es_administrador(request.user):
            # Un conductor solo puede abrir incidencias nuevas en estado pendiente.
            attrs['estado'] = 'pendiente'
            attrs['resolucion_detalles'] = ''
        return attrs


class JornadaSerializer(serializers.ModelSerializer):
    distancia_real_km = serializers.SerializerMethodField()

    class Meta:
        model = Jornada
        fields = [
            'id', 'vehiculo', 'ruta', 'chofer', 'fecha',
            'inicio_real', 'fin_real', 'estado',
            'toneladas_recolectadas', 'distancia_real_km'
        ]

    @extend_schema_field(OpenApiTypes.FLOAT)
    def get_distancia_real_km(self, obj):
        return obj.calcular_distancia_real_km()
