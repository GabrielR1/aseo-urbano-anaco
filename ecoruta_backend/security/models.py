from django.db import models
from django.contrib.auth.models import AbstractUser
from django.utils import timezone


class Rol(models.Model):
    nombre = models.CharField(max_length=50, unique=True, verbose_name="Nombre del Rol")
    descripcion = models.CharField(max_length=150, blank=True, verbose_name="Descripción")
    creado_en = models.DateTimeField(default=timezone.now, verbose_name="Fecha de Creación")

    class Meta:
        verbose_name = "Rol de Usuario"
        verbose_name_plural = "Roles del Sistema"

    def __str__(self):
        return self.nombre


class Usuario(AbstractUser):
    ADMIN = "admin"
    CHOFER = "chofer"

    ROLES_CHOICES = [
        (ADMIN, "Administrador"),
        (CHOFER, "Chofer / Conductor"),
    ]

    rol_ref = models.ForeignKey(
        Rol,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="usuarios",
        verbose_name="Rol (Tabla Normalizada)"
    )
    rol = models.CharField(
        max_length=20,
        choices=ROLES_CHOICES,
        default=ADMIN,
        verbose_name="Rol en el Sistema"
    )
    email_verificado = models.BooleanField(
        default=False,
        verbose_name="Correo Verificado"
    )

    class Meta:
        verbose_name = "Usuario"
        verbose_name_plural = "Usuarios del Sistema"

    def save(self, *args, **kwargs):
        # Asignar permisos de acceso al panel Django Admin según el rol
        if self.rol == self.ADMIN:
            self.is_staff = True
        elif self.rol == self.CHOFER and not self.is_superuser:
            self.is_staff = False
        super().save(*args, **kwargs)

    def __str__(self):
        return f"{self.username} ({self.get_rol_display()})"