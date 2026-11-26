from datetime import timedelta
from decimal import Decimal, InvalidOperation

import django.utils.timezone
from django.contrib import messages
from django.contrib.auth.decorators import login_required
from django.db.models import Avg, Prefetch, Sum
from django.http import HttpResponse
from django.shortcuts import get_object_or_404, redirect, render
from django.utils.dateparse import parse_date
from django.utils.http import url_has_allowed_host_and_scheme

import openpyxl
from openpyxl.styles import Alignment, Font, PatternFill

from reportlab.lib import colors
from reportlab.lib.pagesizes import letter
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.platypus import HRFlowable, Paragraph, SimpleDocTemplate, Spacer, Table, TableStyle

from administracion.models import (
    Chofer,
    IncentivoChofer,
    PuntajeChofer,
    RegistroAuditoria,
    RegistroCombustible,
    Ruta,
    Vehiculo,
)
from logistica.gamificacion import evaluar_y_actualizar_puntaje_chofer
from logistica.models import Incidencia, Jornada, PuntoGeolocalizacion
from logistica.services import serializar_camion, serializar_incidencia
from security.permissions import admin_required, es_administrador


def _prefetch_puntos():
    return Prefetch(
        'puntos',
        queryset=PuntoGeolocalizacion.objects.order_by('timestamp', 'id'),
    )


def _parse_coordenada(valor):
    """Convierte una coordenada de formulario en Decimal o None si no es válida."""
    texto = (valor or '').strip()
    if not texto:
        return None
    try:
        numero = Decimal(texto)
    except (InvalidOperation, ValueError, TypeError):
        return None
    if not Decimal('-180') <= numero <= Decimal('180'):
        return None
    return numero


def _parse_entero(valor):
    """Convierte un identificador de formulario en entero o None."""
    try:
        return int(str(valor).strip())
    except (TypeError, ValueError):
        return None


def _redirigir_seguro(request, destino, fallback):
    """Redirige a ``destino`` solo si pertenece al mismo host; si no, usa ``fallback``."""
    if destino and url_has_allowed_host_and_scheme(
        destino,
        allowed_hosts={request.get_host()},
        require_https=request.is_secure(),
    ):
        return redirect(destino)
    return redirect(fallback)


@login_required
def dashboard_home(request):
    if not es_administrador(request.user):
        # Los conductores tienen su propio panel móvil de ruta.
        return redirect('dashboard_chofer_gps')

    ahora_local = django.utils.timezone.localtime(django.utils.timezone.now())
    hoy = ahora_local.date()

    # Flota (datos reales)
    total_vehiculos = Vehiculo.objects.count()
    vehiculos_activos = Vehiculo.objects.filter(estado='activo').count()
    vehiculos_mantenimiento = Vehiculo.objects.filter(estado='mantenimiento').count()
    tasa_disponibilidad = round((vehiculos_activos / total_vehiculos * 100), 1) if total_vehiculos else 0.0

    # Jornadas de recolección (datos reales)
    jornadas_hoy = Jornada.objects.filter(fecha=hoy).count()
    jornadas_activas = Jornada.objects.filter(estado='en_curso').count()

    # Kilometraje real medido por trazas GPS (Haversine) — sin valores simulados
    todas_jornadas = list(
        Jornada.objects.select_related('ruta', 'vehiculo')
        .prefetch_related(_prefetch_puntos())
        .all()
    )
    km_por_jornada = {j.id: j.calcular_distancia_real_km() for j in todas_jornadas}
    km_acumulados = round(sum(km_por_jornada.values()), 2)
    total_puntos_gps = PuntoGeolocalizacion.objects.count()

    # Combustible despachado (Litros reales registrados — 0.0 si no hay cargas)
    totales_combustible = RegistroCombustible.objects.aggregate(total=Sum('litros'))
    total_litros = round(float(totales_combustible['total'] or 0), 1)

    # Incidencias reales
    incidencias_pendientes = Incidencia.objects.filter(estado='pendiente').count()
    incidencias_hoy = Incidencia.objects.filter(timestamp__date=hoy).count()

    # Listas para el resumen
    ultimas_jornadas = Jornada.objects.select_related('vehiculo', 'ruta', 'chofer', 'chofer__usuario').order_by('-id')[:5]
    alertas_recientes = Incidencia.objects.select_related('jornada', 'jornada__vehiculo').order_by('-timestamp')[:5]
    flota_unidades = Vehiculo.objects.all().order_by('placa')
    total_rutas = Ruta.objects.count()

    # Gráfico semanal 100% REAL (Semana actual: Lunes a Domingo)
    dias_semana = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom']
    inicio_semana = hoy - timedelta(days=hoy.weekday())
    fin_semana = inicio_semana + timedelta(days=6)

    datos_toneladas = [0.0] * 7
    datos_km_semana = [0.0] * 7

    for j in todas_jornadas:
        fecha_ref = django.utils.timezone.localtime(j.fin_real).date() if j.fin_real else j.fecha
        if inicio_semana <= fecha_ref <= fin_semana:
            idx = fecha_ref.weekday()
            datos_toneladas[idx] = round(datos_toneladas[idx] + float(j.toneladas_recolectadas or 0), 2)
            datos_km_semana[idx] = round(datos_km_semana[idx] + km_por_jornada.get(j.id, 0.0), 2)

    total_toneladas_semana = round(sum(datos_toneladas), 2)
    total_km_semana = round(sum(datos_km_semana), 2)

    context = {
        'total_vehiculos': total_vehiculos,
        'vehiculos_activos': vehiculos_activos,
        'vehiculos_mantenimiento': vehiculos_mantenimiento,
        'tasa_disponibilidad': tasa_disponibilidad,
        'jornadas_hoy': jornadas_hoy,
        'jornadas_activas': jornadas_activas,
        'km_acumulados': km_acumulados,
        'total_puntos_gps': total_puntos_gps,
        'total_litros': total_litros,
        'incidencias_pendientes': incidencias_pendientes,
        'incidencias_hoy': incidencias_hoy,
        'total_rutas': total_rutas,
        'ultimas_jornadas': ultimas_jornadas,
        'alertas_recientes': alertas_recientes,
        'flota_unidades': flota_unidades,
        'dias_semana': dias_semana,
        'datos_toneladas': datos_toneladas,
        'datos_km_semana': datos_km_semana,
        'total_toneladas_semana': total_toneladas_semana,
        'total_km_semana': total_km_semana,
        'inicio_semana': inicio_semana,
        'fin_semana': fin_semana,
    }
    return render(request, 'dashboard/home.html', context)


