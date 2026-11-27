import logging

from django.conf import settings
from django.contrib.auth.forms import PasswordResetForm
from django.contrib.auth.views import LoginView
from django.core.exceptions import ValidationError
from django.core.validators import validate_email
from django.urls import reverse
from rest_framework import status
from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import AllowAny
from rest_framework.response import Response

from .permissions import es_administrador

logger = logging.getLogger(__name__)


class EcoRutaLoginView(LoginView):
    """Login institucional que envía a cada rol a su panel correspondiente."""

    redirect_authenticated_user = True

    def get_success_url(self):
        destino = super().get_success_url()
        if destino.startswith('/dashboard/') and not es_administrador(self.request.user):
            return reverse('dashboard_chofer_gps')
        return destino


@api_view(['POST'])
@permission_classes([AllowAny])
def api_password_reset_request(request):
    """Solicita el correo de recuperación de contraseña desde la app móvil."""
    email = (request.data.get('email') or '').strip().lower()
    if not email:
        return Response(
            {'detail': 'Ingresa tu correo electrónico.'},
            status=status.HTTP_400_BAD_REQUEST,
        )
    try:
        validate_email(email)
    except ValidationError:
        return Response(
            {'detail': 'El correo electrónico no tiene un formato válido.'},
            status=status.HTTP_400_BAD_REQUEST,
        )

    form = PasswordResetForm({'email': email})
    if form.is_valid():
        try:
            form.save(
                request=request,
                use_https=request.is_secure(),
                from_email=settings.DEFAULT_FROM_EMAIL,
                email_template_name='registration/password_reset_email.html',
                subject_template_name='registration/password_reset_subject.txt',
            )
        except Exception:
            logger.exception('No se pudo enviar el correo de recuperación a %s', email)
            return Response(
                {'detail': 'El servicio de correo no está disponible en este momento. Intenta más tarde.'},
                status=status.HTTP_503_SERVICE_UNAVAILABLE,
            )

    return Response(
        {'mensaje': 'Si el correo está registrado, recibirás un enlace para restablecer tu contraseña.'},
        status=status.HTTP_200_OK,
    )
