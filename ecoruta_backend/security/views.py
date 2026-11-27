import logging

from django.conf import settings
from django.contrib.auth import get_user_model
from django.contrib.auth.forms import PasswordResetForm
from django.contrib.auth.views import LoginView
from django.core.exceptions import ValidationError
from django.core.mail import send_mail
from django.core.signing import BadSignature, SignatureExpired, TimestampSigner
from django.core.validators import validate_email
from django.shortcuts import render
from django.urls import reverse
from rest_framework import status
from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import AllowAny
from rest_framework.response import Response

from .permissions import es_administrador

logger = logging.getLogger(__name__)

EMAIL_VERIFY_SALT = 'ecoruta-email-verify'
EMAIL_VERIFY_MAX_AGE_SECONDS = 60 * 60 * 48  # 48 horas


def generar_token_verificacion_correo(user):
    signer = TimestampSigner(salt=EMAIL_VERIFY_SALT)
    return signer.sign(f'{user.pk}:{(user.email or "").strip().lower()}')


def enviar_correo_verificacion(request, user):
    """Envía el correo con enlace firmado de verificación al usuario."""
    email = (user.email or '').strip().lower()
    if not email:
        return False
    token = generar_token_verificacion_correo(user)
    verify_url = request.build_absolute_uri(reverse('verificar_correo', args=[token]))
    nombre = user.get_full_name() or user.username
    cuerpo = (
        f'Hola {nombre},\n\n'
        f'Tu cuenta de conductor (@{user.username}) fue registrada en Aseo Urbano Anaco.\n\n'
        f'Para confirmar que este correo es correcto y habilitar la recuperación de contraseña, '
        f'abre el siguiente enlace (válido por 48 horas):\n'
        f'{verify_url}\n\n'
        f'Dirección de Aseo Urbano\n'
        f'Alcaldía del Municipio Bolivariano Anaco\n'
    )
    send_mail(
        subject='Verifica tu correo - Aseo Urbano Anaco',
        message=cuerpo,
        from_email=settings.DEFAULT_FROM_EMAIL,
        recipient_list=[email],
        fail_silently=False,
    )
    return True


def verificar_correo_view(request, token):
    """Confirma el correo electrónico del usuario a partir del enlace firmado."""
    signer = TimestampSigner(salt=EMAIL_VERIFY_SALT)
    Usuario = get_user_model()
    verificado = False
    email_mostrado = ''
    username_mostrado = ''

    try:
        raw = signer.unsign(token, max_age=EMAIL_VERIFY_MAX_AGE_SECONDS)
        user_id_str, email_token = raw.split(':', 1)
        user = Usuario.objects.filter(pk=int(user_id_str)).first()
        if user and (user.email or '').strip().lower() == email_token:
            if not user.email_verificado:
                user.email_verificado = True
                user.save(update_fields=['email_verificado'])
            verificado = True
            email_mostrado = user.email
            username_mostrado = user.username
    except (BadSignature, SignatureExpired, ValueError, TypeError):
        verificado = False

    return render(
        request,
        'registration/email_verified.html',
        {
            'verificado': verificado,
            'email': email_mostrado,
            'username': username_mostrado,
        },
    )


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