@admin_required
def rutas_gestion(request):
    rutas = Ruta.objects.all().order_by('nombre')
    vehiculos = Vehiculo.objects.all().order_by('placa')
    choferes = Chofer.objects.select_related('usuario').all()
    hoy = django.utils.timezone.now().date()
    context = {
        'rutas': rutas,
        'vehiculos': vehiculos,
        'choferes': choferes,
        'hoy': hoy,
    }
    return render(request, 'dashboard/rutas.html', context)


@admin_required
def auditoria_listado(request):
    logs = RegistroAuditoria.objects.select_related('usuario').all().order_by('-timestamp')[:100]
    context = {
        'logs': logs
    }
    return render(request, 'dashboard/auditoria.html', context)

@admin_required
def incentivos_listado(request):
    choferes = Chofer.objects.select_related('usuario').all()
    for c in choferes:
        evaluar_y_actualizar_puntaje_chofer(c)
        
    ranking = PuntajeChofer.objects.select_related('chofer', 'chofer__usuario').order_by('-puntos_totales')
    recent_incentivos = IncentivoChofer.objects.select_related('chofer', 'chofer__usuario').order_by('-otorgado_en')[:20]
    
    context = {
        'ranking': ranking,
        'recent_incentivos': recent_incentivos
    }
    return render(request, 'dashboard/incentivos.html', context)

@admin_required
def conductores_gestion(request):
    choferes = Chofer.objects.select_related('usuario').all()
    context = {
        'choferes': choferes
    }
    return render(request, 'dashboard/conductores.html', context)

@admin_required
def itinerario(request):
    jornadas = Jornada.objects.select_related('vehiculo', 'ruta', 'chofer', 'chofer__usuario').all().order_by('-fecha', '-id')
    rutas = Ruta.objects.all().order_by('nombre')
    vehiculos = Vehiculo.objects.all().order_by('placa')
    choferes = Chofer.objects.select_related('usuario').all()
    hoy = django.utils.timezone.now().date()
    context = {
        'jornadas': jornadas,
        'rutas': rutas,
        'vehiculos': vehiculos,
        'choferes': choferes,
        'hoy': hoy,
    }
    return render(request, 'dashboard/itinerario.html', context)

