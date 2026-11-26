from django.contrib.auth.views import LoginView
from django.shortcuts import render
from django.urls import reverse

from .permissions import es_administrador


class EcoRutaLoginView(LoginView):
    """Login institucional que envía a cada rol a su panel correspondiente."""

    redirect_authenticated_user = True

    def get_success_url(self):
        destino = super().get_success_url()
        if destino.startswith('/dashboard/') and not es_administrador(self.request.user):
            return reverse('dashboard_chofer_gps')
        return destino


# Compatibilidad con la plantilla histórica de security/urls.py.
def index(request):
    return render(request, 'security/login.html')
