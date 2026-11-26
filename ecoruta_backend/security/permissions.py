"""Utilidades de autorización compartidas por el panel web y la API."""

from functools import wraps

from django.contrib.auth.views import redirect_to_login
from django.core.exceptions import PermissionDenied
from django.utils.http import url_has_allowed_host_and_scheme
from rest_framework.permissions import BasePermission


def es_administrador(user):
    """Devuelve True para usuarios con rol administrativo habilitado."""
    if not getattr(user, "is_authenticated", False):
        return False
    return bool(
        user.is_superuser
        or user.is_staff
        or getattr(user, "rol", None) == "admin"
    )


def admin_required(view_func):
    """
    Restringe una vista del panel web a usuarios administrativos.

    - Sin sesión: redirige al login conservando ``next``.
    - Con sesión pero sin permisos: responde 403 (plantilla ``403.html``).
    """
    @wraps(view_func)
    def _wrapped(request, *args, **kwargs):
        if not request.user.is_authenticated:
            next_url = request.get_full_path()
            if not url_has_allowed_host_and_scheme(
                next_url, allowed_hosts={request.get_host()}, require_https=request.is_secure()
            ):
                next_url = "/dashboard/"
            return redirect_to_login(next_url)
        if not es_administrador(request.user):
            raise PermissionDenied(
                "Esta sección está reservada al personal administrativo. "
                "Si eres conductor, utiliza el panel de ruta móvil."
            )
        return view_func(request, *args, **kwargs)

    return _wrapped


class EsAdministrador(BasePermission):
    """Permite el acceso únicamente a personal administrativo."""

    message = "Esta operación requiere permisos de administrador."

    def has_permission(self, request, view):
        return es_administrador(request.user)
