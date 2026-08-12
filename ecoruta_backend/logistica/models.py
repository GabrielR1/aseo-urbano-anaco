from django.db import models
from administracion.models import Vehiculo, Ruta, Chofer
import django.utils.timezone

class Jornada(models.Model):
    ESTADO_CHOICES = [
        ('pendiente', 'Pendiente'),
        ('en_curso', 'En Curso'),
        ('finalizada', 'Finalizada'),
    ]
    vehiculo = models.ForeignKey(Vehiculo, on_delete=models.CASCADE)
    ruta = models.ForeignKey(Ruta, on_delete=models.CASCADE)
    chofer = models.ForeignKey(Chofer, on_delete=models.CASCADE)
    fecha = models.DateField(default=django.utils.timezone.now)
    estado = models.CharField(max_length=20, choices=ESTADO_CHOICES, default='pendiente')

    def __str__(self):
        return f"Jornada {self.id} - {self.ruta.nombre} ({self.fecha})"

class PuntoGeolocalizacion(models.Model):
    jornada = models.ForeignKey(Jornada, on_delete=models.CASCADE, related_name='puntos')
    latitud = models.DecimalField(max_digits=9, decimal_places=6)
    longitud = models.DecimalField(max_digits=9, decimal_places=6)
    timestamp = models.DateTimeField(auto_now_add=True)

    def __str__(self):
        return f"Punto ({self.latitud}, {self.longitud}) - Jornada {self.jornada.id}"

class Incidencia(models.Model):
    jornada = models.ForeignKey(Jornada, on_delete=models.CASCADE, related_name='incidencias')
    descripcion = models.TextField()
    foto = models.ImageField(upload_to='incidencias/', blank=True, null=True)
    latitud = models.DecimalField(max_digits=9, decimal_places=6, null=True, blank=True)
    longitud = models.DecimalField(max_digits=9, decimal_places=6, null=True, blank=True)
    timestamp = models.DateTimeField(auto_now_add=True)

    def __str__(self):
        return f"Incidencia Jornada {self.jornada.id} - {self.timestamp}"
