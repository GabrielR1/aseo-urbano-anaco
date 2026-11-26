"""Context processors globales para las plantillas."""

from django.conf import settings


def app_settings(request):
    """Expone indicadores de entorno a las plantillas (modo demostración, versión)."""
    return {
        "debug": settings.DEBUG,
        "demo_mode": settings.DEBUG,
        "app_version": getattr(settings, "APP_VERSION", "1.0.0"),
    }
