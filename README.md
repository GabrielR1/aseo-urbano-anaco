# 🌿 EcoRuta - Sistema de Gestión y Transporte Ecológico

> **"Limpiando nuestro presente, para disfrutar el futuro."**

EcoRuta es una plataforma integral para la gestión, optimización y seguimiento de rutas ecológicas y recolección de desechos de la Dirección de Aseo Urbano del Municipio Anaco. El sistema consta de un **Backend en Django** (panel web administrativo + API REST) y una **aplicación móvil en Flutter** para choferes y personal de campo.

---

## 🏗️ Arquitectura del Sistema

* **Backend (Django 6.x + DRF):**
  * **Centro de Operaciones y Monitoreo GPS en Vivo**: telemetría en tiempo real, capas multi-estilo (CartoDB, Esri y satelital), polilíneas con traza histórica, panel flotante de flota y simulador de telemetría.
  * **Analítica Ejecutiva & Eco-Calculadora**: dashboard con métricas reales de huella de carbono, consumo de combustible y gráficos Chart.js.
  * **Eco-Optimizador de Rutas**: cálculo de consumo, emisiones y calificación ecológica (A+, A, B).
  * **Gestión de Incidencias**: campana de notificaciones, modal de resolución y bitácora de auditoría.
  * **Exportación Ejecutiva**: informes PDF y Excel con resúmenes operativos.
  * API REST documentada con OpenAPI/Swagger en `/api/docs/`.

* **Frontend Móvil (Flutter 3.x):**
  * Perfil gamificado del chofer con insignias, bonos y niveles de eco-rendimiento.
  * Monitoreo de ruta con velocímetro, precisión satelital, cronómetro y **cola de sincronización offline persistente**.

---

## 👥 Roles y permisos

| Rol | Acceso |
|---|---|
| **Administrador** (`rol=admin`, `is_staff=True`) | Panel web completo, CRUD de flota/rutas/choferes, reportes, monitoreo y API administrativa. |
| **Chofer** (`rol=chofer`) | Panel móvil `/chofer/`, API de sus propias jornadas, telemetría GPS, incidencias y gamificación. |

Reglas implementadas:

* Las vistas del panel (`/dashboard/...`) exigen rol administrativo; un chofer recibe **403** con acceso directo a su panel.
* La API filtra las jornadas, puntos GPS e incidencias por conductor. Un chofer no puede leer ni escribir datos de otro.
* Las operaciones de escritura sobre flota, rutas, choferes y jornadas están reservadas al personal administrativo.
* El panel muestra páginas de error 403/404/500 con la identidad institucional.

---

## 🚀 Instalación y Configuración Local

### 1. Requisitos previos

* Python **3.12 o superior** (el proyecto usa Django 6.x).
* Flutter SDK 3.x (opcional, para el módulo móvil).

### 2. Backend (Django)

```bash
# 1. Crear entorno virtual
python -m venv venv

# 2. Activar entorno virtual
# En Windows:
venv\Scripts\activate
# En Linux/macOS:
source venv/bin/activate

# 3. Instalar dependencias
pip install -r ecoruta_backend/requirements.txt

# 4. Configurar variables de entorno (opcional en desarrollo)
copy ecoruta_backend\.env.example ecoruta_backend\.env   # Windows
# cp ecoruta_backend/.env.example ecoruta_backend/.env    # Linux/macOS

# 5. Migrar, inicializar catálogo y arrancar
cd ecoruta_backend
python manage.py migrate
python manage.py init_ecoruta
python manage.py runserver 0.0.0.0:8000
```

### 3. Variables de entorno

