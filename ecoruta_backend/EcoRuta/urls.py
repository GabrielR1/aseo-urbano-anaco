from django.contrib import admin
from django.urls import path, include
from django.conf import settings
from django.conf.urls.static import static
from rest_framework.authtoken.views import obtain_auth_token

admin.site.site_header = "Plataforma EcoRuta"
admin.site.site_title = "Panel de Administración EcoRuta"
admin.site.index_title = "Gestión del Sistema EcoRuta"

urlpatterns = [
    path('admin/', admin.site.urls),
    path('accounts/', include('django.contrib.auth.urls')),
    path('dashboard/', include('dashboard.urls')),
    path('administracion/', include('administracion.urls')),
    path('api/logistica/', include('logistica.urls')),
    path('api/auth/login/', obtain_auth_token, name='api_token_auth'),
]

if settings.DEBUG:
    urlpatterns += static(settings.MEDIA_URL, document_root=settings.MEDIA_ROOT)
