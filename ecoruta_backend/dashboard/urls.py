from django.urls import path
from . import views

urlpatterns = [
    path('', views.dashboard_home, name='dashboard_home'),
    path('rutas/', views.rutas_gestion, name='dashboard_rutas'),
    path('conductores/', views.conductores_gestion, name='dashboard_conductores'),
    path('auditoria/', views.auditoria_listado, name='dashboard_auditoria'),
    path('incentivos/', views.incentivos_listado, name='dashboard_incentivos'),
    path('itinerario/', views.itinerario, name='dashboard_itinerario'),
    path('disponibilidad/', views.disponibilidad_asignacion, name='dashboard_disponibilidad'),
    path('itinerario/crear/', views.jornada_crear, name='jornada_crear'),
    path('itinerario/<int:pk>/reprogramar/', views.jornada_reprogramar, name='jornada_reprogramar'),
    path('itinerario/<int:pk>/eliminar/', views.jornada_eliminar, name='jornada_eliminar'),
    path('mapa/', views.mapa_monitoreo, name='dashboard_mapa'),
    path('chofer/', views.chofer_gps_movil, name='dashboard_chofer_gps'),
    path('incidencias/', views.incidencias_gestion, name='dashboard_incidencias'),
    path('incidencias/crear/', views.incidencia_crear, name='incidencia_crear'),
    path('incidencias/<int:pk>/actualizar/', views.incidencia_actualizar, name='incidencia_actualizar'),
    path('incidencias/<int:pk>/eliminar/', views.incidencia_eliminar, name='incidencia_eliminar'),
    path('recursos/', views.recursos, name='dashboard_recursos'),
    path('recursos/crear/', views.recurso_crear, name='recurso_crear'),
    path('recursos/<int:pk>/eliminar/', views.recurso_eliminar, name='recurso_eliminar'),
    path('recursos/exportar/excel/', views.exportar_recursos_excel, name='exportar_recursos_excel'),
    path('recursos/exportar/pdf/', views.exportar_recursos_pdf, name='exportar_recursos_pdf'),
]
