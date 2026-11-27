import logging

from django.contrib import messages
from django.core.exceptions import ValidationError
from django.core.validators import validate_email
from django.shortcuts import get_object_or_404, redirect
from django.views.decorators.http import require_POST

from security.models import Usuario
from security.permissions import admin_required
from security.views import enviar_correo_verificacion

from .forms import RutaForm, VehiculoForm
from .models import Chofer, RegistroAuditoria, Ruta, Vehiculo

logger = logging.getLogger(__name__)


def registrar_auditoria(usuario, accion, tabla, detalles):
    try:
        RegistroAuditoria.objects.create(
            usuario=usuario if usuario and usuario.is_authenticated else None,
            accion=accion,
            tabla_afectada=tabla,
            detalles=detalles,
        )
    except Exception:  # la auditoría nunca debe romper la operación principal
        logger.exception("No se pudo registrar la auditoría: %s / %s", accion, tabla)


@admin_required
def ruta_crear(request):
    if request.method == 'POST':
        form = RutaForm(request.POST)
        if form.is_valid():
            ruta = form.save()
            registrar_auditoria(request.user, 'CREAR', 'Ruta Ecológica', f'Se creó la ruta "{ruta.nombre}" en la zona "{ruta.zona}"')
            messages.success(request, '¡Ruta ecológica guardada exitosamente!')
        else:
            messages.error(request, 'Error al guardar la ruta. Por favor verifica los datos.')
    return redirect('dashboard_rutas')


@admin_required
def ruta_editar(request, pk):
    ruta = get_object_or_404(Ruta, pk=pk)
    if request.method == 'POST':
        form = RutaForm(request.POST, instance=ruta)
        if form.is_valid():
            ruta = form.save()
            registrar_auditoria(request.user, 'MODIFICAR', 'Ruta Ecológica', f'Se modificaron los datos de la ruta "{ruta.nombre}"')
            messages.success(request, f'¡Ruta "{ruta.nombre}" modificada correctamente!')
        else:
            messages.error(request, 'Error al modificar la ruta. Revisa los datos ingresados.')
    return redirect('dashboard_rutas')


@admin_required
@require_POST
def ruta_eliminar(request, pk):
    ruta = get_object_or_404(Ruta, pk=pk)
    if ruta.jornada_set.exists():
        messages.error(
            request,
            f'No se puede eliminar la ruta "{ruta.nombre}" porque tiene jornadas asociadas.',
        )
        return redirect('dashboard_rutas')
    nombre_ruta = ruta.nombre
    ruta.delete()
    registrar_auditoria(request.user, 'ELIMINAR', 'Ruta Ecológica', f'Se eliminó la ruta "{nombre_ruta}"')
    messages.success(request, f'Ruta "{nombre_ruta}" eliminada con éxito.')
    return redirect('dashboard_rutas')


@admin_required
def vehiculo_crear(request):
    if request.method == 'POST':
        form = VehiculoForm(request.POST)
        if form.is_valid():
            vehiculo = form.save()
            registrar_auditoria(request.user, 'CREAR', 'Vehículo de Flota', f'Se registró el vehículo placa "{vehiculo.placa}" ({vehiculo.marca})')
            messages.success(request, '¡Vehículo registrado exitosamente!')
        else:
            messages.error(request, 'Error al registrar el vehículo. Verifica la placa y los datos.')
    return redirect('dashboard_recursos')


@admin_required
def vehiculo_editar(request, pk):
    vehiculo = get_object_or_404(Vehiculo, pk=pk)
    if request.method == 'POST':
        form = VehiculoForm(request.POST, instance=vehiculo)
        if form.is_valid():
            vehiculo = form.save()
            registrar_auditoria(request.user, 'MODIFICAR', 'Vehículo de Flota', f'Se actualizaron los datos del vehículo "{vehiculo.placa}"')
            messages.success(request, f'¡Vehículo "{vehiculo.placa}" actualizado correctamente!')
        else:
            messages.error(request, 'Error al actualizar el vehículo. Revisa los datos ingresados.')
    return redirect('dashboard_recursos')


@admin_required
@require_POST
def vehiculo_eliminar(request, pk):
    vehiculo = get_object_or_404(Vehiculo, pk=pk)
    if vehiculo.jornada_set.exists():
        messages.error(
            request,
            f'No se puede eliminar la unidad "{vehiculo.placa}" porque tiene jornadas asociadas.',
        )
        return redirect('dashboard_recursos')
    placa = vehiculo.placa
    vehiculo.delete()
    registrar_auditoria(request.user, 'ELIMINAR', 'Vehículo de Flota', f'Se eliminó el vehículo placa "{placa}"')
    messages.success(request, f'Vehículo "{placa}" eliminado con éxito.')
    return redirect('dashboard_recursos')