@admin_required
def jornada_crear(request):
    if request.method == 'POST':
        vehiculo_id = request.POST.get('vehiculo')
        ruta_id = request.POST.get('ruta')
        chofer_id = request.POST.get('chofer')
        fecha_raw = (request.POST.get('fecha') or '').strip()
        fecha = parse_date(fecha_raw) if fecha_raw else django.utils.timezone.localdate()
        next_url = request.POST.get('next_url')

        if fecha is None:
            messages.error(request, 'La fecha indicada no es válida.')
            return _redirigir_seguro(request, next_url, 'dashboard_itinerario')

        vehiculo = Vehiculo.objects.filter(pk=_parse_entero(vehiculo_id)).first()
        ruta = Ruta.objects.filter(pk=_parse_entero(ruta_id)).first()
        chofer_pk = _parse_entero(chofer_id)
        chofer = Chofer.objects.filter(pk=chofer_pk).first() if chofer_pk else Chofer.objects.first()

        if not vehiculo or not ruta:
            messages.error(request, 'Debes seleccionar una ruta y un vehículo válidos.')
            return _redirigir_seguro(request, next_url, 'dashboard_itinerario')

        if chofer:
            jornada = Jornada.objects.create(
                vehiculo=vehiculo,
                ruta=ruta,
                chofer=chofer,
                fecha=fecha,
                estado='pendiente'
            )
            # Registro en auditoría
            RegistroAuditoria.objects.create(
                usuario=request.user,
                accion='CREAR',
                tabla_afectada='Jornada Asignada',
                detalles=f"Asignación de ruta '{ruta.nombre}' a la unidad [{vehiculo.placa}] con el conductor '{chofer.usuario.get_full_name() or chofer.usuario.username}'. (Rastreo GPS mediante el teléfono móvil del chofer)"
            )
            messages.success(request, f'¡Ruta "{ruta.nombre}" asignada con éxito al camión [{vehiculo.placa}] con el conductor {chofer.usuario.get_full_name() or chofer.usuario.username}! El seguimiento satelital rastreará el móvil del chofer.')
        else:
            messages.error(request, 'Error al asignar el recorrido. Verifica que haya conductores registrados en el sistema.')

        return _redirigir_seguro(request, next_url, 'dashboard_itinerario')

    return redirect('dashboard_itinerario')


@admin_required
def jornada_eliminar(request, pk):
    jornada = get_object_or_404(Jornada, pk=pk)
    next_url = request.POST.get('next_url')
    if request.method == 'POST':
        if jornada.estado == 'en_curso':
            messages.error(request, 'No se puede eliminar una jornada que está en curso.')
            return _redirigir_seguro(request, next_url, 'dashboard_itinerario')
        ruta_nombre = jornada.ruta.nombre
        placa = jornada.vehiculo.placa
        jornada.delete()
        RegistroAuditoria.objects.create(
            usuario=request.user,
            accion='ELIMINAR',
            tabla_afectada='Jornada Asignada',
            detalles=f"Cancelada la jornada de la ruta '{ruta_nombre}' con unidad [{placa}]"
        )
        messages.success(request, f'Jornada de la ruta "{ruta_nombre}" cancelada correctamente.')
    return _redirigir_seguro(request, next_url, 'dashboard_itinerario')


@admin_required
def mapa_monitoreo(request):
    jornadas = (
        Jornada.objects.select_related('vehiculo', 'ruta', 'chofer', 'chofer__usuario')
        .filter(estado__in=['en_curso', 'pendiente'])
        .prefetch_related(_prefetch_puntos())
        .order_by('-id')
    )
    incidencias = list(
        Incidencia.objects.select_related(
            'jornada', 'jornada__vehiculo', 'jornada__chofer', 'jornada__chofer__usuario'
        ).order_by('-timestamp')
    )

    camiones_lista = [serializar_camion(j) for j in jornadas]

    incidencias_lista = [
        serializar_incidencia(inc)
        for inc in incidencias
        if inc.latitud is not None and inc.longitud is not None
    ]

    context = {
        'camiones': camiones_lista,
        'incidencias': incidencias,
        'incidencias_lista': incidencias_lista,
        'total_camiones': len(camiones_lista),
        'total_con_gps': sum(1 for c in camiones_lista if c['tiene_gps']),
        'total_incidencias': len(incidencias),
        'rutas': Ruta.objects.all().order_by('nombre'),
        'vehiculos': Vehiculo.objects.all().order_by('placa'),
        'choferes': Chofer.objects.select_related('usuario').all(),
        'hoy': django.utils.timezone.localtime(django.utils.timezone.now()).date(),
    }
    return render(request, 'dashboard/mapa.html', context)


