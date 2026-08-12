from django.test import TestCase
from rest_framework.test import APIClient
from rest_framework import status
from security.models import Usuario
from administracion.models import Ruta, Vehiculo, Chofer
from logistica.models import Jornada, PuntoGeolocalizacion

class LogisticaAPITests(TestCase):
    def setUp(self):
        self.client = APIClient()
        self.user = Usuario.objects.create_user(username='choferapi', password='password123', rol=Usuario.CHOFER)
        self.chofer = Chofer.objects.create(usuario=self.user, licencia="LIC-API-111")
        
        self.ruta = Ruta.objects.create(nombre="Ruta Test API", zona="Norte", distancia_estimada_km=12.0)
        self.vehiculo = Vehiculo.objects.create(placa="API-001", marca="Isuzu", modelo="NPR", capacidad_toneladas=8.0)
        
        self.jornada = Jornada.objects.create(
            vehiculo=self.vehiculo,
            ruta=self.ruta,
            chofer=self.chofer,
            estado='en_curso'
        )

    def test_jwt_auth_obtain_pair(self):
        response = self.client.post('/api/token/', {
            'username': 'choferapi',
            'password': 'password123'
        }, format='json')
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertIn('access', response.data)
        self.assertIn('refresh', response.data)

    def test_sincronizar_puntos_lote(self):
        self.client.force_authenticate(user=self.user)
        lote_puntos = [
            {'jornada': self.jornada.id, 'latitud': 10.4806, 'longitud': -66.9036, 'velocidad_kmh': 40.0, 'precision_metros': 5.0},
            {'jornada': self.jornada.id, 'latitud': 10.4810, 'longitud': -66.9040, 'velocidad_kmh': 42.5, 'precision_metros': 4.2}
        ]
        response = self.client.post('/api/logistica/coordenadas/sincronizar_lote/', lote_puntos, format='json')
        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        self.assertEqual(PuntoGeolocalizacion.objects.count(), 2)

    def test_monitoreo_en_vivo_endpoint(self):
        self.client.force_authenticate(user=self.user)
        PuntoGeolocalizacion.objects.create(jornada=self.jornada, latitud=10.4806, longitud=-66.9036, velocidad_kmh=45.0)
        
        response = self.client.get('/api/logistica/monitoreo_en_vivo/')
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data['total_activos'], 1)
        self.assertEqual(response.data['camiones_activos'][0]['placa'], 'API-001')
