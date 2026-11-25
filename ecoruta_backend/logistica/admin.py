from django.contrib import admin
from django.utils.html import format_html
from .models import Jornada, PuntoGeolocalizacion, Incidencia

@admin.register(Jornada)
class JornadaAdmin(admin.ModelAdmin):
    list_display = ('id', 'fecha', 'vehiculo', 'ruta', 'chofer', 'estado_badge', 'inicio_real', 'fin_real')
    list_filter = ('estado', 'fecha', 'ruta')
    search_fields = ('vehiculo__placa', 'ruta__nombre', 'chofer__usuario__first_name', 'chofer__usuario__last_name')
    date_hierarchy = 'fecha'

    def estado_badge(self, obj):
        colors = {
            'en_curso': ('#dbeafe', '#1d4ed8', 'En Recorrido'),
            'pendiente': ('#fef3c7', '#b45309', 'Pendiente'),
            'finalizada': ('#dcfce7', '#15803d', 'Finalizada'),
        }
        bg, fg, label = colors.get(obj.estado, ('#f1f5f9', '#475569', obj.get_estado_display()))
        return format_html(
            '<span style="background: {}; color: {}; padding: 3px 10px; border-radius: 12px; font-weight: 700; font-size: 11px;">{}</span>',
            bg, fg, label
        )
    estado_badge.short_description = "Estado"


@admin.register(Incidencia)
class IncidenciaAdmin(admin.ModelAdmin):
    list_display = ('id', 'timestamp_formato', 'jornada', 'descripcion_corta', 'estado_badge')
    list_filter = ('estado', 'timestamp')
    search_fields = ('descripcion', 'resolucion_detalles')

    def timestamp_formato(self, obj):
        return obj.timestamp.strftime('%d/%m/%Y %H:%M')
    timestamp_formato.short_description = "Fecha / Hora"

    def descripcion_corta(self, obj):
        desc = obj.descripcion or ""
        return desc[:60] + ('...' if len(desc) > 60 else '')
    descripcion_corta.short_description = "Descripción"

    def estado_badge(self, obj):
        colors = {
            'pendiente': ('#fee2e2', '#b91c1c', '⚠️ Pendiente'),
            'en_atencion': ('#fef3c7', '#b45309', '🔄 En Atención'),
            'resuelta': ('#dcfce7', '#15803d', '✅ Resuelta'),
        }
        bg, fg, label = colors.get(obj.estado, ('#f1f5f9', '#475569', obj.get_estado_display()))
        return format_html(
            '<span style="background: {}; color: {}; padding: 3px 10px; border-radius: 12px; font-weight: 700; font-size: 11px;">{}</span>',
            bg, fg, label
        )
    estado_badge.short_description = "Estado Operativo"


@admin.register(PuntoGeolocalizacion)
class PuntoGeolocalizacionAdmin(admin.ModelAdmin):
    list_display = ('id', 'jornada', 'latitud', 'longitud', 'velocidad_kmh', 'timestamp')
    list_filter = ('timestamp',)
    search_fields = ('jornada__vehiculo__placa',)
