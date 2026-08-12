from django.contrib import admin
from django.urls import path, include
from django.conf import settings
from django.conf.urls.static import static
from rest_framework.authtoken.views import obtain_auth_token
from rest_framework_simplejwt.views import TokenObtainPairView, TokenRefreshView
from drf_spectacular.views import SpectacularAPIView, SpectacularSwaggerView, SpectacularRedocView

admin.site.site_header = "Plataforma EcoRuta"
admin.site.site_title = "Panel de Administración EcoRuta"
admin.site.index_title = "Gestión del Sistema EcoRuta"

urlpatterns = [
    path('admin/', admin.site.urls),
    path('accounts/', include('django.contrib.auth.urls')),
    path('dashboard/', include('dashboard.urls')),
    path('administracion/', include('administracion.urls')),
    path('api/logistica/', include('logistica.urls')),
    
    # Auth Endpoints (Token y JWT)
    path('api/auth/login/', obtain_auth_token, name='api_token_auth'),
    path('api/token/', TokenObtainPairView.as_view(), name='token_obtain_pair'),
    path('api/token/refresh/', TokenRefreshView.as_view(), name='token_refresh'),
    
    # Documentación Interactiva OpenAPI / Swagger
    path('api/schema/', SpectacularAPIView.as_view(), name='schema'),
    path('api/docs/', SpectacularSwaggerView.as_view(url_name='schema'), name='swagger-ui'),
    path('api/redoc/', SpectacularRedocView.as_view(url_name='schema'), name='redoc'),
]

if settings.DEBUG:
    urlpatterns += static(settings.MEDIA_URL, document_root=settings.MEDIA_ROOT)
