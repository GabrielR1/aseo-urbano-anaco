from django.contrib import admin
from .models import Vehiculo, Ruta, Chofer, RegistroCombustible, RegistroAuditoria

admin.site.register(Vehiculo)
admin.site.register(Ruta)
admin.site.register(Chofer)
admin.site.register(RegistroCombustible)
admin.site.register(RegistroAuditoria)
