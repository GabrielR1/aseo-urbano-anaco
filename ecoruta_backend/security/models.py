from django.db import models
from django.contrib.auth.models import AbstractUser

class Usuario(AbstractUser):
    # Definimos los roles
    ADMIN = "admin"
    CHOFER = "chofer"

    ROLES_CHOICES = [
        (ADMIN, "Administrador"),
        (CHOFER, "Chofer"),
    ]

    rol = models.CharField(
        max_length=20,
        choices=ROLES_CHOICES,
        default=ADMIN
    )

    def __str__(self):
        return f"{self.username} ({self.get_rol_display()})"