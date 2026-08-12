from django.urls import path, include
from rest_framework.routers import DefaultRouter
from .views import JornadaViewSet, PuntoGeolocalizacionViewSet, IncidenciaViewSet

router = DefaultRouter()
router.register(r'jornadas', JornadaViewSet)
router.register(r'puntos', PuntoGeolocalizacionViewSet)
router.register(r'incidencias', IncidenciaViewSet)

urlpatterns = [
    path('', include(router.urls)),
]