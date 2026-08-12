from django.db import models
from administracion.models import Vehiculo, Ruta, Chofer
import django.utils.timezone

class Jornada(models.Model):
    ESTADO_CHOICES = [
        ('pendiente', 'Pendiente'),
        ('en_curso', 'En Curso'),
        ('finalizada', 'Finalizada'),
    ]
    vehiculo = models.ForeignKey(Vehiculo, on_delete=models.CASCADE, verbose_name="Vehículo")
    ruta = models.ForeignKey(Ruta, on_delete=models.CASCADE, verbose_name="Ruta Ecológica")
    chofer = models.ForeignKey(Chofer, on_delete=models.CASCADE, verbose_name="Conductor")
    fecha = models.DateField(default=django.utils.timezone.now, db_index=True, verbose_name="Fecha Programada")
    inicio_real = models.DateTimeField(null=True, blank=True, verbose_name="Inicio Real")
    fin_real = models.DateTimeField(null=True, blank=True, verbose_name="Fin Real")
    estado = models.CharField(max_length=20, choices=ESTADO_CHOICES, default='pendiente', verbose_name="Estado de la Jornada")
    creado_en = models.DateTimeField(default=django.utils.timezone.now, verbose_name="Fecha de Creación")
    actualizado_en = models.DateTimeField(auto_now=True, verbose_name="Última Actualización")

    class Meta:
        verbose_name = "Jornada de Trabajo"
        verbose_name_plural = "Jornadas de Trabajo"

    def __str__(self):
        return f"Jornada {self.id} - {self.ruta.nombre} ({self.fecha})"

class PuntoGeolocalizacion(models.Model):
    jornada = models.ForeignKey(Jornada, on_delete=models.CASCADE, related_name='puntos', verbose_name="Jornada")
    latitud = models.DecimalField(max_digits=9, decimal_places=6, verbose_name="Latitud")
    longitud = models.DecimalField(max_digits=9, decimal_places=6, verbose_name="Longitud")
    precision_metros = models.FloatField(null=True, blank=True, verbose_name="Precisión (Metros)")
    velocidad_kmh = models.FloatField(null=True, blank=True, verbose_name="Velocidad (Km/h)")
    timestamp = models.DateTimeField(auto_now_add=True, db_index=True, verbose_name="Sello de Tiempo")

    class Meta:
        verbose_name = "Punto de Geolocalización"
        verbose_name_plural = "Puntos de Geolocalización GPS"

    def __str__(self):
        return f"Punto ({self.latitud}, {self.longitud}) - Jornada {self.jornada.id}"

class Incidencia(models.Model):
    jornada = models.ForeignKey(Jornada, on_delete=models.CASCADE, related_name='incidencias', verbose_name="Jornada")
    descripcion = models.TextField(verbose_name="Descripción de la Incidencia")
    foto = models.ImageField(upload_to='incidencias/', blank=True, null=True, verbose_name="Fotografía Evidencia")
    latitud = models.DecimalField(max_digits=9, decimal_places=6, null=True, blank=True, verbose_name="Latitud GPS")
    longitud = models.DecimalField(max_digits=9, decimal_places=6, null=True, blank=True, verbose_name="Longitud GPS")
    timestamp = models.DateTimeField(auto_now_add=True, db_index=True, verbose_name="Sello de Tiempo")

    class Meta:
        verbose_name = "Incidencia Reportada"
        verbose_name_plural = "Incidencias Reportadas"

    def __str__(self):
        return f"Incidencia Jornada {self.jornada.id} - {self.timestamp}"
