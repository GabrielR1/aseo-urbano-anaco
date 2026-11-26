import json
import os
from decimal import Decimal
from django.core.management.base import BaseCommand
from security.models import Usuario, Rol
from administracion.models import Vehiculo, Ruta, Chofer


class Command(BaseCommand):
    help = "Inicializa catálogo base (roles, usuarios, flota y rutas de Anaco) sin crear métricas ni GPS simulados."

    def handle(self, *args, **options):
        rol_admin, _ = Rol.objects.get_or_create(
            nombre='Administrador',
            defaults={'descripcion': 'Gestión operativa completa del sistema Aseo Urbano Anaco'}
        )
        rol_chofer, _ = Rol.objects.get_or_create(
            nombre='Chofer',
            defaults={'descripcion': 'Operador de unidad recolectora con transmisión GPS móvil'}
        )

        # Superusuario administrador (solo crea si no existe)
        admin_pass = os.getenv('ADMIN_INITIAL_PASSWORD', 'admin123')
        admin_user, created = Usuario.objects.get_or_create(
            username='admin',
            defaults={
                'first_name': 'Administrador',
                'last_name': 'Anaco',
                'email': 'admin@aseourbanoanaco.gob.ve',
                'rol': Usuario.ADMIN,
                'rol_ref': rol_admin,
                'is_staff': True,
                'is_superuser': True,
            }
        )
        if created:
            admin_user.set_password(admin_pass)
            admin_user.save()
            self.stdout.write(self.style.SUCCESS("Usuario 'admin' creado."))

        # El administrador es personal de oficina; limpiar perfil de chofer previo si no tiene jornadas
        Chofer.objects.filter(usuario=admin_user, jornada__isnull=True).delete()

        # Choferes base
        chofer_pass = os.getenv('CHOFER_INITIAL_PASSWORD', 'chofer123')
        choferes_seed = [
            ('chofer1', 'Carlos', 'Mendoza', 'V-18452104-5TA', '0414-8001101'),
            ('chofer2', 'José', 'Rodríguez', 'V-20194852-5TA', '0414-8001102'),
            ('chofer3', 'Luis', 'Martínez', 'V-16782341-4TA', '0412-8001103'),
        ]
        for username, fname, lname, licencia, tel in choferes_seed:
            user, u_created = Usuario.objects.get_or_create(
                username=username,
                defaults={
                    'first_name': fname,
                    'last_name': lname,
                    'email': f'{username}@aseourbanoanaco.gob.ve',
                    'rol': Usuario.CHOFER,
                    'rol_ref': rol_chofer,
                    'is_staff': False,
                    'is_superuser': False,
                }
            )
            if u_created:
                user.set_password(chofer_pass)
                user.save()
                self.stdout.write(self.style.SUCCESS(f"Usuario chofer '{username}' creado."))

            Chofer.objects.get_or_create(
                usuario=user,
                defaults={'licencia': licencia, 'telefono': tel}
            )

        # Flota de Anaco (solo si no existe cada placa)
        vehiculos_seed = [
            ('ANA-01', 'Iveco', 'Eurocargo (Compactador)', Decimal('10.00'), 'activo', Decimal('4.80')),
            ('ANA-02', 'International', 'DuraStar (Compactador)', Decimal('12.00'), 'activo', Decimal('4.50')),
            ('ANA-03', 'Isuzu', 'NPR 75 (Recolector)', Decimal('8.50'), 'activo', Decimal('5.20')),
            ('ANA-04', 'Ford', 'Cargo 1721 (En Taller)', Decimal('11.00'), 'mantenimiento', Decimal('4.60')),
            ('ANA-TM1', 'Haojin', 'Trimoto de Carga 250cc (Azul)', Decimal('1.20'), 'activo', Decimal('14.00')),
            ('ANA-TM2', 'Bera', 'Trimoto de Carga 200cc (Azul)', Decimal('1.00'), 'activo', Decimal('16.00')),
        ]
        for placa, marca, modelo, cap, estado, rend in vehiculos_seed:
            Vehiculo.objects.get_or_create(
                placa=placa,
                defaults={
                    'marca': marca,
                    'modelo': modelo,
                    'capacidad_toneladas': cap,
                    'estado': estado,
                    'rendimiento_km_por_litro': rend,
                }
            )

        # Rutas de Anaco con trazado base (solo rellena waypoints si están vacíos)
        rutas_seed = [
            (
                'Ruta 01 - Casco Central y Mercado Municipal',
                'Casco Central',
                Decimal('12.50'),
                'Av. Mérida, Calle Sucre, Mercado Municipal, Av. Miranda y Plaza Bolívar.',
                [
                    [9.4368, -64.4678],
                    [9.4392, -64.4642],
                    [9.4418, -64.4605],
                    [9.4440, -64.4575],
                    [9.4412, -64.4552],
                    [9.4380, -64.4596],
                ],
            ),
            (
                'Ruta 02 - Sector Campo Norte y Av. Zulia',
                'Campo Norte',
                Decimal('18.00'),
                'Av. Zulia, Campo Norte, Urbanización Los Jardines y Av. Portuguesa.',
                [
                    [9.4435, -64.4635],
                    [9.4472, -64.4618],
                    [9.4510, -64.4586],
                    [9.4534, -64.4535],
                    [9.4490, -64.4510],
                ],
            ),
            (
                'Ruta 03 - Sector 23 de Enero y Nuevo Anaco',
                '23 de Enero',
                Decimal('15.20'),
                'Sector 23 de Enero, Av. Los Pilones, Nuevo Anaco y Calle Principal.',
                [
                    [9.4355, -64.4565],
                    [9.4322, -64.4525],
                    [9.4295, -64.4488],
                    [9.4335, -64.4455],
                    [9.4382, -64.4482],
                ],
            ),
            (
                'Ruta 04 - Campo Sur y Av. José Antonio Anzoátegui',
                'Campo Sur',
                Decimal('14.80'),
                'Av. José Antonio Anzoátegui, Campo Sur, Sector San Joaquín y redoma sur.',
                [
                    [9.4350, -64.4660],
                    [9.4310, -64.4675],
                    [9.4268, -64.4652],
                    [9.4252, -64.4602],
                    [9.4298, -64.4580],
                ],
            ),
            (
                'Ruta 05 - Sector Las Charas y Alí Primera',
                'Las Charas',
                Decimal('21.00'),
                'Las Charas, Sector Alí Primera, Carretera Nacional y retorno por Av. Miranda.',
                [
                    [9.4455, -64.4695],
                    [9.4495, -64.4728],
                    [9.4540, -64.4702],
                    [9.4558, -64.4648],
                    [9.4508, -64.4630],
                ],
            ),
        ]
        for nombre, zona, dist, desc, waypoints in rutas_seed:
            ruta_obj, created = Ruta.objects.get_or_create(
                nombre=nombre,
                defaults={
                    'zona': zona,
                    'distancia_estimada_km': dist,
                    'descripcion': desc,
                    'coordenadas_waypoints': json.dumps(waypoints),
                }
            )
            updated_fields = []
            try:
                existing_wps = json.loads(ruta_obj.coordenadas_waypoints or '[]')
            except (ValueError, TypeError):
                existing_wps = []
            if not isinstance(existing_wps, list) or len(existing_wps) < 2:
                ruta_obj.coordenadas_waypoints = json.dumps(waypoints)
                updated_fields.append('coordenadas_waypoints')
            if not (ruta_obj.descripcion or '').strip():
                ruta_obj.descripcion = desc
                updated_fields.append('descripcion')
            if updated_fields:
                ruta_obj.save(update_fields=updated_fields)

        self.stdout.write(self.style.SUCCESS("Inicialización base de Aseo Urbano Anaco verificada (sin datos simulados)."))
