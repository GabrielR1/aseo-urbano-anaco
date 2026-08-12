from django.urls import path, include
from rest_framework.routers import DefaultRouter
from .views import (
    JornadaViewSet, PuntoGeolocalizacionViewSet, IncidenciaViewSet,
    sincronizar_puntos_lote, monitoreo_en_vivo, optimizar_ruta_api, notificaciones_chofer
)

router = DefaultRouter()
router.register(r'jornadas', JornadaViewSet)
router.register(r'puntos', PuntoGeolocalizacionViewSet)
router.register(r'incidencias', IncidenciaViewSet)

urlpatterns = [
    path('coordenadas/sincronizar_lote/', sincronizar_puntos_lote, name='sincronizar_puntos_lote'),
    path('monitoreo_en_vivo/', monitoreo_en_vivo, name='monitoreo_en_vivo'),
    path('rutas/<int:pk>/optimizar/', optimizar_ruta_api, name='optimizar_ruta_api'),
    path('notificaciones/', notificaciones_chofer, name='notificaciones_chofer'),
    path('', include(router.urls)),
]