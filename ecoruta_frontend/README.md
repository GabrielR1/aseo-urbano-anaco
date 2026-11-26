# 📱 EcoRuta Chofer (Flutter)

Aplicación móvil de EcoRuta para conductores de la Dirección de Aseo Urbano del Municipio Anaco.

## Funcionalidades

- Inicio de sesión por token contra el backend Django.
- Perfil gamificado: puntos, nivel, kilómetros y bonos en USD.
- Inicio y finalización de la jornada asignada.
- Telemetría GPS cada 10 segundos con velocímetro, precisión y cronómetro.
- Cola offline persistente: los puntos se guardan en el dispositivo y se sincronizan al recuperar la conexión, conservando su hora de captura.
- Reporte de incidencias con foto y ubicación.
- Configuración de la URL del servidor desde el login (se recuerda en el dispositivo).

## Requisitos

- Flutter SDK 3.x (Dart 3.11+).
- Backend EcoRuta en ejecución.

## Ejecutar

```bash
flutter pub get
flutter run -d chrome      # Web
flutter run -d windows     # Escritorio
flutter run -d android     # Android
```

En Android, usa la IP de tu equipo en la red local, por ejemplo `http://192.168.1.112:8000/api`, desde el ícono de configuración del login. Para producción, configura una URL HTTPS.

## Permisos

La app declara permisos de internet, ubicación y cámara en `android/app/src/main/AndroidManifest.xml` y en `ios/Runner/Info.plist`. El modo HTTP sin cifrar está habilitado en Android para la demostración en red local; en producción usa HTTPS.

## Estructura

```text
lib/
├── main.dart
├── providers/auth_provider.dart
├── screens/
│   ├── login_screen.dart
│   ├── home_screen.dart
│   ├── route_active_screen.dart
│   └── incident_screen.dart
└── services/api_service.dart
```
