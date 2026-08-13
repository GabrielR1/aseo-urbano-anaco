from django.contrib import admin
from .models import Vehiculo, Ruta, Chofer, RegistroCombustible, RegistroAuditoria, PuntajeChofer, IncentivoChofer

admin.site.register(Vehiculo)
admin.site.register(Ruta)
admin.site.register(Chofer)
admin.site.register(RegistroCombustible)
admin.site.register(RegistroAuditoria)
admin.site.register(PuntajeChofer)
admin.site.register(IncentivoChofer)
