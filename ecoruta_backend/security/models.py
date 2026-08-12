from django.db import models
from django.contrib.auth.models import AbstractUser

class Usuario(AbstractUser):
    ADMIN = "admin"
    CHOFER = "chofer"

    ROLES_CHOICES = [
        (ADMIN, "Administrador"),
        (CHOFER, "Chofer / Conductor"),
    ]

    rol = models.CharField(
        max_length=20,
        choices=ROLES_CHOICES,
        default=ADMIN,
        verbose_name="Rol en el Sistema"
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