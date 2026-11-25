from django.contrib import admin
from django.utils.html import format_html
from django.utils.safestring import mark_safe
from .models import Vehiculo, Ruta, Chofer, RegistroCombustible, RegistroAuditoria

@admin.register(Vehiculo)
class VehiculoAdmin(admin.ModelAdmin):
    list_display = ('placa_badge', 'marca', 'modelo', 'tipo_unidad', 'capacidad_toneladas', 'rendimiento_km_por_litro', 'estado_badge')
    list_filter = ('estado',)
    search_fields = ('placa', 'marca', 'modelo')
    ordering = ('placa',)

    def placa_badge(self, obj):
        return format_html(
            '<span style="font-family: monospace; font-weight: 700; background: #dbeafe; color: #1d4ed8; padding: 3px 8px; border-radius: 4px; border: 1px solid #bfdbfe;">{}</span>',
            obj.placa
        )
    placa_badge.short_description = "Placa"

    def tipo_unidad(self, obj):
        if 'TM' in obj.placa:
            return mark_safe('<span style="color: #b45309; font-weight: 600;"><i class="fa-solid fa-motorcycle"></i> Trimoto</span>')
        return mark_safe('<span style="color: #1d4ed8; font-weight: 600;"><i class="fa-solid fa-truck"></i> Camión Compactador</span>')
    tipo_unidad.short_description = "Tipo"

    def estado_badge(self, obj):
        colors = {
            'activo': ('#dcfce7', '#15803d', 'Activo'),
            'mantenimiento': ('#fef3c7', '#b45309', 'En Mantenimiento'),
            'inactivo': ('#fee2e2', '#b91c1c', 'Inactivo'),
        }
        bg, fg, label = colors.get(obj.estado, ('#f1f5f9', '#475569', obj.estado))
        return format_html(
            '<span style="background: {}; color: {}; padding: 3px 10px; border-radius: 12px; font-weight: 700; font-size: 11px;">{}</span>',
            bg, fg, label
        )
    estado_badge.short_description = "Estado Operativo"


@admin.register(Ruta)
class RutaAdmin(admin.ModelAdmin):
    list_display = ('nombre', 'zona', 'distancia_estimada_km', 'actualizado_en')
    search_fields = ('nombre', 'zona', 'descripcion')
    list_filter = ('zona',)


@admin.register(Chofer)
class ChoferAdmin(admin.ModelAdmin):
    list_display = ('nombre_completo', 'licencia', 'telefono', 'actualizado_en')
    search_fields = ('usuario__first_name', 'usuario__last_name', 'usuario__username', 'licencia', 'telefono')

    def nombre_completo(self, obj):
        return obj.usuario.get_full_name() or obj.usuario.username
    nombre_completo.short_description = "Nombre del Conductor"


@admin.register(RegistroCombustible)
class RegistroCombustibleAdmin(admin.ModelAdmin):
    list_display = ('fecha_formato', 'vehiculo', 'litros', 'costo_total_badge', 'kilometraje_actual')
    list_filter = ('vehiculo', 'fecha')
    search_fields = ('vehiculo__placa', 'vehiculo__modelo')
    date_hierarchy = 'fecha'

    def fecha_formato(self, obj):
        return obj.fecha.strftime('%d/%m/%Y %H:%M')
    fecha_formato.short_description = "Fecha / Hora"

    def costo_total_badge(self, obj):
        return format_html('<strong>${}</strong>', obj.costo_total)
    costo_total_badge.short_description = "Costo Total"


@admin.register(RegistroAuditoria)
class RegistroAuditoriaAdmin(admin.ModelAdmin):
    list_display = ('timestamp_formato', 'accion_badge', 'tabla_afectada', 'usuario', 'detalles')
    list_filter = ('accion', 'tabla_afectada', 'timestamp')
    search_fields = ('tabla_afectada', 'detalles', 'usuario__username')
    readonly_fields = ('usuario', 'accion', 'tabla_afectada', 'detalles', 'timestamp')

    def timestamp_formato(self, obj):
        return obj.timestamp.strftime('%d/%m/%Y %H:%M:%S')
    timestamp_formato.short_description = "Fecha / Hora"

    def accion_badge(self, obj):
        colors = {
            'CREAR': ('#dcfce7', '#15803d'),
            'MODIFICAR': ('#dbeafe', '#1d4ed8'),
            'ELIMINAR': ('#fee2e2', '#b91c1c'),
        }
        bg, fg = colors.get(obj.accion, ('#f1f5f9', '#475569'))
        return format_html(
            '<span style="background: {}; color: {}; padding: 2px 8px; border-radius: 4px; font-weight: 700; font-size: 11px;">{}</span>',
            bg, fg, obj.accion
        )
    accion_badge.short_description = "Acción"