@login_required
def chofer_gps_movil(request):
    """
    Interfaz web móvil (PWA-friendly) para que el chofer transmita el GPS real
    de su teléfono directamente desde Chrome o Safari sobre HTTPS.
    """
    jornadas_qs = Jornada.objects.select_related(
        'vehiculo', 'ruta', 'chofer', 'chofer__usuario'
    ).filter(estado__in=['en_curso', 'pendiente']).order_by('-id')

    es_admin = es_administrador(request.user)
    if not es_admin:
        jornadas_qs = jornadas_qs.filter(chofer__usuario=request.user)

    jornadas_ordenadas = sorted(jornadas_qs, key=lambda j: (0 if j.estado == 'en_curso' else 1, -j.id))

    context = {
        'jornadas': jornadas_ordenadas,
        'es_admin': es_admin,
        'rutas': Ruta.objects.all().order_by('nombre'),
        'vehiculos': Vehiculo.objects.filter(estado='activo').order_by('placa'),
        'choferes': Chofer.objects.select_related('usuario').all(),
        'hoy': django.utils.timezone.localtime(django.utils.timezone.now()).date(),
    }
    return render(request, 'dashboard/chofer_gps.html', context)

@admin_required
def recursos(request):
    registros = RegistroCombustible.objects.select_related('vehiculo').all().order_by('-fecha')
    vehiculos = Vehiculo.objects.all()

    totales = registros.aggregate(litros=Sum('litros'), costo=Sum('costo_total'))
    promedio = vehiculos.aggregate(promedio=Avg('rendimiento_km_por_litro'))

    context = {
        'registros': registros,
        'vehiculos': vehiculos,
        'total_litros': round(float(totales['litros'] or 0), 2),
        'costo_total': round(float(totales['costo'] or 0), 2),
        'rendimiento_prom': round(float(promedio['promedio'] or 0), 1),
    }
    return render(request, 'dashboard/recursos.html', context)

@admin_required
def recurso_crear(request):
    if request.method == 'POST':
        vehiculo_id = request.POST.get('vehiculo')
        litros = request.POST.get('litros')
        costo_total = request.POST.get('costo_total')
        kilometraje = request.POST.get('kilometraje', 0)

        try:
            litros_dec = Decimal(str(litros))
            costo_dec = Decimal(str(costo_total))
            km_int = int(kilometraje or 0)
        except (InvalidOperation, ValueError, TypeError):
            messages.error(request, 'Los valores de litros, costo o kilometraje no son válidos.')
            return redirect('dashboard_recursos')

        if litros_dec <= 0 or costo_dec < 0 or km_int < 0:
            messages.error(request, 'Los litros deben ser mayores que cero y el costo no puede ser negativo.')
            return redirect('dashboard_recursos')

        vehiculo_pk = _parse_entero(vehiculo_id)
        if vehiculo_pk is None:
            messages.error(request, 'Debes seleccionar un vehículo válido.')
            return redirect('dashboard_recursos')

        vehiculo = get_object_or_404(Vehiculo, pk=vehiculo_pk)
        RegistroCombustible.objects.create(
            vehiculo=vehiculo,
            litros=litros_dec,
            costo_total=costo_dec,
            kilometraje_actual=km_int
        )
        RegistroAuditoria.objects.create(
            usuario=request.user,
            accion='CREAR',
            tabla_afectada='Registro de Combustible',
            detalles=f"Recarga de {litros_dec} L por ${costo_dec} para la unidad [{vehiculo.placa}]",
        )
        messages.success(request, '¡Registro de combustible guardado exitosamente!')

    return redirect('dashboard_recursos')

@admin_required
def recurso_eliminar(request, pk):
    registro = get_object_or_404(RegistroCombustible, pk=pk)
    if request.method == 'POST':
        registro.delete()
        messages.success(request, 'Registro de combustible eliminado.')
    return redirect('dashboard_recursos')

