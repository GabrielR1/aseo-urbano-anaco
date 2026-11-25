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
    creado_en = models.DateTimeField(default=timezone.now, verbose_name="Fecha de Creación")
    actualizado_en = models.DateTimeField(auto_now=True, verbose_name="Última Actualización")

    class Meta:
        verbose_name = "Unidad de Recolección"
        verbose_name_plural = "Unidades de Recolección (Flota)"

    def __str__(self):
        return f"{self.marca} {self.modelo} - {self.placa}"

class Ruta(models.Model):
    nombre = models.CharField(max_length=100, verbose_name="Nombre de la Ruta")
    descripcion = models.TextField(blank=True, verbose_name="Descripción")
    zona = models.CharField(max_length=100, blank=True, verbose_name="Zona / Sector")
    distancia_estimada_km = models.DecimalField(max_digits=6, decimal_places=2, default=10.0, verbose_name="Distancia Estimada (Km)")
    coordenadas_waypoints = models.TextField(blank=True, default="", verbose_name="Waypoints y Puntos de Recolección (JSON)")
    creado_en = models.DateTimeField(default=timezone.now, verbose_name="Fecha de Creación")
    actualizado_en = models.DateTimeField(auto_now=True, verbose_name="Última Actualización")

    class Meta:
        verbose_name = "Ruta de Recolección"
        verbose_name_plural = "Rutas de Recolección"

    def __str__(self):
        return self.nombre

class Chofer(models.Model):
    usuario = models.OneToOneField(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='perfil_chofer', verbose_name="Cuenta de Usuario")
    licencia = models.CharField(max_length=50, unique=True, verbose_name="Nº de Licencia")
    telefono = models.CharField(max_length=20, blank=True, verbose_name="Teléfono de Contacto")
    creado_en = models.DateTimeField(default=timezone.now, verbose_name="Fecha de Creación")
    actualizado_en = models.DateTimeField(auto_now=True, verbose_name="Última Actualización")

    class Meta:
        verbose_name = "Conductor / Chofer"
        verbose_name_plural = "Conductores y Cuadrillas"

    def __str__(self):
        return f"Chofer: {self.usuario.get_full_name() or self.usuario.username}"

class RegistroCombustible(models.Model):
    vehiculo = models.ForeignKey(Vehiculo, on_delete=models.CASCADE, related_name='recargas_combustible', verbose_name="Vehículo")
    fecha = models.DateTimeField(default=timezone.now, verbose_name="Fecha y Hora")
    litros = models.DecimalField(max_digits=6, decimal_places=2, verbose_name="Litros Cargados")
    costo_total = models.DecimalField(max_digits=8, decimal_places=2, verbose_name="Costo Total ($)")
    kilometraje_actual = models.IntegerField(default=0, verbose_name="Kilometraje Actual")
    comprobante = models.ImageField(upload_to='comprobantes_combustible/', blank=True, null=True, verbose_name="Foto Comprobante")
    creado_en = models.DateTimeField(default=timezone.now, verbose_name="Fecha de Creación")
    actualizado_en = models.DateTimeField(auto_now=True, verbose_name="Última Actualización")

    class Meta:
        verbose_name = "Registro de Combustible"
        verbose_name_plural = "Registros de Combustible"

    def __str__(self):
        return f"Recarga {self.vehiculo.placa} - {self.fecha.strftime('%Y-%m-%d')}"

class RegistroAuditoria(models.Model):
    ACCION_CHOICES = [
        ('CREAR', 'Guardar / Crear'),
        ('MODIFICAR', 'Modificar / Actualizar'),
        ('ELIMINAR', 'Eliminar / Borrar'),
    ]
    usuario = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, blank=True, verbose_name="Usuario")
    accion = models.CharField(max_length=20, choices=ACCION_CHOICES, verbose_name="Acción Realizada")
    tabla_afectada = models.CharField(max_length=50, verbose_name="Entidad / Tabla")
    detalles = models.TextField(verbose_name="Detalles del Cambio")
    timestamp = models.DateTimeField(default=timezone.now, db_index=True, verbose_name="Fecha y Hora")

    class Meta:
        verbose_name = "Registro de Actividad"
        verbose_name_plural = "Registro de Actividades (Auditoría)"

    def __str__(self):
        return f"[{self.accion}] {self.tabla_afectada} por {self.usuario} ({self.timestamp.strftime('%Y-%m-%d %H:%M')})"

class PuntajeChofer(models.Model):
    NIVEL_CHOICES = [
        ('bronce', '🥉 Bronce'),
        ('plata', '🥈 Plata'),
        ('oro', '🥇 Oro Eco-Leyenda'),
    ]
    chofer = models.OneToOneField(Chofer, on_delete=models.CASCADE, related_name='puntaje', verbose_name="Conductor")
    puntos_totales = models.IntegerField(default=0, verbose_name="Puntos Totales Acumulados")
    km_recorridos_totales = models.DecimalField(max_digits=8, decimal_places=2, default=0.0, verbose_name="Kilómetros Recorridos")
    jornadas_exitosas = models.IntegerField(default=0, verbose_name="Jornadas Exitosas")
    nivel = models.CharField(max_length=20, choices=NIVEL_CHOICES, default='bronce', verbose_name="Nivel Eco-Rendimiento")
    actualizado_en = models.DateTimeField(auto_now=True, verbose_name="Última Actualización")

    class Meta:
        verbose_name = "Puntaje y Gamificación de Chofer"
        verbose_name_plural = "Puntajes y Gamificación de Choferes"

    def __str__(self):
        return f"{self.chofer} - {self.puntos_totales} pts ({self.get_nivel_display()})"

class IncentivoChofer(models.Model):
    TIPO_INSIGNIA_CHOICES = [
        ('estrella', '🥇 Chofer Estrella del Mes'),
        ('eco', '🌿 Eco-Conductor Eficiente'),
        ('maestro', '🚚 Maestro del Volante'),
        ('impecable', '⚡ Ruta Impecable (0 Incidencias)'),
    ]
    chofer = models.ForeignKey(Chofer, on_delete=models.CASCADE, related_name='incentivos', verbose_name="Conductor")
    titulo = models.CharField(max_length=100, verbose_name="Título del Reconocimiento")
    descripcion = models.TextField(verbose_name="Descripción del Logro")
    tipo_insignia = models.CharField(max_length=30, choices=TIPO_INSIGNIA_CHOICES, default='eco', verbose_name="Insignia Otorgada")
    monto_bono_usd = models.DecimalField(max_digits=6, decimal_places=2, default=0.0, verbose_name="Bono de Incentivo ($)")
    otorgado_en = models.DateTimeField(default=timezone.now, verbose_name="Fecha de Otorgamiento")

    class Meta:
        verbose_name = "Incentivo / Reconocimiento a Chofer"
        verbose_name_plural = "Incentivos y Reconocimientos a Choferes"

    def __str__(self):
        return f"{self.titulo} - {self.chofer.usuario.get_full_name() or self.chofer.usuario.username}"
