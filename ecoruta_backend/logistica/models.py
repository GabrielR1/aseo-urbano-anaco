import math
from django.db import models
from administracion.models import Vehiculo, Ruta, Chofer
import django.utils.timezone


def haversine_km(lat1, lon1, lat2, lon2):
    """Calcula la distancia geodésica real en kilómetros entre dos coordenadas GPS."""
    r = 6371.0
    phi1 = math.radians(float(lat1))
    phi2 = math.radians(float(lat2))
    dphi = math.radians(float(lat2) - float(lat1))
    dlambda = math.radians(float(lon2) - float(lon1))

    a = math.sin(dphi / 2.0) ** 2 + math.cos(phi1) * math.cos(phi2) * math.sin(dlambda / 2.0) ** 2
    return 2.0 * r * math.atan2(math.sqrt(a), math.sqrt(1.0 - a))


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
    toneladas_recolectadas = models.DecimalField(
        max_digits=6,
        decimal_places=2,
        default=0.0,
        verbose_name="Toneladas Recolectadas"
    )
    creado_en = models.DateTimeField(default=django.utils.timezone.now, verbose_name="Fecha de Creación")
    actualizado_en = models.DateTimeField(auto_now=True, verbose_name="Última Actualización")

    class Meta:
        verbose_name = "Recorrido / Jornada Asignada"
        verbose_name_plural = "Recorridos Asignados"

    def calcular_distancia_real_km(self, puntos=None):
        """
        Calcula la distancia real recorrida (en Km) a partir de la traza GPS registrada
        en PuntoGeolocalizacion usando la fórmula de Haversine.
        Filtra micro-derivas menores a 5 metros y saltos anómalos de GPS.

        ``puntos`` permite reutilizar una lista ya prefetcheada (objetos del modelo o
        tuplas ``(latitud, longitud, timestamp)``) para evitar consultas N+1.
        """
        cache_distancia = getattr(self, "_distancia_real_km_cache", None)
        if cache_distancia is not None:
            return cache_distancia

        if puntos is None:
            cache = getattr(self, "_prefetched_objects_cache", {}) or {}
            if "puntos" in cache:
                puntos = cache["puntos"]
            else:
                puntos = list(
                    self.puntos.order_by("timestamp", "id").values_list(
                        "latitud", "longitud", "timestamp"
                    )
                )
        else:
            puntos = list(puntos)

        if len(puntos) < 2:
            self._distancia_real_km_cache = 0.0
            return 0.0

        def _tuple(punto):
            if isinstance(punto, (tuple, list)):
                return punto[0], punto[1], punto[2]
            return punto.latitud, punto.longitud, punto.timestamp

        distancia_total = 0.0
        prev_lat, prev_lng, prev_ts = _tuple(puntos[0])
        for punto in puntos[1:]:
            lat, lng, ts = _tuple(punto)
            tramo_km = haversine_km(prev_lat, prev_lng, lat, lng)
            # Ignorar micro-ruido estacionario (< 5 metros)
            if tramo_km < 0.005:
                continue
            # Filtrar saltos imposibles de GPS (> 5 km en menos de 60 segundos)
            delta_seg = (ts - prev_ts).total_seconds() if (ts and prev_ts) else 0
            if delta_seg > 0 and tramo_km > 5.0 and (tramo_km / (delta_seg / 3600.0)) > 160.0:
                continue
            distancia_total += tramo_km
            prev_lat, prev_lng, prev_ts = lat, lng, ts

        resultado = round(distancia_total, 2)
        self._distancia_real_km_cache = resultado
        return resultado

    def __str__(self):
        return f"Jornada {self.id} - {self.ruta.nombre} ({self.fecha})"

class PuntoGeolocalizacion(models.Model):
    jornada = models.ForeignKey(Jornada, on_delete=models.CASCADE, related_name='puntos', verbose_name="Jornada")
    latitud = models.DecimalField(max_digits=9, decimal_places=6, verbose_name="Latitud")
    longitud = models.DecimalField(max_digits=9, decimal_places=6, verbose_name="Longitud")
    precision_metros = models.FloatField(null=True, blank=True, verbose_name="Precisión (Metros)")
    velocidad_kmh = models.FloatField(null=True, blank=True, verbose_name="Velocidad (Km/h)")
    timestamp = models.DateTimeField(default=django.utils.timezone.now, db_index=True, verbose_name="Sello de Tiempo")

    class Meta:
        verbose_name = "Punto de Monitoreo GPS"
        verbose_name_plural = "Puntos de Monitoreo GPS"

    def __str__(self):
        return f"Punto ({self.latitud}, {self.longitud}) - Recorrido {self.jornada.id}"

class Incidencia(models.Model):
    ESTADO_CHOICES = [
        ('pendiente', '⚠️ Pendiente'),
        ('en_atencion', '🔄 En Atención'),
        ('resuelta', '✅ Resuelta'),
    ]
    jornada = models.ForeignKey(Jornada, on_delete=models.CASCADE, related_name='incidencias', verbose_name="Jornada")
    descripcion = models.TextField(verbose_name="Descripción de la Incidencia")
    foto = models.ImageField(upload_to='incidencias/', blank=True, null=True, verbose_name="Fotografía Evidencia")
    latitud = models.DecimalField(max_digits=9, decimal_places=6, null=True, blank=True, verbose_name="Latitud GPS")
    longitud = models.DecimalField(max_digits=9, decimal_places=6, null=True, blank=True, verbose_name="Longitud GPS")
    estado = models.CharField(max_length=20, choices=ESTADO_CHOICES, default='pendiente', verbose_name="Estado Operativo")
    resolucion_detalles = models.TextField(blank=True, default="", verbose_name="Notas de Resolución")
    resuelta_en = models.DateTimeField(null=True, blank=True, verbose_name="Fecha de Resolución")
    timestamp = models.DateTimeField(auto_now_add=True, db_index=True, verbose_name="Sello de Tiempo")

    class Meta:
        verbose_name = "Incidencia en Ruta"
        verbose_name_plural = "Incidencias Reportadas"

    def __str__(self):
        return f"[{self.get_estado_display()}] Incidencia Jornada {self.jornada.id} - {self.timestamp}"