@admin_required
def exportar_recursos_excel(request):
    wb = openpyxl.Workbook()
    ahora_local = django.utils.timezone.localtime(django.utils.timezone.now())
    operador = request.user.get_full_name() or request.user.username

    registros = RegistroCombustible.objects.select_related('vehiculo').all().order_by('-fecha')
    vehiculos = Vehiculo.objects.all().order_by('placa')
    jornadas = (
        Jornada.objects.select_related('vehiculo', 'ruta', 'chofer', 'chofer__usuario')
        .prefetch_related(_prefetch_puntos())
        .all()
        .order_by('-fecha', '-id')
    )

    total_vehiculos = vehiculos.count()
    vehiculos_activos = vehiculos.filter(estado='activo').count()
    totales = registros.aggregate(litros=Sum('litros'), costo=Sum('costo_total'))
    total_litros = float(totales['litros'] or 0)
    costo_total = float(totales['costo'] or 0)

    header_fill = PatternFill(start_color="E5E7EB", end_color="E5E7EB", fill_type="solid")
    header_font = Font(color="000000", bold=True)
    total_fill = PatternFill(start_color="F3F4F6", end_color="F3F4F6", fill_type="solid")

    # Hoja 1: Relación de Unidades y Resumen
    ws_flota = wb.active
    ws_flota.title = "Unidades"
    ws_flota.append(["ALCALDÍA DEL MUNICIPIO ANACO - DIRECCIÓN DE ASEO URBANO"])
    ws_flota.append(["REPORTE DE UNIDADES Y COMBUSTIBLE"])
    ws_flota.append([f"Fecha: {ahora_local.strftime('%d/%m/%Y %H:%M')} | Generado por: {operador}"])
    ws_flota.append([])
    ws_flota.append(["Placa", "Marca", "Modelo", "Capacidad (Ton)", "Rendimiento (Km/L)", "Estado"])

    for cell in ws_flota[5]:
        cell.fill = header_fill
        cell.font = header_font
        cell.alignment = Alignment(horizontal="center")

    for v in vehiculos:
        ws_flota.append([
            v.placa,
            v.marca,
            v.modelo,
            float(v.capacidad_toneladas),
            float(v.rendimiento_km_por_litro),
            v.get_estado_display(),
        ])

    # Hoja 2: Registro de Combustible
    ws_detalle = wb.create_sheet(title="Combustible")
    ws_detalle.append(["ID", "Fecha y Hora", "Placa", "Marca / Modelo", "Litros", "Costo ($)", "Kilometraje"])
    for cell in ws_detalle[1]:
        cell.fill = header_fill
        cell.font = header_font
        cell.alignment = Alignment(horizontal="center")

    for r in registros:
        fecha_loc = django.utils.timezone.localtime(r.fecha).strftime("%d/%m/%Y %H:%M")
        ws_detalle.append([
            r.id,
            fecha_loc,
            r.vehiculo.placa,
            f"{r.vehiculo.marca} {r.vehiculo.modelo}",
            float(r.litros),
            float(r.costo_total),
            r.kilometraje_actual
        ])

    total_row = ["TOTAL", "-", f"{len(registros)} cargas", "-", round(total_litros, 2), round(costo_total, 2), "-"]
    ws_detalle.append(total_row)
    for cell in ws_detalle[ws_detalle.max_row]:
        cell.font = Font(bold=True)
        cell.fill = total_fill

    # Hoja 3: Jornadas
    ws_operaciones = wb.create_sheet(title="Jornadas")
    ws_operaciones.append(["Fecha", "Placa", "Ruta", "Sector", "Chofer", "Distancia GPS Real (Km)", "Toneladas (Ton)", "Estado"])
    for cell in ws_operaciones[1]:
        cell.fill = header_fill
        cell.font = header_font
        cell.alignment = Alignment(horizontal="center")

    for j in jornadas:
        ws_operaciones.append([
            j.fecha.strftime("%d/%m/%Y"),
            j.vehiculo.placa,
            j.ruta.nombre,
            j.ruta.zona,
            j.chofer.usuario.get_full_name() or j.chofer.usuario.username,
            j.calcular_distancia_real_km(),
            float(j.toneladas_recolectadas or 0),
            j.get_estado_display()
        ])

    for ws in [ws_flota, ws_detalle, ws_operaciones]:
        for col in ws.columns:
            max_len = max(len(str(cell.value or '')) for cell in col)
            col_letter = col[0].column_letter
            ws.column_dimensions[col_letter].width = max(max_len + 4, 14)

    response = HttpResponse(content_type='application/vnd.openxmlformats-officedocument.spreadsheetml.sheet')
    response['Content-Disposition'] = 'attachment; filename="Reporte_Combustible_Aseo_Urbano.xlsx"'
    wb.save(response)
    return response