| Variable | Descripción | Valor por defecto |
|---|---|---|
| `SECRET_KEY` | Clave secreta de Django. **Obligatoria con `DEBUG=False`.** | Clave de desarrollo |
| `DEBUG` | Modo depuración. | `True` |
| `ALLOWED_HOSTS` | Hosts permitidos separados por coma. | `localhost,127.0.0.1` |
| `CSRF_TRUSTED_ORIGINS` | Orígenes adicionales para formularios. | Local + `.onrender.com` |
| `CORS_ALLOWED_ORIGINS` | Orígenes web permitidos en producción. | Vacío |
| `DATABASE_URL` | Cadena de conexión PostgreSQL (Render). | SQLite local |
| `USE_POSTGRES` | Usar PostgreSQL con parámetros `DB_*`. | `False` |
| `ADMIN_INITIAL_PASSWORD` | Clave inicial del usuario `admin`. | `admin123` |
| `CHOFER_INITIAL_PASSWORD` | Clave inicial de los choferes de ejemplo. | `chofer123` |

> En producción (`DEBUG=False`), `SECRET_KEY` es obligatoria y CORS queda cerrado salvo que declares `CORS_ALLOWED_ORIGINS`.

---

## 🔑 Accesos del Sistema

* **Panel Dashboard Web:** [http://127.0.0.1:8000/dashboard/](http://127.0.0.1:8000/dashboard/)
* **Panel de Administración Django:** [http://127.0.0.1:8000/admin/](http://127.0.0.1:8000/admin/)
* **Panel móvil del chofer:** [http://127.0.0.1:8000/chofer/](http://127.0.0.1:8000/chofer/)
* **Usuario administrador:** `admin` / `admin123`
* **Choferes de ejemplo:** `chofer1`, `chofer2`, `chofer3` / `chofer123`

> Los accesos de demostración y el botón de autollenado solo se muestran con `DEBUG=True`. En producción cámbialos con `ADMIN_INITIAL_PASSWORD` y `CHOFER_INITIAL_PASSWORD` antes del primer despliegue.

---

## 🧪 Pruebas y validaciones

```bash
cd ecoruta_backend

# Suite completa (permisos, API, GPS, gamificación y aislamiento por conductor)
python manage.py test

# Verificación de configuración
python manage.py check

# Validar el esquema OpenAPI
python manage.py spectacular --validate --file schema.yaml
```

La suite cubre: autenticación JWT, sincronización masiva, rechazo de coordenadas inválidas, protección de jornadas ajenas, permisos del panel, distancia Haversine y cálculo de puntajes.

---

## 📱 Frontend Flutter

```bash
cd ecoruta_frontend
flutter pub get
flutter run -d chrome      # Web (cámara limitada por el navegador)
flutter run -d windows     # Escritorio
flutter run -d android     # Dispositivo/emulador Android
```

La app incluye:

* Configuración de la URL del servidor desde la pantalla de login (se guarda en el dispositivo).
* Permisos de Android/iOS declarados para internet, ubicación y cámara.
* Cola GPS offline persistida en almacenamiento seguro y reenviada con su marca de tiempo original.
* Manejo de permisos de ubicación denegados o bloqueados, con acceso directo a los ajustes.

> Para desarrollo local en Android, usa `http://IP_DE_TU_PC:8000/api` y verifica que el teléfono esté en la misma red. En producción configura una URL **HTTPS** (por ejemplo, Render).

---

## ☁️ Despliegue en Render

El archivo [`render.yaml`](render.yaml) define el servicio web y la base PostgreSQL. El arranque ejecuta [`build.sh`](ecoruta_backend/build.sh): instala dependencias, ejecuta migraciones, `init_ecoruta` y `collectstatic`.

Variables mínimas en Render:

* `DEBUG=False`
* `SECRET_KEY` (generada por Render)
* `ALLOWED_HOSTS=.onrender.com`
* `DATABASE_URL` (desde la base de datos de Render)

---

## 📄 Documentación adicional

* [`MANUAL_DE_USUARIO.md`](MANUAL_DE_USUARIO.md) — guía funcional paso a paso.
* [`DOCUMENTACION_TECNICA_CODIGO.md`](DOCUMENTACION_TECNICA_CODIGO.md) — arquitectura, modelos y flujo técnico.
