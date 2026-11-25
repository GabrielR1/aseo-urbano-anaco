from django.urls import path, include
from rest_framework.routers import DefaultRouter
from .views import (
    JornadaViewSet, PuntoGeolocalizacionViewSet, IncidenciaViewSet,
    sincronizar_puntos_lote, monitoreo_en_vivo, optimizar_ruta_api, notificaciones_chofer,
    chofer_gamificacion_api, gestionar_incidencia_api,
    mis_jornadas, iniciar_jornada_api, finalizar_jornada_api
)

router = DefaultRouter()
router.register(r'jornadas', JornadaViewSet)
router.register(r'puntos', PuntoGeolocalizacionViewSet)
router.register(r'incidencias', IncidenciaViewSet)

urlpatterns = [
    path('coordenadas/sincronizar_lote/', sincronizar_puntos_lote, name='sincronizar_puntos_lote'),
    path('monitoreo_en_vivo/', monitoreo_en_vivo, name='monitoreo_en_vivo'),
    path('mis_jornadas/', mis_jornadas, name='mis_jornadas'),
    path('jornadas/<int:pk>/iniciar/', iniciar_jornada_api, name='iniciar_jornada_api'),
    path('jornadas/<int:pk>/finalizar/', finalizar_jornada_api, name='finalizar_jornada_api'),
    path('incidencias/<int:pk>/gestionar/', gestionar_incidencia_api, name='gestionar_incidencia_api'),
    path('rutas/<int:pk>/optimizar/', optimizar_ruta_api, name='optimizar_ruta_api'),
    path('notificaciones/', notificaciones_chofer, name='notificaciones_chofer'),
    path('chofer/gamificacion/', chofer_gamificacion_api, name='chofer_gamificacion_api'),
    path('', include(router.urls)),
]
