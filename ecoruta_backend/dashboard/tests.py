from django.test import TestCase
from django.urls import reverse

from administracion.models import Chofer, Ruta, Vehiculo
from logistica.models import Jornada
from security.models import Usuario

PAGINAS_ADMIN = [
    'dashboard_home',
    'dashboard_rutas',
    'dashboard_conductores',
    'dashboard_auditoria',
    'dashboard_incentivos',
    'dashboard_itinerario',
    'dashboard_mapa',
    'dashboard_incidencias',
    'dashboard_recursos',
]


class PanelPermisosTests(TestCase):
    def setUp(self):
        self.admin = Usuario.objects.create_user(
            username='adminpanel', password='password123', rol=Usuario.ADMIN
        )
        self.chofer_user = Usuario.objects.create_user(
            username='choferpanel', password='password123', rol=Usuario.CHOFER
        )
        self.chofer = Chofer.objects.create(usuario=self.chofer_user, licencia='LIC-PANEL-1')
        self.ruta = Ruta.objects.create(nombre='Ruta Panel', zona='Centro', distancia_estimada_km=10)
        self.vehiculo = Vehiculo.objects.create(
            placa='PAN-001', marca='Isuzu', modelo='NPR', capacidad_toneladas=8
        )
        self.jornada = Jornada.objects.create(
            vehiculo=self.vehiculo, ruta=self.ruta, chofer=self.chofer, estado='pendiente'
        )

    def test_anonimo_es_redirigido_al_login(self):
        response = self.client.get(reverse('dashboard_home'))
        self.assertEqual(response.status_code, 302)
        self.assertIn('/accounts/login/', response['Location'])

    def test_administrador_accede_a_todas_las_secciones(self):
        self.client.force_login(self.admin)
        for nombre in PAGINAS_ADMIN:
            with self.subTest(pagina=nombre):
                response = self.client.get(reverse(nombre))
                self.assertEqual(response.status_code, 200)

    def test_chofer_es_redirigido_a_su_panel(self):
        self.client.force_login(self.chofer_user)
        response = self.client.get(reverse('dashboard_home'))
        self.assertRedirects(response, reverse('dashboard_chofer_gps'))

    def test_chofer_no_accede_a_secciones_administrativas(self):
        self.client.force_login(self.chofer_user)
        for nombre in PAGINAS_ADMIN[1:]:
            with self.subTest(pagina=nombre):
                response = self.client.get(reverse(nombre))
                self.assertEqual(response.status_code, 403)

    def test_chofer_puede_usar_su_panel_gps(self):
        self.client.force_login(self.chofer_user)
        response = self.client.get(reverse('dashboard_chofer_gps'))
        self.assertEqual(response.status_code, 200)
        self.assertContains(response, 'Ruta Panel')

    def test_chofer_no_puede_eliminar_vehiculos(self):
        self.client.force_login(self.chofer_user)
        response = self.client.post(reverse('vehiculo_eliminar', args=[self.vehiculo.pk]))
        self.assertEqual(response.status_code, 403)
        self.assertTrue(Vehiculo.objects.filter(pk=self.vehiculo.pk).exists())

    def test_chofer_no_puede_crear_jornadas(self):
        self.client.force_login(self.chofer_user)
        response = self.client.post(
            reverse('jornada_crear'),
            {'vehiculo': self.vehiculo.pk, 'ruta': self.ruta.pk, 'chofer': self.chofer.pk},
        )
        self.assertEqual(response.status_code, 403)
        self.assertEqual(Jornada.objects.count(), 1)

    def test_no_se_puede_eliminar_unidad_con_jornadas(self):
        self.client.force_login(self.admin)
        response = self.client.post(reverse('vehiculo_eliminar', args=[self.vehiculo.pk]))
        self.assertRedirects(response, reverse('dashboard_recursos'))
        self.assertTrue(Vehiculo.objects.filter(pk=self.vehiculo.pk).exists())

    def test_crear_jornada_con_fecha_invalida_no_rompe(self):
        self.client.force_login(self.admin)
        response = self.client.post(
            reverse('jornada_crear'),
            {
                'vehiculo': self.vehiculo.pk,
                'ruta': self.ruta.pk,
                'chofer': self.chofer.pk,
                'fecha': 'fecha-invalida',
            },
        )
        self.assertRedirects(response, reverse('dashboard_itinerario'))
        self.assertEqual(Jornada.objects.count(), 1)

    def test_administrador_crea_ruta_y_queda_auditada(self):
        from administracion.models import RegistroAuditoria

        self.client.force_login(self.admin)
        response = self.client.post(
            reverse('ruta_crear'),
            {
                'nombre': 'Ruta Nueva',
                'zona': 'Sector Nuevo',
                'distancia_estimada_km': '18.40',
                'descripcion': 'Ruta creada desde la prueba',
            },
        )
        self.assertRedirects(response, reverse('dashboard_rutas'))
        self.assertTrue(Ruta.objects.filter(nombre='Ruta Nueva').exists())
        self.assertTrue(
            RegistroAuditoria.objects.filter(
                accion='CREAR', tabla_afectada='Ruta Ecológica'
            ).exists()
        )

    def test_registro_combustible_invalido_es_rechazado(self):
        from administracion.models import RegistroCombustible

        self.client.force_login(self.admin)
        response = self.client.post(
            reverse('recurso_crear'),
            {'vehiculo': self.vehiculo.pk, 'litros': '-5', 'costo_total': '10'},
        )
        self.assertRedirects(response, reverse('dashboard_recursos'))
        self.assertFalse(RegistroCombustible.objects.exists())

    def test_chofer_no_puede_registrar_combustible(self):
        self.client.force_login(self.chofer_user)
        response = self.client.post(
            reverse('recurso_crear'),
            {'vehiculo': self.vehiculo.pk, 'litros': '10', 'costo_total': '20'},
        )
        self.assertEqual(response.status_code, 403)

    def test_no_se_puede_eliminar_jornada_en_curso(self):
        self.jornada.estado = 'en_curso'
        self.jornada.save(update_fields=['estado'])
        self.client.force_login(self.admin)
        response = self.client.post(reverse('jornada_eliminar', args=[self.jornada.pk]))
        self.assertRedirects(response, reverse('dashboard_itinerario'))
        self.assertTrue(Jornada.objects.filter(pk=self.jornada.pk).exists())

    def test_incidencia_con_coordenadas_invalidas_guarda_sin_gps(self):
        from logistica.models import Incidencia

        self.client.force_login(self.admin)
        response = self.client.post(
            reverse('incidencia_crear'),
            {
                'jornada': self.jornada.pk,
                'descripcion': 'Contenedor obstruido en la vía',
                'latitud': '999',
                'longitud': '-64.45',
            },
        )
        self.assertRedirects(response, reverse('dashboard_incidencias'))
        incidencia = Incidencia.objects.get()
        self.assertIsNone(incidencia.latitud)
        self.assertIsNone(incidencia.longitud)

    def test_login_de_chofer_lo_envia_a_su_panel(self):
        response = self.client.post(
            reverse('login'),
            {
                'username': self.chofer_user.username,
                'password': 'password123',
                'next': '/dashboard/',
            },
        )
        self.assertRedirects(response, reverse('dashboard_chofer_gps'))

    def test_login_de_administrador_va_al_dashboard(self):
        response = self.client.post(
            reverse('login'),
            {
                'username': self.admin.username,
                'password': 'password123',
                'next': '/dashboard/',
            },
        )
        self.assertRedirects(response, reverse('dashboard_home'))

    def test_credenciales_demo_ocultas_sin_debug(self):
        from django.test import override_settings

        with override_settings(DEBUG=False):
            response = self.client.get(reverse('login'))
        self.assertEqual(response.status_code, 200)
        self.assertNotContains(response, 'Acceso de Demostración')

    def test_programacion_multiple_dias_y_evita_duplicados(self):
        self.client.force_login(self.admin)
        response = self.client.post(
            reverse('jornada_crear'),
            {
                'vehiculo': self.vehiculo.pk,
                'ruta': self.ruta.pk,
                'chofer': self.chofer.pk,
                'fechas_multiples': '2026-12-01,2026-12-03,2026-12-05',
            },
        )
        self.assertRedirects(response, reverse('dashboard_itinerario'))
        self.assertEqual(Jornada.objects.filter(fecha__year=2026, fecha__month=12).count(), 3)

        # Reenviar las mismas fechas no debe duplicar jornadas pendientes
        self.client.post(
            reverse('jornada_crear'),
            {
                'vehiculo': self.vehiculo.pk,
                'ruta': self.ruta.pk,
                'chofer': self.chofer.pk,
                'fechas_multiples': '2026-12-01,2026-12-03,2026-12-05',
            },
        )
        self.assertEqual(Jornada.objects.filter(fecha__year=2026, fecha__month=12).count(), 3)

    def test_reprogramar_jornada_pendiente_por_ajax(self):
        self.client.force_login(self.admin)
        response = self.client.post(
            reverse('jornada_reprogramar', args=[self.jornada.pk]),
            data='{"fecha": "2026-12-10"}',
            content_type='application/json',
        )
        self.assertEqual(response.status_code, 200)
        self.jornada.refresh_from_db()
        self.assertEqual(self.jornada.fecha.isoformat(), '2026-12-10')

    def test_no_se_puede_reprogramar_jornada_en_curso(self):
        self.jornada.estado = 'en_curso'
        self.jornada.save(update_fields=['estado'])
        self.jornada.refresh_from_db()
        fecha_orig = self.jornada.fecha
        self.client.force_login(self.admin)
        response = self.client.post(
            reverse('jornada_reprogramar', args=[self.jornada.pk]),
            data='{"fecha": "2026-12-15"}',
            content_type='application/json',
        )
        self.assertEqual(response.status_code, 400)
        self.jornada.refresh_from_db()
        self.assertEqual(self.jornada.fecha, fecha_orig)
