from django.shortcuts import render, redirect, get_object_or_404
from django.contrib.auth.decorators import login_required
from django.contrib import messages
from administracion.models import Vehiculo, Ruta, RegistroCombustible, Chofer
from logistica.models import Jornada, Incidencia
import django.utils.timezone

@login_required
def dashboard_home(request):
    vehiculos_activos = Vehiculo.objects.filter(estado='activo').count()
    jornadas_hoy = Jornada.objects.filter(fecha=django.utils.timezone.now().date()).count()
    incidencias_hoy = Incidencia.objects.filter(timestamp__date=django.utils.timezone.now().date()).count()
    
    context = {
        'vehiculos_activos': vehiculos_activos,
        'jornadas_hoy': jornadas_hoy,
        'incidencias_hoy': incidencias_hoy,
    }
    return render(request, 'dashboard/home.html', context)

@login_required
def rutas_gestion(request):
    rutas = Ruta.objects.all().order_by('nombre')
    context = {
        'rutas': rutas
    }
    return render(request, 'dashboard/rutas.html', context)

@login_required
def conductores_gestion(request):
    choferes = Chofer.objects.select_related('usuario').all()
    context = {
        'choferes': choferes
    }
    return render(request, 'dashboard/conductores.html', context)

@login_required
def itinerario(request):
    jornadas = Jornada.objects.all().order_by('-fecha')
    rutas = Ruta.objects.all()
    vehiculos = Vehiculo.objects.all()
    choferes = Chofer.objects.all()
    context = {
        'jornadas': jornadas,
        'rutas': rutas,
        'vehiculos': vehiculos,
        'choferes': choferes
    }
    return render(request, 'dashboard/itinerario.html', context)

@login_required
def jornada_crear(request):
    if request.method == 'POST':
        vehiculo_id = request.POST.get('vehiculo')
        ruta_id = request.POST.get('ruta')
        chofer_id = request.POST.get('chofer')
        fecha = request.POST.get('fecha')
        
        vehiculo = get_object_or_404(Vehiculo, pk=vehiculo_id)
        ruta = get_object_or_404(Ruta, pk=ruta_id)
        
        chofer = Chofer.objects.filter(pk=chofer_id).first() if chofer_id else Chofer.objects.first()
        
        if chofer and fecha:
            Jornada.objects.create(
                vehiculo=vehiculo,
                ruta=ruta,
                chofer=chofer,
                fecha=fecha,
                estado='pendiente'
            )
            messages.success(request, '¡Jornada de recolección asignada correctamente!')
        else:
            messages.error(request, 'Error al asignar la jornada. Asegúrate de registrar un chofer previamente.')
            
    return redirect('dashboard_itinerario')

@login_required
def jornada_eliminar(request, pk):
    jornada = get_object_or_404(Jornada, pk=pk)
    if request.method == 'POST':
        jornada.delete()
        messages.success(request, 'Jornada de recolección eliminada.')
    return redirect('dashboard_itinerario')

@login_required
def mapa_monitoreo(request):
    return render(request, 'dashboard/mapa.html')

@login_required
def recursos(request):
    registros = RegistroCombustible.objects.all().order_by('-fecha')
    vehiculos = Vehiculo.objects.all()
    
    # Métricas dinámicas
    total_litros = sum(r.litros for r in registros) if registros else 0
    costo_total = sum(r.costo_total for r in registros) if registros else 0
    rendimiento_prom = (sum(v.rendimiento_km_por_litro for v in vehiculos) / vehiculos.count()) if vehiculos.exists() else 0
    
    context = {
        'registros': registros,
        'vehiculos': vehiculos,
        'total_litros': round(total_litros, 2),
        'costo_total': round(costo_total, 2),
        'rendimiento_prom': round(rendimiento_prom, 1)
    }
    return render(request, 'dashboard/recursos.html', context)

@login_required
def recurso_crear(request):
    if request.method == 'POST':
        vehiculo_id = request.POST.get('vehiculo')
        litros = request.POST.get('litros')
        costo_total = request.POST.get('costo_total')
        kilometraje = request.POST.get('kilometraje', 0)
        
        vehiculo = get_object_or_404(Vehiculo, pk=vehiculo_id)
        if litros and costo_total:
            RegistroCombustible.objects.create(
                vehiculo=vehiculo,
                litros=litros,
                costo_total=costo_total,
                kilometraje_actual=kilometraje
            )
            messages.success(request, '¡Registro de combustible guardado exitosamente!')
        else:
            messages.error(request, 'Por favor completa los campos de litros y costo.')
            
    return redirect('dashboard_recursos')

@login_required
def recurso_eliminar(request, pk):
    registro = get_object_or_404(RegistroCombustible, pk=pk)
    if request.method == 'POST':
        registro.delete()
        messages.success(request, 'Registro de combustible eliminado.')
    return redirect('dashboard_recursos')
