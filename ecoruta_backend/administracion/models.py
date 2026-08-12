from django.db import models
from django.conf import settings
from django.utils import timezone

class Vehiculo(models.Model):
    ESTADO_CHOICES = [
        ('activo', 'Activo'),
        ('mantenimiento', 'En Mantenimiento'),
        ('inactivo', 'Inactivo'),
    ]
    placa = models.CharField(max_length=20, unique=True, verbose_name="Placa del Vehículo")
    marca = models.CharField(max_length=50, verbose_name="Marca")
    modelo = models.CharField(max_length=50, verbose_name="Modelo")
    capacidad_toneladas = models.DecimalField(max_digits=5, decimal_places=2, verbose_name="Capacidad (Toneladas)")
    estado = models.CharField(max_length=20, choices=ESTADO_CHOICES, default='activo', verbose_name="Estado Operativo")
    rendimiento_km_por_litro = models.DecimalField(max_digits=5, decimal_places=2, default=5.0, verbose_name="Rendimiento (Km/L)")

    class Meta:
        verbose_name = "Vehículo"
        verbose_name_plural = "Vehículos de la Flota"

    def __str__(self):
        return f"{self.marca} {self.modelo} - {self.placa}"

class Ruta(models.Model):
    nombre = models.CharField(max_length=100, verbose_name="Nombre de la Ruta")
    descripcion = models.TextField(blank=True, verbose_name="Descripción")
    zona = models.CharField(max_length=100, blank=True, verbose_name="Zona / Sector")
    distancia_estimada_km = models.DecimalField(max_digits=6, decimal_places=2, default=10.0, verbose_name="Distancia Estimada (Km)")

    class Meta:
        verbose_name = "Ruta Ecológica"
        verbose_name_plural = "Rutas Ecológicas"

    def __str__(self):
        return self.nombre

class Chofer(models.Model):
    usuario = models.OneToOneField(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='perfil_chofer', verbose_name="Cuenta de Usuario")
    licencia = models.CharField(max_length=50, unique=True, verbose_name="Nº de Licencia")
    telefono = models.CharField(max_length=20, blank=True, verbose_name="Teléfono de Contacto")

    class Meta:
        verbose_name = "Conductor / Chofer"
        verbose_name_plural = "Conductores / Choferes"

    def __str__(self):
        return f"Chofer: {self.usuario.get_full_name() or self.usuario.username}"

class RegistroCombustible(models.Model):
    vehiculo = models.ForeignKey(Vehiculo, on_delete=models.CASCADE, related_name='recargas_combustible', verbose_name="Vehículo")
    fecha = models.DateTimeField(default=timezone.now, verbose_name="Fecha y Hora")
    litros = models.DecimalField(max_digits=6, decimal_places=2, verbose_name="Litros Cargados")
    costo_total = models.DecimalField(max_digits=8, decimal_places=2, verbose_name="Costo Total ($)")
    kilometraje_actual = models.IntegerField(default=0, verbose_name="Kilometraje Actual")
    comprobante = models.ImageField(upload_to='comprobantes_combustible/', blank=True, null=True, verbose_name="Foto Comprobante")

    class Meta:
        verbose_name = "Registro de Combustible"
        verbose_name_plural = "Registros de Combustible"

    def __str__(self):
        return f"Recarga {self.vehiculo.placa} - {self.fecha.strftime('%Y-%m-%d')}"
