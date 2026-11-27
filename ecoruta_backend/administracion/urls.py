from django.urls import path
from . import views

urlpatterns = [
    path('rutas/crear/', views.ruta_crear, name='ruta_crear'),
    path('rutas/<int:pk>/editar/', views.ruta_editar, name='ruta_editar'),
    path('rutas/<int:pk>/eliminar/', views.ruta_eliminar, name='ruta_eliminar'),
    path('vehiculos/crear/', views.vehiculo_crear, name='vehiculo_crear'),
    path('vehiculos/<int:pk>/editar/', views.vehiculo_editar, name='vehiculo_editar'),
    path('vehiculos/<int:pk>/eliminar/', views.vehiculo_eliminar, name='vehiculo_eliminar'),
    path('choferes/crear/', views.chofer_crear, name='chofer_crear'),
    path('choferes/<int:pk>/editar/', views.chofer_editar, name='chofer_editar'),
    path('choferes/<int:pk>/reenviar-verificacion/', views.chofer_reenviar_verificacion, name='chofer_reenviar_verificacion'),
    path('choferes/<int:pk>/eliminar/', views.chofer_eliminar, name='chofer_eliminar'),
]