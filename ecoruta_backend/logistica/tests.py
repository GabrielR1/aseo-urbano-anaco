from django.test import TestCase
from rest_framework import status
from rest_framework.test import APIClient

from administracion.models import Chofer, Ruta, Vehiculo
from logistica.models import Incidencia, Jornada, PuntoGeolocalizacion
from security.models import Usuario


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

        # Segundo conductor para probar aislamiento de datos.
        self.otro_user = Usuario.objects.create_user(username='otrochofer', password='password123', rol=Usuario.CHOFER)
        self.otro_chofer = Chofer.objects.create(usuario=self.otro_user, licencia="LIC-API-222")
        self.otra_jornada = Jornada.objects.create(
            vehiculo=self.vehiculo,
            ruta=self.ruta,
            chofer=self.otro_chofer,
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

    def test_sincronizar_lote_ignora_jornadas_ajenas(self):
        self.client.force_authenticate(user=self.user)
        response = self.client.post(
            '/api/logistica/coordenadas/sincronizar_lote/',
            [{'jornada': self.otra_jornada.id, 'latitud': 10.48, 'longitud': -66.90}],
            format='json',
        )
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(PuntoGeolocalizacion.objects.count(), 0)

    def test_sincronizar_lote_descarta_coordenadas_invalidas(self):
        self.client.force_authenticate(user=self.user)
        response = self.client.post(
            '/api/logistica/coordenadas/sincronizar_lote/',
            [
                {'jornada': self.jornada.id, 'latitud': 120, 'longitud': -66.90},
                {'jornada': self.jornada.id, 'latitud': 10.48, 'longitud': -66.90},
            ],
            format='json',
        )
        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        self.assertEqual(response.data['procesados'], 1)
        self.assertEqual(response.data['descartados'], 1)

    def test_sincronizar_lote_conserva_timestamp_offline(self):
        self.client.force_authenticate(user=self.user)
        response = self.client.post(
            '/api/logistica/coordenadas/sincronizar_lote/',
            [{
                'jornada': self.jornada.id,
                'latitud': 10.48,
                'longitud': -66.90,
                'timestamp': '2026-01-15T08:30:00Z',
            }],
            format='json',
        )
        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        punto = PuntoGeolocalizacion.objects.get()
        self.assertEqual(punto.timestamp.year, 2026)
        self.assertEqual(punto.timestamp.month, 1)

    def test_monitoreo_en_vivo_endpoint(self):
        self.client.force_authenticate(user=self.user)
        PuntoGeolocalizacion.objects.create(jornada=self.jornada, latitud=10.4806, longitud=-66.9036, velocidad_kmh=45.0)

        response = self.client.get('/api/logistica/monitoreo_en_vivo/')
        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)

    def test_monitoreo_en_vivo_administrador(self):
        admin = Usuario.objects.create_user(username='adminapi', password='password123', rol=Usuario.ADMIN)
        self.client.force_authenticate(user=admin)
        PuntoGeolocalizacion.objects.create(jornada=self.jornada, latitud=10.4806, longitud=-66.9036, velocidad_kmh=45.0)

        response = self.client.get('/api/logistica/monitoreo_en_vivo/')
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data['total_activos'], 2)
        placas = {c['placa'] for c in response.data['camiones_activos']}
        self.assertEqual(placas, {'API-001'})

    def test_optimizar_ruta_api(self):
        self.client.force_authenticate(user=self.user)
        response = self.client.get(f'/api/logistica/rutas/{self.ruta.id}/optimizar/')
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertIn('emision_co2_kg', response.data)
        self.assertIn('litros_estimados', response.data)

    def test_notificaciones_chofer(self):
        self.client.force_authenticate(user=self.user)
        Jornada.objects.create(vehiculo=self.vehiculo, ruta=self.ruta, chofer=self.chofer, estado='pendiente')
        response = self.client.get('/api/logistica/notificaciones/')
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        # La jornada en curso del setUp + la pendiente recién creada.
        self.assertEqual(response.data['total'], 2)
        self.assertTrue(all(n['id'] for n in response.data['notificaciones']))

    def test_chofer_gamificacion_api(self):
        self.client.force_authenticate(user=self.user)
        Jornada.objects.create(vehiculo=self.vehiculo, ruta=self.ruta, chofer=self.chofer, estado='finalizada')
        response = self.client.get('/api/logistica/chofer/gamificacion/')
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertIn('puntos_totales', response.data)
        self.assertIn('insignias', response.data)

    def test_chofer_no_ve_jornadas_de_otro_conductor(self):
        self.client.force_authenticate(user=self.user)
        response = self.client.get('/api/logistica/jornadas/')
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        ids = {item['id'] for item in response.data['results']} if 'results' in response.data else {item['id'] for item in response.data}
        self.assertEqual(ids, {self.jornada.id})

    def test_chofer_no_puede_enviar_gps_a_jornada_ajena(self):
        self.client.force_authenticate(user=self.user)
        response = self.client.post(
            '/api/logistica/puntos/',
            {'jornada': self.otra_jornada.id, 'latitud': '10.480600', 'longitud': '-66.903600'},
            format='json',
        )
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(PuntoGeolocalizacion.objects.count(), 0)

    def test_chofer_no_puede_iniciar_jornada_ajena(self):
        self.client.force_authenticate(user=self.user)
        response = self.client.post(f'/api/logistica/jornadas/{self.otra_jornada.id}/iniciar/')
        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)

    def test_chofer_no_puede_gestionar_incidencia_ajena(self):
        incidencia = Incidencia.objects.create(jornada=self.otra_jornada, descripcion=' contenedor bloqueado ')
        self.client.force_authenticate(user=self.user)
        response = self.client.post(
            f'/api/logistica/incidencias/{incidencia.id}/gestionar/',
            {'estado': 'resuelta'},
            format='json',
        )
        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)

    def test_distancia_real_haversine(self):
        from datetime import timedelta

        from django.utils import timezone

        base = timezone.now()
        PuntoGeolocalizacion.objects.create(jornada=self.jornada, latitud=10.480600, longitud=-66.903600, timestamp=base)
        PuntoGeolocalizacion.objects.create(jornada=self.jornada, latitud=10.489600, longitud=-66.903600, timestamp=base + timedelta(minutes=2))

        distancia = self.jornada.calcular_distancia_real_km()
        # ~1 km por cada 0.009 grados de latitud.
        self.assertAlmostEqual(distancia, 1.0, delta=0.1)