@admin_required
def exportar_recursos_pdf(request):
    response = HttpResponse(content_type='application/pdf')
    response['Content-Disposition'] = 'attachment; filename="Reporte_Combustible_Aseo_Urbano.pdf"'

    ahora_local = django.utils.timezone.localtime(django.utils.timezone.now())
    operador = request.user.get_full_name() or request.user.username

    doc = SimpleDocTemplate(
        response,
        pagesize=letter,
        rightMargin=40,
        leftMargin=40,
        topMargin=36,
        bottomMargin=36
    )
    story = []
    styles = getSampleStyleSheet()

    membrete_style = ParagraphStyle(
        'Membrete',
        parent=styles['Normal'],
        fontSize=9.5,
        textColor=colors.black,
        fontName='Helvetica-Bold',
        alignment=1,  # Centrado
        leading=13
    )
    title_style = ParagraphStyle(
        'DocTitle',
        parent=styles['Normal'],
        fontSize=12,
        textColor=colors.black,
        fontName='Helvetica-Bold',
        alignment=1,
        spaceBefore=10,
        spaceAfter=12
    )
    section_style = ParagraphStyle(
        'SectionHeading',
        parent=styles['Normal'],
        fontSize=10,
        textColor=colors.black,
        fontName='Helvetica-Bold',
        spaceBefore=14,
        spaceAfter=6
    )
    normal_small = ParagraphStyle(
        'NormalSmall',
        parent=styles['Normal'],
        fontSize=9,
        textColor=colors.black,
        leading=12
    )

    # Membrete clásico institucional centrado
    story.append(Paragraph(
        "REPÚBLICA BOLIVARIANA DE VENEZUELA<br/>"
        "ESTADO ANZOÁTEGUI - ALCALDÍA DEL MUNICIPIO ANACO<br/>"
        "DIRECCIÓN DE ASEO URBANO",
        membrete_style
    ))
    story.append(Spacer(1, 6))
    story.append(HRFlowable(width="100%", thickness=0.8, color=colors.black, spaceAfter=6))
    story.append(Paragraph("REPORTE DE FLOTA Y REGISTRO DE COMBUSTIBLE", title_style))

    # Consultas de datos
    vehiculos = Vehiculo.objects.all().order_by('placa')
    registros = RegistroCombustible.objects.select_related('vehiculo').all().order_by('-fecha')
    jornadas = (
        Jornada.objects.select_related('vehiculo', 'ruta', 'chofer', 'chofer__usuario')
        .prefetch_related(_prefetch_puntos())
        .all()
        .order_by('-fecha', '-id')[:10]
    )

    total_vehiculos = vehiculos.count()
    vehiculos_activos = vehiculos.filter(estado='activo').count()
    totales = registros.aggregate(litros=Sum('litros'), costo=Sum('costo_total'))
    total_litros = float(totales['litros'] or 0)
    costo_total = float(totales['costo'] or 0)

    # Ficha de datos generales (estilo planilla administrativa)
    info_data = [
        ["Fecha de emisión:", ahora_local.strftime('%d/%m/%Y %H:%M'), "Unidades registradas:", f"{total_vehiculos} ({vehiculos_activos} operativas)"],
        ["Generado por:", operador, "Total combustible:", f"{round(total_litros, 2)} Litros ($ {round(costo_total, 2)})"]
    ]
    info_table = Table(info_data, colWidths=[95, 165, 115, 155])
    info_table.setStyle(TableStyle([
        ('FONTNAME', (0, 0), (0, -1), 'Helvetica-Bold'),
        ('FONTNAME', (2, 0), (2, -1), 'Helvetica-Bold'),
        ('FONTSIZE', (0, 0), (-1, -1), 9),
        ('TEXTCOLOR', (0, 0), (-1, -1), colors.black),
        ('BOTTOMPADDING', (0, 0), (-1, -1), 4),
        ('TOPPADDING', (0, 0), (-1, -1), 4),
        ('BOX', (0, 0), (-1, -1), 0.5, colors.black),
        ('INNERGRID', (0, 0), (-1, -1), 0.25, colors.grey),
    ]))
    story.append(info_table)

    # 1. Tabla de Vehículos
    story.append(Paragraph("1. Relación de Unidades", section_style))
    flota_data = [["Placa", "Marca / Modelo", "Capacidad (Ton)", "Rendimiento (Km/L)", "Estado"]]
    for v in vehiculos:
        flota_data.append([
            v.placa,
            f"{v.marca} {v.modelo}",
            f"{v.capacidad_toneladas}",
            f"{v.rendimiento_km_por_litro}",
            v.get_estado_display()
        ])
    if len(flota_data) == 1:
        flota_data.append(["-", "Sin registros", "-", "-", "-"])

    t_flota = Table(flota_data, colWidths=[85, 165, 95, 100, 85])
    t_flota.setStyle(TableStyle([
        ('BACKGROUND', (0, 0), (-1, 0), colors.HexColor('#E5E7EB')),
        ('TEXTCOLOR', (0, 0), (-1, -1), colors.black),
        ('FONTNAME', (0, 0), (-1, 0), 'Helvetica-Bold'),
        ('FONTSIZE', (0, 0), (-1, -1), 8.5),
        ('ALIGN', (0, 0), (-1, -1), 'CENTER'),
        ('ALIGN', (1, 1), (1, -1), 'LEFT'),
        ('GRID', (0, 0), (-1, -1), 0.5, colors.black),
        ('TOPPADDING', (0, 0), (-1, -1), 5),
        ('BOTTOMPADDING', (0, 0), (-1, -1), 5),
    ]))
    story.append(t_flota)

    # 2. Tabla de Cargas de Combustible
    story.append(Paragraph("2. Registro de Abastecimiento de Combustible", section_style))
    comb_data = [["Fecha y Hora", "Placa", "Marca / Modelo", "Litros", "Costo ($)", "Kilometraje"]]
    for r in registros:
        fecha_loc = django.utils.timezone.localtime(r.fecha).strftime("%d/%m/%Y %H:%M")
        comb_data.append([
            fecha_loc,
            r.vehiculo.placa,
            f"{r.vehiculo.marca} {r.vehiculo.modelo}",
            f"{r.litros} L",
            f"$ {r.costo_total}",
            f"{r.kilometraje_actual} km"
        ])

    if len(comb_data) == 1:
        comb_data.append(["-", "-", "Sin registros de combustible", "0 L", "$ 0.00", "-"])
    else:
        comb_data.append([
            "TOTAL",
            "-",
            f"{len(registros)} recargas",
            f"{round(total_litros, 2)} L",
            f"$ {round(costo_total, 2)}",
            "-"
        ])

    t_comb = Table(comb_data, colWidths=[95, 75, 130, 75, 75, 80])
    t_comb.setStyle(TableStyle([
        ('BACKGROUND', (0, 0), (-1, 0), colors.HexColor('#E5E7EB')),
        ('TEXTCOLOR', (0, 0), (-1, -1), colors.black),
        ('FONTNAME', (0, 0), (-1, 0), 'Helvetica-Bold'),
        ('FONTSIZE', (0, 0), (-1, -1), 8.5),
        ('ALIGN', (0, 0), (-1, -1), 'CENTER'),
        ('ALIGN', (2, 1), (2, -2), 'LEFT'),
        ('BACKGROUND', (0, -1), (-1, -1), colors.HexColor('#F3F4F6')),
        ('FONTNAME', (0, -1), (-1, -1), 'Helvetica-Bold'),
        ('GRID', (0, 0), (-1, -1), 0.5, colors.black),
        ('TOPPADDING', (0, 0), (-1, -1), 5),
        ('BOTTOMPADDING', (0, 0), (-1, -1), 5),
    ]))
    story.append(t_comb)

    # 3. Tabla de Recorridos Asignados
    story.append(Paragraph("3. Últimas Jornadas de Recolección", section_style))
    jornadas_data = [["Fecha", "Placa", "Ruta", "Sector", "Chofer", "Estado"]]
    for j in jornadas:
        jornadas_data.append([
            j.fecha.strftime("%d/%m/%Y"),
            j.vehiculo.placa,
            j.ruta.nombre[:25],
            j.ruta.zona[:20] if j.ruta.zona else "-",
            (j.chofer.usuario.get_full_name() or j.chofer.usuario.username)[:20],
            j.get_estado_display()
        ])
    if len(jornadas_data) == 1:
        jornadas_data.append(["-", "-", "Sin jornadas registradas", "-", "-", "-"])

    t_jornadas = Table(jornadas_data, colWidths=[65, 65, 130, 95, 100, 75])
    t_jornadas.setStyle(TableStyle([
        ('BACKGROUND', (0, 0), (-1, 0), colors.HexColor('#E5E7EB')),
        ('TEXTCOLOR', (0, 0), (-1, -1), colors.black),
        ('FONTNAME', (0, 0), (-1, 0), 'Helvetica-Bold'),
        ('FONTSIZE', (0, 0), (-1, -1), 8.5),
        ('ALIGN', (0, 0), (-1, -1), 'CENTER'),
        ('ALIGN', (2, 1), (4, -1), 'LEFT'),
        ('GRID', (0, 0), (-1, -1), 0.5, colors.black),
        ('TOPPADDING', (0, 0), (-1, -1), 5),
        ('BOTTOMPADDING', (0, 0), (-1, -1), 5),
    ]))
    story.append(t_jornadas)

    # Firmas simples al pie
    story.append(Spacer(1, 40))
    firmas_data = [
        ["_______________________________", "_______________________________"],
        ["Elaborado por", "Revisado por Dirección de Aseo Urbano"]
    ]
    t_firmas = Table(firmas_data, colWidths=[265, 265])
    t_firmas.setStyle(TableStyle([
        ('ALIGN', (0, 0), (-1, -1), 'CENTER'),
        ('FONTSIZE', (0, 0), (-1, -1), 9),
        ('TEXTCOLOR', (0, 0), (-1, -1), colors.black),
        ('TOPPADDING', (0, 0), (-1, -1), 3),
        ('BOTTOMPADDING', (0, 0), (-1, -1), 3),
    ]))
    story.append(t_firmas)

    doc.build(story)
    return response


