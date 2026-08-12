from django.shortcuts import render, redirect, get_object_or_404
from django.contrib.auth.decorators import login_required
from django.contrib import messages
from django.http import HttpResponse
from administracion.models import Vehiculo, Ruta, RegistroCombustible, Chofer
from logistica.models import Jornada, Incidencia
import django.utils.timezone

import openpyxl
from openpyxl.styles import Font, PatternFill, Alignment

from reportlab.lib.pagesizes import letter
from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.lib import colors

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
    jornadas = Jornada.objects.select_related('vehiculo', 'ruta', 'chofer', 'chofer__usuario').all().order_by('-fecha')
    rutas = Ruta.objects.all()
    vehiculos = Vehiculo.objects.all()
    choferes = Chofer.objects.select_related('usuario').all()
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
    registros = RegistroCombustible.objects.select_related('vehiculo').all().order_by('-fecha')
    vehiculos = Vehiculo.objects.all()
    
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

@login_required
def exportar_recursos_excel(request):
    wb = openpyxl.Workbook()
    ws = wb.active
    ws.title = "Consumo de Combustible"

    ws.append(["ID", "Fecha / Hora", "Placa Vehículo", "Marca / Modelo", "Litros Cargados", "Costo Total ($)", "Kilometraje"])
    header_fill = PatternFill(start_color="10B981", end_color="10B981", fill_type="solid")
    header_font = Font(color="FFFFFF", bold=True)

    for cell in ws[1]:
        cell.fill = header_fill
        cell.font = header_font
        cell.alignment = Alignment(horizontal="center")

    registros = RegistroCombustible.objects.select_related('vehiculo').all().order_by('-fecha')
    for r in registros:
        ws.append([
            r.id,
            r.fecha.strftime("%d/%m/%Y %H:%M"),
            r.vehiculo.placa,
            f"{r.vehiculo.marca} {r.vehiculo.modelo}",
            float(r.litros),
            float(r.costo_total),
            r.kilometraje_actual
        ])

    response = HttpResponse(content_type='application/vnd.openxmlformats-officedocument.spreadsheetml.sheet')
    response['Content-Disposition'] = 'attachment; filename="EcoRuta_Reporte_Combustible.xlsx"'
    wb.save(response)
    return response

@login_required
def exportar_recursos_pdf(request):
    response = HttpResponse(content_type='application/pdf')
    response['Content-Disposition'] = 'attachment; filename="EcoRuta_Reporte_Combustible.pdf"'

    doc = SimpleDocTemplate(response, pagesize=letter, rightMargin=30, leftMargin=30, topMargin=30, bottomMargin=30)
    story = []
    styles = getSampleStyleSheet()

    title_style = ParagraphStyle(
        'DocTitle',
        parent=styles['Heading1'],
        fontSize=18,
        textColor=colors.HexColor('#059669'),
        spaceAfter=12
    )

    story.append(Paragraph("🌿 EcoRuta — Reporte de Recursos y Combustible", title_style))
    story.append(Paragraph(f"Fecha de generación: {django.utils.timezone.now().strftime('%d/%m/%Y %H:%M')}", styles['Normal']))
    story.append(Spacer(1, 16))

    registros = RegistroCombustible.objects.select_related('vehiculo').all().order_by('-fecha')
    data = [["Fecha", "Vehículo", "Litros", "Costo ($)", "Kilometraje"]]
    
    for r in registros:
        data.append([
            r.fecha.strftime("%d/%m/%Y %H:%M"),
            f"{r.vehiculo.placa} ({r.vehiculo.marca})",
            f"{r.litros} L",
            f"${r.costo_total}",
            f"{r.kilometraje_actual} km"
        ])

    if len(data) == 1:
        data.append(["-", "Sin registros", "0 L", "$0.00", "0 km"])

    t = Table(data, colWidths=[110, 140, 90, 90, 100])
    t.setStyle(TableStyle([
        ('BACKGROUND', (0,0), (-1,0), colors.HexColor('#10B981')),
        ('TEXTCOLOR', (0,0), (-1,0), colors.whitesmoke),
        ('ALIGN', (0,0), (-1,-1), 'CENTER'),
        ('FONTNAME', (0,0), (-1,0), 'Helvetica-Bold'),
        ('BOTTOMPADDING', (0,0), (-1,0), 8),
        ('BACKGROUND', (0,1), (-1,-1), colors.HexColor('#F3F4F6')),
        ('GRID', (0,0), (-1,-1), 0.5, colors.HexColor('#D1D5DB')),
    ]))

    story.append(t)
    doc.build(story)
    return response
