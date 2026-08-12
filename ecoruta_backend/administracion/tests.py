from django.test import TestCase
from security.models import Usuario
from administracion.models import Ruta, Vehiculo, Chofer, RegistroCombustible

class AdministracionModelTests(TestCase):
    def setUp(self):
        self.user = Usuario.objects.create_user(username='testadmin', password='password123', rol=Usuario.ADMIN)
        self.chofer_user = Usuario.objects.create_user(username='testchofer', password='password123', rol=Usuario.CHOFER)

    def test_crear_ruta(self):
        ruta = Ruta.objects.create(
            nombre="Ruta Test San Bernardino",
            zona="Sector San Bernardino",
            distancia_estimada_km=10.5,
            descripcion="Ruta de prueba unitaria"
        )
        self.assertEqual(Ruta.objects.count(), 1)
        self.assertEqual(ruta.nombre, "Ruta Test San Bernardino")
        self.assertIsNotNone(ruta.creado_en)

    def test_crear_vehiculo(self):
        vehiculo = Vehiculo.objects.create(
            placa="TST-999",
            marca="Mack",
            modelo="Granite",
            capacidad_toneladas=15.0,
            estado="activo",
            rendimiento_km_por_litro=4.0
        )
        self.assertEqual(Vehiculo.objects.count(), 1)
        self.assertEqual(vehiculo.placa, "TST-999")
        self.assertEqual(vehiculo.estado, "activo")

    def test_crear_chofer(self):
        chofer = Chofer.objects.create(
            usuario=self.chofer_user,
            licencia="LIC-TEST-001",
            telefono="+58 414-0000000"
        )
        self.assertEqual(Chofer.objects.count(), 1)
        self.assertEqual(chofer.licencia, "LIC-TEST-001")