@admin_required
def incidencias_gestion(request):
    incidencias = list(
        Incidencia.objects.select_related(
            'jornada', 'jornada__vehiculo', 'jornada__ruta', 'jornada__chofer', 'jornada__chofer__usuario'
        ).all().order_by('-timestamp')
    )
    jornadas = Jornada.objects.select_related('vehiculo', 'ruta', 'chofer', 'chofer__usuario').order_by('-fecha', '-id')

    context = {
        'incidencias': incidencias,
        'jornadas': jornadas,
        'total_incidencias': len(incidencias),
        'pendientes_count': sum(1 for i in incidencias if i.estado == 'pendiente'),
        'en_atencion_count': sum(1 for i in incidencias if i.estado == 'en_atencion'),
        'resueltas_count': sum(1 for i in incidencias if i.estado == 'resuelta'),
    }
    return render(request, 'dashboard/incidencias.html', context)


@admin_required
def incidencia_crear(request):
    if request.method == 'POST':
        jornada_id = request.POST.get('jornada')
        descripcion = request.POST.get('descripcion', '').strip()
        latitud = _parse_coordenada(request.POST.get('latitud'))
        longitud = _parse_coordenada(request.POST.get('longitud'))
        if latitud is not None and not Decimal('-90') <= latitud <= Decimal('90'):
            latitud = None
        if latitud is None or longitud is None:
            latitud = None
            longitud = None
        foto = request.FILES.get('foto')

        jornada_pk = _parse_entero(jornada_id)
        jornada = Jornada.objects.filter(pk=jornada_pk).first() if jornada_pk else None
        if not jornada:
            messages.error(request, 'Debes seleccionar una jornada válida.')
            return redirect('dashboard_incidencias')

        if descripcion:
            inc = Incidencia.objects.create(
                jornada=jornada,
                descripcion=descripcion,
                latitud=latitud,
                longitud=longitud,
                foto=foto,
                estado='pendiente'
            )
            RegistroAuditoria.objects.create(
                usuario=request.user,
                accion='CREAR',
                tabla_afectada='Incidencia',
                detalles=f"Reporte de incidencia #{inc.id} en unidad {jornada.vehiculo.placa}: {descripcion[:80]}"
            )
            messages.success(request, '¡Incidencia operativa registrada correctamente!')
        else:
            messages.error(request, 'Por favor ingresa la descripción de la incidencia.')

    return redirect('dashboard_incidencias')


