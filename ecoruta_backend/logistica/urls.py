from django.urls import path, include
from rest_framework.routers import DefaultRouter
from .views import JornadaViewSet, PuntoGeolocalizacionViewSet, IncidenciaViewSet, sincronizar_puntos_lote

router = DefaultRouter()
router.register(r'jornadas', JornadaViewSet)
router.register(r'puntos', PuntoGeolocalizacionViewSet)
router.register(r'incidencias', IncidenciaViewSet)

urlpatterns = [
    path('coordenadas/sincronizar_lote/', sincronizar_puntos_lote, name='sincronizar_puntos_lote'),
    path('', include(router.urls)),
]