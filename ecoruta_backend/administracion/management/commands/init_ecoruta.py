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

        Chofer.objects.get_or_create(
            usuario=admin_user,
            defaults={'licencia': 'LIC-ADMIN-01', 'telefono': ''}
        )

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

        # Rutas de Anaco (solo si no existe el nombre)
        rutas_seed = [
            ('Ruta 01 - Casco Central y Mercado Municipal', 'Casco Central', Decimal('12.50')),
            ('Ruta 02 - Sector Campo Norte y Av. Zulia', 'Campo Norte', Decimal('18.00')),
            ('Ruta 03 - Sector 23 de Enero y Nuevo Anaco', '23 de Enero', Decimal('15.20')),
            ('Ruta 04 - Campo Sur y Av. José Antonio Anzoátegui', 'Campo Sur', Decimal('14.80')),
            ('Ruta 05 - Sector Las Charas y Alí Primera', 'Las Charas', Decimal('21.00')),
        ]
        for nombre, zona, dist in rutas_seed:
            Ruta.objects.get_or_create(
                nombre=nombre,
                defaults={
                    'zona': zona,
                    'distancia_estimada_km': dist,
                }
            )

        self.stdout.write(self.style.SUCCESS("Inicialización base de Aseo Urbano Anaco verificada (sin datos simulados)."))
