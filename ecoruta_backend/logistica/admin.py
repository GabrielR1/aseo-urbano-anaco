from django.contrib import admin
from .models import Jornada, PuntoGeolocalizacion, Incidencia

admin.site.register(Jornada)
admin.site.register(PuntoGeolocalizacion)
admin.site.register(Incidencia)