@admin_required
def chofer_crear(request):
    if request.method == 'POST':
        username = (request.POST.get('username') or '').strip()
        email = (request.POST.get('email') or '').strip().lower()
        password = request.POST.get('password') or 'chofer123'
        first_name = (request.POST.get('first_name') or '').strip()
        last_name = (request.POST.get('last_name') or '').strip()
        licencia = (request.POST.get('licencia') or '').strip()
        telefono = (request.POST.get('telefono') or '').strip()

        if not (username and licencia):
            messages.error(request, 'Por favor completa los campos requeridos de usuario y licencia.')
            return redirect('dashboard_conductores')

        if email:
            try:
                validate_email(email)
            except ValidationError:
                messages.error(request, 'El correo electrónico ingresado no es válido.')
                return redirect('dashboard_conductores')
            if Usuario.objects.filter(email__iexact=email).exists():
                messages.error(request, f'El correo "{email}" ya está registrado en otra cuenta.')
                return redirect('dashboard_conductores')

        if Usuario.objects.filter(username=username).exists():
            messages.error(request, f'El usuario "{username}" ya existe.')
        elif Chofer.objects.filter(licencia=licencia).exists():
            messages.error(request, f'La licencia "{licencia}" ya está registrada.')
        else:
            user = Usuario.objects.create_user(
                username=username,
                email=email,
                password=password,
                first_name=first_name,
                last_name=last_name,
                rol=Usuario.CHOFER,
                email_verificado=False,
            )
            Chofer.objects.create(usuario=user, licencia=licencia, telefono=telefono)
            registrar_auditoria(request.user, 'CREAR', 'Conductor / Chofer', f'Se creó el perfil de chofer para el usuario "{username}"')
            if email:
                try:
                    enviar_correo_verificacion(request, user)
                    messages.success(
                        request,
                        f'Conductor "{username}" registrado. Se envió un enlace de verificación a {email}.',
                    )
                except Exception:
                    logger.exception('No se pudo enviar verificación al registrar %s', username)
                    messages.warning(
                        request,
                        f'Conductor "{username}" registrado, pero no se pudo enviar el correo de verificación. Verifica la configuración de correo y usa "Reenviar".',
                    )
            else:
                messages.success(request, f'Conductor "{username}" registrado exitosamente.')
    return redirect('dashboard_conductores')


@admin_required
def chofer_editar(request, pk):
    chofer = get_object_or_404(Chofer, pk=pk)
    if request.method == 'POST':
        licencia = (request.POST.get('licencia') or '').strip()
        telefono = (request.POST.get('telefono') or '').strip()
        first_name = (request.POST.get('first_name') or '').strip()
        last_name = (request.POST.get('last_name') or '').strip()
        email = (request.POST.get('email') or '').strip().lower()

        if not licencia:
            messages.error(request, 'La licencia no puede estar vacía.')
            return redirect('dashboard_conductores')

        if Chofer.objects.filter(licencia=licencia).exclude(pk=chofer.pk).exists():
            messages.error(request, f'La licencia "{licencia}" ya está asignada a otro conductor.')
            return redirect('dashboard_conductores')

        if email:
            try:
                validate_email(email)
            except ValidationError:
                messages.error(request, 'El correo electrónico ingresado no es válido.')
                return redirect('dashboard_conductores')
            if Usuario.objects.filter(email__iexact=email).exclude(pk=chofer.usuario_id).exists():
                messages.error(request, f'El correo "{email}" ya está registrado en otra cuenta.')
                return redirect('dashboard_conductores')

        chofer.licencia = licencia
        chofer.telefono = telefono
        chofer.save(update_fields=['licencia', 'telefono', 'actualizado_en'])

        user = chofer.usuario
        email_cambio = (user.email or '').strip().lower() != email
        user.first_name = first_name
        user.last_name = last_name
        user.email = email
        if email_cambio or not email:
            user.email_verificado = False
        user.save(update_fields=['first_name', 'last_name', 'email', 'email_verificado'])

        registrar_auditoria(request.user, 'MODIFICAR', 'Conductor / Chofer', f'Se modificaron los datos del conductor "{user.username}"')
        if email and email_cambio:
            try:
                enviar_correo_verificacion(request, user)
                messages.success(
                    request,
                    f'Datos actualizados. Se envió un enlace de verificación a {email}.',
                )
            except Exception:
                logger.exception('No se pudo enviar verificación al actualizar %s', user.username)
                messages.warning(
                    request,
                    f'Datos actualizados, pero no se pudo enviar el correo de verificación a {email}.',
                )
        else:
            messages.success(request, f'Datos del conductor "{user.username}" actualizados.')
    return redirect('dashboard_conductores')


@admin_required
@require_POST
def chofer_reenviar_verificacion(request, pk):
    chofer = get_object_or_404(Chofer.objects.select_related('usuario'), pk=pk)
    user = chofer.usuario
    if not (user.email or '').strip():
        messages.error(request, f'El conductor "{user.username}" no tiene un correo registrado.')
        return redirect('dashboard_conductores')
    try:
        enviar_correo_verificacion(request, user)
        messages.success(request, f'Enlace de verificación reenviado a {user.email}.')
    except Exception:
        logger.exception('Error reenviando correo de verificación a %s', user.email)
        messages.error(request, 'No se pudo enviar el correo de verificación. Revisa el servicio de correo en Render.')
    return redirect('dashboard_conductores')


@admin_required
@require_POST
def chofer_eliminar(request, pk):
    chofer = get_object_or_404(Chofer, pk=pk)
    if chofer.jornada_set.exists():
        messages.error(
            request,
            'No se puede eliminar al conductor porque tiene jornadas asociadas en el historial.',
        )
        return redirect('dashboard_conductores')
    if chofer.usuario.is_superuser:
        messages.error(request, 'No se puede eliminar la cuenta de un superusuario.')
        return redirect('dashboard_conductores')

    username = chofer.usuario.username
    user = chofer.usuario
    chofer.delete()
    user.delete()
    registrar_auditoria(request.user, 'ELIMINAR', 'Conductor / Chofer', f'Se eliminó al conductor y usuario "{username}"')
    messages.success(request, f'Conductor "{username}" eliminado exitosamente.')
    return redirect('dashboard_conductores')
