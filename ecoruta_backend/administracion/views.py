from django.shortcuts import render, redirect, get_object_or_404
from django.contrib.auth.decorators import login_required
from django.contrib import messages
from .models import Ruta, Vehiculo, Chofer
from security.models import Usuario
from .forms import RutaForm, VehiculoForm

@login_required
def ruta_crear(request):
    if request.method == 'POST':
        form = RutaForm(request.POST)
        if form.is_valid():
            form.save()
            messages.success(request, '¡Ruta ecológica guardada exitosamente!')
        else:
            messages.error(request, 'Error al guardar la ruta. Por favor verifica los datos.')
    return redirect('dashboard_rutas')

@login_required
def ruta_editar(request, pk):
    ruta = get_object_or_404(Ruta, pk=pk)
    if request.method == 'POST':
        form = RutaForm(request.POST, instance=ruta)
        if form.is_valid():
            form.save()
            messages.success(request, f'¡Ruta "{ruta.nombre}" modificada correctamente!')
        else:
            messages.error(request, 'Error al modificar la ruta.')
    return redirect('dashboard_rutas')

@login_required
def ruta_eliminar(request, pk):
    ruta = get_object_or_404(Ruta, pk=pk)
    if request.method == 'POST':
        nombre_ruta = ruta.nombre
        ruta.delete()
        messages.success(request, f'Ruta "{nombre_ruta}" eliminada con éxito.')
    return redirect('dashboard_rutas')

@login_required
def vehiculo_crear(request):
    if request.method == 'POST':
        form = VehiculoForm(request.POST)
        if form.is_valid():
            form.save()
            messages.success(request, '¡Vehículo registrado exitosamente!')
        else:
            messages.error(request, 'Error al registrar el vehículo.')
    return redirect('dashboard_recursos')

@login_required
def vehiculo_editar(request, pk):
    vehiculo = get_object_or_404(Vehiculo, pk=pk)
    if request.method == 'POST':
        form = VehiculoForm(request.POST, instance=vehiculo)
        if form.is_valid():
            form.save()
            messages.success(request, f'¡Vehículo "{vehiculo.placa}" actualizado correctamente!')
        else:
            messages.error(request, 'Error al actualizar el vehículo.')
    return redirect('dashboard_recursos')

@login_required
def vehiculo_eliminar(request, pk):
    vehiculo = get_object_or_404(Vehiculo, pk=pk)
    if request.method == 'POST':
        placa = vehiculo.placa
        vehiculo.delete()
        messages.success(request, f'Vehículo "{placa}" eliminado con éxito.')
    return redirect('dashboard_recursos')

@login_required
def chofer_crear(request):
    if request.method == 'POST':
        username = request.POST.get('username')
        password = request.POST.get('password', 'chofer123')
        first_name = request.POST.get('first_name', '')
        last_name = request.POST.get('last_name', '')
        licencia = request.POST.get('licencia')
        telefono = request.POST.get('telefono', '')

        if username and licencia:
            if Usuario.objects.filter(username=username).exists():
                messages.error(request, f'El usuario "{username}" ya existe.')
            elif Chofer.objects.filter(licencia=licencia).exists():
                messages.error(request, f'La licencia "{licencia}" ya está registrada.')
            else:
                user = Usuario.objects.create_user(
                    username=username,
                    password=password,
                    first_name=first_name,
                    last_name=last_name,
                    rol=Usuario.CHOFER
                )
                Chofer.objects.create(usuario=user, licencia=licencia, telefono=telefono)
                messages.success(request, f'¡Chofer/Conductor "{username}" registrado exitosamente!')
        else:
            messages.error(request, 'Por favor completa los campos requeridos de usuario y licencia.')
    return redirect('dashboard_conductores')

@login_required
def chofer_editar(request, pk):
    chofer = get_object_or_404(Chofer, pk=pk)
    if request.method == 'POST':
        licencia = request.POST.get('licencia')
        telefono = request.POST.get('telefono', '')
        first_name = request.POST.get('first_name', '')
        last_name = request.POST.get('last_name', '')

        chofer.licencia = licencia
        chofer.telefono = telefono
        chofer.save()

        user = chofer.usuario
        user.first_name = first_name
        user.last_name = last_name
        user.save()

        messages.success(request, f'¡Datos del conductor "{user.username}" modificados con éxito!')
    return redirect('dashboard_conductores')

@login_required
def chofer_eliminar(request, pk):
    chofer = get_object_or_404(Chofer, pk=pk)
    if request.method == 'POST':
        username = chofer.usuario.username
        user = chofer.usuario
        chofer.delete()
        user.delete()
        messages.success(request, f'Conductor "{username}" eliminado exitosamente.')
    return redirect('dashboard_conductores')