@admin_required
def incidencia_actualizar(request, pk):
    incidencia = get_object_or_404(Incidencia, pk=pk)
    if request.method == 'POST':
        nuevo_estado = request.POST.get('estado')
        resolucion_detalles = request.POST.get('resolucion_detalles', '').strip()

        if nuevo_estado in ['pendiente', 'en_atencion', 'resuelta']:
            incidencia.estado = nuevo_estado
            incidencia.resolucion_detalles = resolucion_detalles
            incidencia.resuelta_en = (
                django.utils.timezone.now() if nuevo_estado == 'resuelta' else None
            )
            incidencia.save(update_fields=['estado', 'resolucion_detalles', 'resuelta_en'])

            RegistroAuditoria.objects.create(
                usuario=request.user,
                accion='MODIFICAR',
                tabla_afectada='Incidencia',
                detalles=f"Incidencia #{incidencia.id} actualizada a '{incidencia.get_estado_display()}'. Notas: {resolucion_detalles or 'Sin notas'}"
            )
            messages.success(request, f"Estado de la incidencia actualizado a {incidencia.get_estado_display()}.")
        else:
            messages.error(request, 'Estado seleccionado no válido.')

    return redirect('dashboard_incidencias')


@admin_required
def incidencia_eliminar(request, pk):
    incidencia = get_object_or_404(Incidencia, pk=pk)
    if request.method == 'POST':
        inc_id = incidencia.id
        placa = incidencia.jornada.vehiculo.placa if incidencia.jornada and incidencia.jornada.vehiculo else 'S/V'
        incidencia.delete()
        RegistroAuditoria.objects.create(
            usuario=request.user,
            accion='ELIMINAR',
            tabla_afectada='Incidencia',
            detalles=f"Eliminada incidencia #{inc_id} de la unidad {placa}"
        )
        messages.success(request, 'Registro de incidencia eliminado correctamente.')

    return redirect('dashboard_incidencias')


