from django.db import models
from django.conf import settings
from django.utils import timezone

class Vehiculo(models.Model):
    ESTADO_CHOICES = [
        ('activo', 'Activo'),
        ('mantenimiento', 'En Mantenimiento'),
        ('inactivo', 'Inactivo'),
    ]
    placa = models.CharField(max_length=20, unique=True)
    marca = models.CharField(max_length=50)
    modelo = models.CharField(max_length=50)
    capacidad_toneladas = models.DecimalField(max_digits=5, decimal_places=2)
    estado = models.CharField(max_length=20, choices=ESTADO_CHOICES, default='activo')
    rendimiento_km_por_litro = models.DecimalField(max_digits=5, decimal_places=2, default=5.0)

    def __str__(self):
        return f"{self.marca} {self.modelo} - {self.placa}"

class Ruta(models.Model):
    nombre = models.CharField(max_length=100)
    descripcion = models.TextField(blank=True)
    zona = models.CharField(max_length=100, blank=True)
    distancia_estimada_km = models.DecimalField(max_digits=6, decimal_places=2, default=10.0)

    def __str__(self):
        return self.nombre

class Chofer(models.Model):
    usuario = models.OneToOneField(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='perfil_chofer')
    licencia = models.CharField(max_length=50, unique=True)
    telefono = models.CharField(max_length=20, blank=True)

    def __str__(self):
        return f"Chofer: {self.usuario.get_full_name() or self.usuario.username}"

class RegistroCombustible(models.Model):
    vehiculo = models.ForeignKey(Vehiculo, on_delete=models.CASCADE, related_name='recargas_combustible')
    fecha = models.DateTimeField(default=timezone.now)
    litros = models.DecimalField(max_digits=6, decimal_places=2)
    costo_total = models.DecimalField(max_digits=8, decimal_places=2)
    kilometraje_actual = models.IntegerField(default=0)
    comprobante = models.ImageField(upload_to='comprobantes_combustible/', blank=True, null=True)

    def __str__(self):
        return f"Recarga {self.vehiculo.placa} - {self.fecha.strftime('%Y-%m-%d')}"

