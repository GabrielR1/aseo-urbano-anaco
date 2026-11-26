# 📘 Documentación Técnica: Estructura, Tecnologías e Implementación del Código
**Proyecto:** Sistema de Gestión, Monitoreo GPS y Transporte Ecológico (**EcoRuta / Aseo Urbano Anaco**)

---

## 1. ¿Con qué se hizo el sistema? (Stack Tecnológico)

El sistema está construido bajo una arquitectura **Cliente-Servidor desacoplada**, compuesta por un **Servidor Central Web + API REST (Backend)** y una **Aplicación Móvil Multiplataforma para Conductores (Frontend)**.

### 1.1. Backend y Panel Web Administrativo (`ecoruta_backend/`)
| Componente | Tecnología / Librería | Versión / Detalle | Propósito en el Proyecto |
| :--- | :--- | :--- | :--- |
| **Lenguaje Base** | **Python** | 3.12+ | Lógica de negocio, cálculos ecológicos, vistas web y servicios REST. |
| **Framework Web** | **Django** | 6.1.x | Arquitectura MVT (Modelo-Vista-Template), ORM, seguridad CSRF, sesiones y panel administrativo. |
| **API REST** | **Django REST Framework (DRF)** | 3.x | Creación de ViewSets, Serializadores y endpoints JSON para la aplicación móvil y el mapa en tiempo real. |
| **Autenticación API** | **DRF AuthToken & SimpleJWT** | Token / JWT | Autenticación segura mediante tokens para dispositivos móviles (`/api/auth/login/` y `/api/token/`). |
| **Documentación API** | **drf-spectacular (OpenAPI 3)** | Swagger / Redoc | Generación automática de documentación interactiva en `/api/docs/` y `/api/redoc/`. |
| **Base de Datos** | **SQLite 3 / PostgreSQL** | `db.sqlite3` / `psycopg2-binary` | Persistencia relacional configurable mediante variable `USE_POSTGRES` en `.env`. |
| **Reportes PDF** | **ReportLab** | `reportlab.platypus` | Generación dinámica de reportes institucionales en PDF con membrete oficial, tablas y firmas. |
| **Reportes Excel** | **OpenPyXL** | `openpyxl` | Exportación de libros Excel (`.xlsx`) multi-hoja (*Unidades*, *Combustible*, *Jornadas*). |
| **CORS y Entorno** | **django-cors-headers / python-dotenv** | — | Permisos de conexión cruzada para Flutter Web/Móvil y lectura de variables de entorno (`.env`). |

### 1.2. Interfaz Web del Dashboard (`dashboard/templates/` y `static/`)
* **HTML5 + CSS3 Moderno (Variables CSS Nativas):** Diseño institucional limpio con barra lateral fija, tarjetas de indicadores (KPIs) y modales interactivos sin depender de frameworks pesados.
* **JavaScript (ES6+ / Fetch API):** Consumo asíncrono de endpoints REST para actualizar camiones e incidencias sin recargar la página.
* **Leaflet.js (`dashboard/static/dashboard/vendor/leaflet/`):** Motor de mapas interactivos alojado localmente (con soporte offline/LAN) para renderizar marcadores de camiones, trazas históricas (polilíneas GPS) y alertas georreferenciadas en Anaco.
* **Chart.js:** Gráficos estadísticos dinámicos en el panel principal (`home.html`) para visualizar toneladas recolectadas y estado operativo.
* **FontAwesome 6.5 & Google Fonts (`Plus Jakarta Sans` / `Outfit`):** Iconografía operativa y tipografía.

### 1.3. Aplicación Móvil para Choferes (`ecoruta_frontend/`)
| Componente | Tecnología / Paquete | Versión | Propósito en el Proyecto |
| :--- | :--- | :--- | :--- |
| **Framework & Lenguaje** | **Flutter / Dart** | SDK ^3.11.5 | Aplicación compilable para Android, iOS, Web (Chrome) y Windows. |
| **Gestión de Estado** | **`provider`** | ^6.1.5+1 | Control reactivo del estado de sesión del chofer (`AuthProvider`). |
| **Cliente HTTP** | **`http`** | ^1.6.0 | Peticiones `GET`, `POST` y `MultipartRequest` (subida de fotos) hacia Django. |
| **Rastreo Satelital** | **`geolocator`** | ^14.0.3 | Lectura de coordenadas GPS (`latitud`, `longitud`), velocidad (`m/s` a `km/h`) y precisión en metros. |
| **Cámara / Evidencias** | **`image_picker`** | ^1.2.2 | Captura de fotografías de incidencias en ruta desde la cámara del dispositivo. |
| **Almacenamiento Seguro**| **`flutter_secure_storage`** | ^10.3.1 | Guardado cifrado del token de autenticación (`auth_token`) en el dispositivo. |

---

## 2. Estructura General del Proyecto (Dónde está cada parte)

```text
App Django Gabriel/
│
├── iniciar_servidor.bat               # Script de arranque automático del servidor Django en red local (0.0.0.0:8000)
├── iniciar_app_movil.bat              # Script de lanzamiento de la app móvil Flutter en Chrome
├── README.md                          # Guía rápida de instalación y credenciales por defecto
├── MANUAL_DE_USUARIO.md               # Manual funcional de pantallas para administradores y operadores
├── DOCUMENTACION_TECNICA_CODIGO.md    # (Este documento) Arquitectura, código y ubicación de cada módulo
├── Diagramas_Tesis/                   # Diagramas UML: Base de Datos, Arquitectura, Secuencia GPS, Casos de Uso y Flujo
│
├── ecoruta_backend/                   # 🖥️ BACKEND DJANGO + PANEL WEB + API REST
│   ├── manage.py                      # Utilidad CLI de Django para migraciones, servidor y administración
│   ├── requirements.txt               # Lista de dependencias de Python
│   ├── db.sqlite3                     # Base de datos relacional local
│   ├── .env                           # Variables de entorno (SECRET_KEY, DEBUG, USE_POSTGRES)
│   │
│   ├── EcoRuta/                       # ⚙️ Configuración central del proyecto Django
│   │   ├── settings.py                # Configuración de apps, BD, DRF, JWT, CORS, idioma (es-ve) y zona horaria
│   │   ├── urls.py                    # Enrutador raíz (/dashboard/, /administracion/, /api/logistica/, /api/docs/)
│   │   ├── wsgi.py / asgi.py          # Interfaces de despliegue para servidores web
│   │
│   ├── security/                      # 🔐 Módulo 1: Usuarios, Roles y Autenticación
│   │   ├── models.py                  # Modelo personalizado `Usuario` (AbstractUser) y tabla normalizada `Rol`
│   │   ├── admin.py                   # Configuración del modelo Usuario en Django Admin
│   │   └── views.py / urls.py         # Vistas de soporte de seguridad
│   │
│   ├── administracion/                # 🚛 Módulo 2: Flota, Rutas, Conductores, Combustible, Auditoría y Gamificación (Datos)
│   │   ├── models.py                  # Modelos: Vehiculo, Ruta, Chofer, RegistroCombustible, RegistroAuditoria, PuntajeChofer, IncentivoChofer
│   │   ├── forms.py                   # Formularios validados: RutaForm y VehiculoForm
│   │   ├── views.py                   # Controladores CRUD (crear/editar/eliminar rutas, vehículos y choferes) + Auditoría
│   │   └── urls.py                    # Rutas de procesamiento de formularios administrativos
│   │
│   ├── logistica/                     # 📡 Módulo 3: Operaciones, Telemetría GPS, Incidencias, Algoritmos y API REST
│   │   ├── models.py                  # Modelos operativos: Jornada, PuntoGeolocalizacion, Incidencia
│   │   ├── optimizador.py             # Algoritmo ecológico: cálculo de combustible, costos y emisiones CO2
│   │   ├── gamificacion.py            # Motor de puntos, niveles (Bronce/Plata/Oro) e insignias con bonos en USD
│   │   ├── serializers.py             # Serializadores JSON para Jornada, PuntoGeolocalizacion e Incidencia
│   │   ├── views.py                   # Endpoints de la API REST (monitoreo en vivo, lote GPS offline, simulador, etc.)
│   │   └── urls.py                    # Enrutador REST bajo `/api/logistica/`
│   │
│   └── dashboard/                     # 📊 Módulo 4: Interfaz Web Administrativa y Exportación de Reportes
│       ├── views.py                   # Vistas de las 9 secciones del panel + Exportación PDF (ReportLab) y Excel (OpenPyXL)
│       ├── urls.py                    # Rutas web bajo `/dashboard/`
│       ├── static/dashboard/          # Logos oficiales y librería local Leaflet.js (CSS, JS, marcadores)
│       └── templates/
│           ├── dashboard/             # Plantillas HTML del sistema (base, home, mapa, rutas, itinerario, etc.)
│           └── registration/          # Plantillas de Login y recuperación de contraseña
│
└── ecoruta_frontend/                  # 📱 APLICACIÓN MÓVIL FLUTTER (CHOFERES)
    ├── pubspec.yaml                   # Dependencias y configuración del proyecto Flutter
    └── lib/
        ├── main.dart                  # Punto de entrada, tema visual oscuro y selector reactivo Login / Home
        ├── providers/
        │   └── auth_provider.dart     # Estado global de autenticación con ChangeNotifier
        ├── services/
        │   └── api_service.dart       # Cliente HTTP REST (login, envío GPS en vivo, lote offline, gamificación)
        └── screens/
            ├── login_screen.dart      # Pantalla de acceso de operadores con botón de autollenado demo
            ├── home_screen.dart       # Panel del chofer: tarjeta Eco-Nivel, jornada asignada e insignias/bonos
            ├── route_active_screen.dart # Cabina de ruta activa: velocímetro GPS, cronómetro y cola offline automática
            └── incident_screen.dart   # Reporte de incidencias en campo con captura fotográfica y GPS
```

---

## 3. Implementación Detallada del Backend (`ecoruta_backend/`)

### 3.1. Núcleo de Configuración (`EcoRuta/`)
* **[settings.py](file:///c:/Users/gabri/Desktop/App%20Django%20Gabriel/ecoruta_backend/EcoRuta/settings.py):**
  * Define `AUTH_USER_MODEL = 'security.Usuario'` para utilizar el modelo de usuario extendido con soporte de roles.
  * Configura `CSRF_TRUSTED_ORIGINS` para permitir peticiones desde `localhost`, `127.0.0.1`, Render y cualquier IP de la subred local `192.168.1.1` a `192.168.1.254` en el puerto `8000` durante desarrollo.
  * Permite conmutar entre **SQLite** (por defecto en desarrollo) y **PostgreSQL** mediante `USE_POSTGRES` o `DATABASE_URL`.
  * Configura `REST_FRAMEWORK` habilitando tres métodos simultáneos de autenticación: `JWTAuthentication`, `TokenAuthentication` y `SessionAuthentication`, con permiso global `IsAuthenticated`.
  * Aplica endurecimiento por entorno: `SECRET_KEY` obligatoria y CORS cerrado con `DEBUG=False`, cookies seguras, HSTS y cabeceras `nosniff`/`Referrer-Policy`.
  * Registra el context processor `security.context_processors.app_settings` para exponer `demo_mode` y la versión de la app a las plantillas.
  * Define localización venezolana: `LANGUAGE_CODE = 'es-ve'` y `TIME_ZONE = 'America/Caracas'`.
* **[urls.py](file:///c:/Users/gabri/Desktop/App%20Django%20Gabriel/ecoruta_backend/EcoRuta/urls.py):**
  * Redirige la raíz `/` directamente a `/dashboard/`.
  * Monta las rutas web (`/dashboard/`, `/administracion/`, `/accounts/`, `/admin/`), los endpoints de autenticación móvil (`/api/auth/login/`, `/api/token/`) y la documentación Swagger (`/api/docs/`).

---

### 3.2. Módulo de Seguridad y Usuarios (`security/`)
* **[security/models.py](file:///c:/Users/gabri/Desktop/App%20Django%20Gabriel/ecoruta_backend/security/models.py):**
  * **`Rol` (líneas 6–16):** Tabla normalizada para almacenar roles del sistema (`nombre`, `descripcion`, `creado_en`).
  * **`Usuario` (líneas 19–56):** Hereda de `AbstractUser` de Django. Añade el campo `rol` (`admin` o `chofer`) y la clave foránea `rol_ref`. Sobrescribe el método `save()` (líneas 47–53) para que todo usuario con rol `ADMIN` reciba automáticamente permisos `is_staff = True`, mientras que los usuarios con rol `CHOFER` tengan restringido el acceso al panel interno de administración.
* **[security/permissions.py](file:///c:/Users/gabri/Desktop/App%20Django%20Gabriel/ecoruta_backend/security/permissions.py):**
  * **`es_administrador(user)`:** fuente única de verdad para decidir si una cuenta puede operar el panel (`is_staff`, `is_superuser` o `rol=admin`).
  * **`admin_required`:** decorador de vistas web que redirige al login si no hay sesión y devuelve 403 con la plantilla institucional si el usuario es un chofer.
  * **`EsAdministrador`:** permiso DRF reutilizado por los ViewSets y endpoints de monitoreo.
* **[security/context_processors.py](file:///c:/Users/gabri/Desktop/App%20Django%20Gabriel/ecoruta_backend/security/context_processors.py):**
  * Expone `debug`, `demo_mode` y `app_version` a las plantillas; el botón de credenciales de demostración solo se renderiza cuando `DEBUG=True`.

---

### 3.3. Módulo de Administración y Flota (`administracion/`)
Contiene las entidades maestras, el registro de auditoría y las tablas de gamificación.

* **[administracion/models.py](file:///c:/Users/gabri/Desktop/App%20Django%20Gabriel/ecoruta_backend/administracion/models.py):**
  1. **`Vehiculo` (líneas 5–25):** Representa cada camión recolector (`placa` única, `marca`, `modelo`, `capacidad_toneladas`, `estado` [`activo`, `mantenimiento`, `inactivo`] y `rendimiento_km_por_litro`).
  2. **`Ruta` (líneas 27–41):** Define las rutas de recolección (`nombre`, `descripcion`, `zona`, `distancia_estimada_km` y `coordenadas_waypoints` en formato JSON para almacenar puntos del trazado en el mapa).
  3. **`Chofer` (líneas 43–55):** Perfil operativo vinculado 1 a 1 (`OneToOneField`) con `security.Usuario`, almacenando número de `licencia` única y `telefono`.
  4. **`RegistroCombustible` (líneas 57–72):** Historial de abastecimiento de combustible asociado a un `Vehiculo` (`fecha`, `litros`, `costo_total` en USD, `kilometraje_actual` y foto opcional del `comprobante`).
  5. **`RegistroAuditoria` (líneas 74–91):** Bitácora inmutable de seguridad que registra qué `usuario` ejecutó qué `accion` (`CREAR`, `MODIFICAR`, `ELIMINAR`), sobre cuál `tabla_afectada`, con descripción detallada (`detalles`) y fecha/hora indexada (`timestamp`).
  6. **`PuntajeChofer` (líneas 93–111):** Estado de gamificación del conductor (`puntos_totales`, `km_recorridos_totales`, `jornadas_exitosas` y `nivel`: Bronce, Plata u Oro Eco-Leyenda).
  7. **`IncentivoChofer` (líneas 113–132):** Reconocimientos e insignias otorgadas a un conductor (`titulo`, `descripcion`, `tipo_insignia` y `monto_bono_usd`).

* **[administracion/forms.py](file:///c:/Users/gabri/Desktop/App%20Django%20Gabriel/ecoruta_backend/administracion/forms.py):**
  * Define `RutaForm` y `VehiculoForm` (`ModelForm`) con widgets estilizados (`class="form-input"`) y campo oculto `coordenadas_waypoints` para recibir los puntos trazados en el mapa.

* **[administracion/views.py](file:///c:/Users/gabri/Desktop/App%20Django%20Gabriel/ecoruta_backend/administracion/views.py):**
  * **`registrar_auditoria(usuario, accion, tabla, detalles)` (líneas 8–17):** Función auxiliar invocada en cada operación administrativa para dejar trazabilidad automática en la tabla `RegistroAuditoria`.
  * **CRUD de Rutas (`ruta_crear`, `ruta_editar`, `ruta_eliminar`, líneas 20–52):** Procesa peticiones `POST` desde el panel de rutas, valida con `RutaForm` y registra el evento en auditoría.
  * **CRUD de Vehículos (`vehiculo_crear`, `vehiculo_editar`, `vehiculo_eliminar`, líneas 55–87):** Crea, actualiza o elimina camiones de la flota y redirige a `dashboard_recursos`.
  * **CRUD de Conductores (`chofer_crear`, `chofer_editar`, `chofer_eliminar`, líneas 90–151):** Crea de forma transaccional tanto la cuenta de acceso (`Usuario` con rol `CHOFER`) como su perfil `Chofer`, verificando duplicidad de nombre de usuario y número de licencia.

---

### 3.4. Módulo de Logística, Algoritmos y API REST (`logistica/`)
Es el corazón operativo que conecta la aplicación móvil de los choferes con el centro de monitoreo web.

* **[logistica/models.py](file:///c:/Users/gabri/Desktop/App%20Django%20Gabriel/ecoruta_backend/logistica/models.py):**
  1. **`Jornada` (líneas 5–26):** Vincula un `Vehiculo`, una `Ruta` y un `Chofer` en una `fecha` programada, controlando `inicio_real`, `fin_real` y `estado` (`pendiente`, `en_curso`, `finalizada`).
  2. **`PuntoGeolocalizacion` (líneas 28–41):** Cada coordenada emitida por el GPS del camión durante una `Jornada` (`latitud`, `longitud`, `precision_metros`, `velocidad_kmh` y `timestamp`).
  3. **`Incidencia` (líneas 43–64):** Eventos o alertas reportadas en ruta (`jornada`, `descripcion`, `foto`, `latitud`, `longitud`, `estado` [`pendiente`, `en_atencion`, `resuelta`], `resolucion_detalles` y `resuelta_en`).

* **[logistica/optimizador.py](file:///c:/Users/gabri/Desktop/App%20Django%20Gabriel/ecoruta_backend/logistica/optimizador.py) (Eco-Calculadora y Huella de Carbono):**
  * **`calcular_eficiencia_ecologica(distancia_km, rendimiento_km_l, capacidad_toneladas)`:**
    * Utiliza la constante `FACTOR_EMISION_CO2_DIESEL = 0.264` kg de $\text{CO}_2$ por km.
    * Calcula `litros_estimados = distancia / rendimiento`, `costo_estimado_usd = litros * 0.50`, `emision_co2_kg` y `co2_ahorrado_estimado_kg` (15% de reducción por optimización de ruta).
    * Otorga una calificación ecológica automática: **`A+`** ($\ge 5.5\text{ km/L}$), **`A`** ($\ge 4.5\text{ km/L}$) o **`B`** ($< 4.5\text{ km/L}$).

* **[logistica/gamificacion.py](file:///c:/Users/gabri/Desktop/App%20Django%20Gabriel/ecoruta_backend/logistica/gamificacion.py) (Motor de Gamificación de Conductores):**
  * **`evaluar_y_actualizar_puntaje_chofer(chofer)`:**
    * Consulta todas las jornadas con `estado='finalizada'` del chofer, suma los kilómetros recorridos y calcula el puntaje con la fórmula:
      $$\text{Puntos} = (\text{Km Totales} \times 10) + (\text{Jornadas Finalizadas} \times 50)$$
    * Clasifica al conductor en nivel **Oro** ($\ge 1000\text{ pts}$), **Plata** ($\ge 400\text{ pts}$) o **Bronce** ($< 400\text{ pts}$).
    * Otorga automáticamente insignias y bonos en dólares en la tabla `IncentivoChofer` cuando el conductor alcanza metas:
      * *Primera Ruta Ecológica Finalizada* (`+$10.00 USD`).
      * *Maestro del Volante (100+ Km)* (`+$25.00 USD`).
      * *Chofer Estrella EcoRuta (500+ pts)* (`+$50.00 USD`).

* **[logistica/views.py](file:///c:/Users/gabri/Desktop/App%20Django%20Gabriel/ecoruta_backend/logistica/views.py) y [logistica/urls.py](file:///c:/Users/gabri/Desktop/App%20Django%20Gabriel/ecoruta_backend/logistica/urls.py) (Endpoints de la API REST):**
  * `GET/POST /api/logistica/jornadas/` (`JornadaViewSet`): CRUD REST de jornadas.
  * `GET/POST /api/logistica/puntos/` (`PuntoGeolocalizacionViewSet`): Recepción individual de coordenadas GPS en vivo desde la app móvil.
  * `GET/POST /api/logistica/incidencias/` (`IncidenciaViewSet`): Recepción de reportes de incidencias con fotografía (`multipart/form-data`).
  * `POST /api/logistica/coordenadas/sincronizar_lote/` (`sincronizar_puntos_lote`, líneas 35–65): Recibe un arreglo JSON de puntos GPS acumulados cuando el teléfono del chofer estuvo sin internet y los inserta de forma masiva y eficiente mediante `bulk_create()`.
  * `GET /api/logistica/monitoreo_en_vivo/` (`monitoreo_en_vivo`, líneas 87–140): Devuelve en JSON todos los camiones con jornada `en_curso`, su última coordenada, velocidad, precisión, los últimos 35 puntos ordenados cronológicamente para dibujar la polilínea de recorrido en el mapa y las 25 incidencias más recientes.
  * `POST /api/logistica/simular_gps_paso/` (`simular_gps_paso`, líneas 149–206): Simulador interactivo de telemetría sobre un circuito de 10 waypoints reales de **Anaco** (`SIMULATION_WAYPOINTS_ANACO`: Plaza Bolívar, Av. Miranda, Av. Mérida, Av. Portuguesa, Campo Norte, Redoma Norte, Av. José Antonio Anzoátegui, Sector Las Charas, Av. Zulia y Casco Central) con micro-variaciones aleatorias de posición y velocidad.
  * `POST /api/logistica/simular_incidencia/` (`simular_incidencia_api`, líneas 215–250): Genera una incidencia de prueba georreferenciada en Anaco para demostraciones en vivo.
  * `POST /api/logistica/incidencias/<pk>/gestionar/` (`gestionar_incidencia_api`, líneas 259–280): Permite cambiar el estado de una incidencia a `en_atencion` o `resuelta` con notas de resolución.
  * `GET /api/logistica/rutas/<pk>/optimizar/` (`optimizar_ruta_api`, líneas 289–297): Devuelve el análisis ecológico de una ruta invocando `calcular_eficiencia_ecologica()`.
  * `GET /api/logistica/notificaciones/` (`notificaciones_chofer`, líneas 306–322): Devuelve al chofer autenticado sus jornadas pendientes asignadas.
  * `GET /api/logistica/chofer/gamificacion/` (`chofer_gamificacion_api`, líneas 331–357): Recalcula y devuelve al móvil del chofer sus puntos, nivel, kilómetros e insignias con bonos.

---

### 3.5. Módulo de Dashboard Web y Reportes (`dashboard/`)
Gestiona todas las pantallas administrativas y la generación de documentos oficiales.

* **[dashboard/views.py](file:///c:/Users/gabri/Desktop/App%20Django%20Gabriel/ecoruta_backend/dashboard/views.py) y [dashboard/urls.py](file:///c:/Users/gabri/Desktop/App%20Django%20Gabriel/ecoruta_backend/dashboard/urls.py):**
  1. **`dashboard_home` (`/dashboard/`, líneas 23–77):** Calcula los indicadores ejecutivos en tiempo real (total de unidades, disponibilidad porcentual, jornadas del día, kilómetros supervisados, litros despachados, incidencias pendientes y serie semanal de toneladas) y renderiza `home.html`.
  2. **`rutas_gestion` (`/dashboard/rutas/`, líneas 81–88):** Lista el catálogo de rutas ecológicas y unidades para el trazado de waypoints y simulador de consumo en `rutas.html`.
  3. **`auditoria_listado` (`/dashboard/auditoria/`, líneas 92–97):** Muestra los últimos 100 eventos de la bitácora `RegistroAuditoria` en `auditoria.html`.
  4. **`incentivos_listado` (`/dashboard/incentivos/`, líneas 100–112):** Evalúa a todos los choferes con `evaluar_y_actualizar_puntaje_chofer()` y presenta el ranking de puntos y bonos en `incentivos.html`.
  5. **`conductores_gestion` (`/dashboard/conductores/`, líneas 115–120):** Panel de administración de choferes y licencias en `conductores.html`.
  6. **`itinerario`, `jornada_crear`, `jornada_eliminar` (`/dashboard/itinerario/`, líneas 123–168):** Programación y asignación de recorridos vinculando camión, ruta, chofer y fecha en `itinerario.html`.
  7. **`mapa_monitoreo` (`/dashboard/mapa/`, líneas 171–223):** Carga las posiciones iniciales de la flota en Anaco y las alertas para el centro de monitoreo GPS en vivo (`mapa.html`).
  8. **`recursos`, `recurso_crear`, `recurso_eliminar` (`/dashboard/recursos/`, líneas 226–271):** Gestión de unidades recolectoras y registro de cargas de combustible con cálculo de consumo total y rendimiento promedio (`recursos.html`).
  9. **`exportar_recursos_excel` (`/dashboard/recursos/exportar/excel/`, líneas 274–370):** Construye con `openpyxl` el archivo `Reporte_Combustible_Aseo_Urbano.xlsx` con 3 hojas formateadas y auto-ajustadas: *Unidades*, *Combustible* (con fila de totales) y *Jornadas*.
  10. **`exportar_recursos_pdf` (`/dashboard/recursos/exportar/pdf/`, líneas 374–585):** Genera con `ReportLab` el documento formal `Reporte_Combustible_Aseo_Urbano.pdf` con membrete oficial (*República Bolivariana de Venezuela - Alcaldía del Municipio Anaco - Dirección de Aseo Urbano*), ficha resumen, cuadros de unidades, abastecimiento de combustible, últimas jornadas y bloque de firmas al pie.
  11. **`incidencias_gestion`, `incidencia_crear`, `incidencia_actualizar`, `incidencia_eliminar` (`/dashboard/incidencias/`, líneas 589–685):** Centro de control de incidencias con contadores por estado (`pendiente`, `en_atencion`, `resuelta`) y registro automático en auditoría.

* **Plantillas HTML ([dashboard/templates/dashboard/](file:///c:/Users/gabri/Desktop/App%20Django%20Gabriel/ecoruta_backend/dashboard/templates/dashboard/)):**
  * **[base.html](file:///c:/Users/gabri/Desktop/App%20Django%20Gabriel/ecoruta_backend/dashboard/templates/dashboard/base.html):** Layout maestro con menú lateral de navegación, cabecera superior con campana de notificaciones en vivo y estilos institucionales.
  * **[home.html](file:///c:/Users/gabri/Desktop/App%20Django%20Gabriel/ecoruta_backend/dashboard/templates/dashboard/home.html):** Resumen ejecutivo, tarjetas KPI, gráfico Chart.js y tabla de actividad reciente.
  * **[mapa.html](file:///c:/Users/gabri/Desktop/App%20Django%20Gabriel/ecoruta_backend/dashboard/templates/dashboard/mapa.html):** Mapa interactivo Leaflet con actualización automática, lista lateral de camiones, trazado de ruta y botones de simulación GPS.
  * **[rutas.html](file:///c:/Users/gabri/Desktop/App%20Django%20Gabriel/ecoruta_backend/dashboard/templates/dashboard/rutas.html):** CRUD de rutas con editor visual de puntos sobre el mapa y calculadora de huella de carbono.
  * **[itinerario.html](file:///c:/Users/gabri/Desktop/App%20Django%20Gabriel/ecoruta_backend/dashboard/templates/dashboard/itinerario.html), [conductores.html](file:///c:/Users/gabri/Desktop/App%20Django%20Gabriel/ecoruta_backend/dashboard/templates/dashboard/conductores.html), [recursos.html](file:///c:/Users/gabri/Desktop/App%20Django%20Gabriel/ecoruta_backend/dashboard/templates/dashboard/recursos.html), [incidencias.html](file:///c:/Users/gabri/Desktop/App%20Django%20Gabriel/ecoruta_backend/dashboard/templates/dashboard/incidencias.html), [incentivos.html](file:///c:/Users/gabri/Desktop/App%20Django%20Gabriel/ecoruta_backend/dashboard/templates/dashboard/incentivos.html), [auditoria.html](file:///c:/Users/gabri/Desktop/App%20Django%20Gabriel/ecoruta_backend/dashboard/templates/dashboard/auditoria.html):** Interfaces específicas de cada módulo operativo.

---

## 4. Implementación Detallada de la App Móvil (`ecoruta_frontend/`)

Toda la lógica de la aplicación móvil reside dentro de `ecoruta_frontend/lib/`:

1. **[lib/main.dart](file:///c:/Users/gabri/Desktop/App%20Django%20Gabriel/ecoruta_frontend/lib/main.dart):**
   * Inicializa `MultiProvider` inyectando `AuthProvider`.
   * Configura el tema Material 3 oscuro (`scaffoldBackgroundColor: #070B12`, verde esmeralda primario `#10B981`).
   * Evalúa reactivamente `auth.isAuthenticated`: si el chofer tiene sesión activa muestra `HomeScreen()`, de lo contrario muestra `LoginScreen()`.

2. **[lib/providers/auth_provider.dart](file:///c:/Users/gabri/Desktop/App%20Django%20Gabriel/ecoruta_frontend/lib/providers/auth_provider.dart):**
   * Administra el estado de autenticación (`isAuthenticated`, `isLoading`).
   * Al abrir la app ejecuta `_checkAuthStatus()` para verificar si existe un token guardado en el almacenamiento seguro del dispositivo y mantener la sesión iniciada.

3. **[lib/services/api_service.dart](file:///c:/Users/gabri/Desktop/App%20Django%20Gabriel/ecoruta_frontend/lib/services/api_service.dart):**
   * **Detección inteligente de plataforma (`baseUrl`):** Si se ejecuta en Web o Windows apunta a `http://127.0.0.1:8000/api`; en Android/iOS usa la URL configurable desde el login (por defecto `http://192.168.1.112:8000/api`) y recuerda la última dirección guardada.
   * **`login(username, password)`:** Envía credenciales a `/api/auth/login/`, cifra el token devuelto en `FlutterSecureStorage` y expone `lastError` para mensajes claros.
   * **`sendLocation(...)`:** Envía latitud, longitud, velocidad en km/h y precisión a `/api/logistica/puntos/`.
   * **`sincronizarLote(puntos)`:** Envía la cola de coordenadas acumuladas sin conexión a `/api/logistica/coordenadas/sincronizar_lote/`, conservando la marca de tiempo original.
   * **Cola offline persistente (`loadOfflineQueue` / `saveOfflineQueue`):** Sobrevive al cierre de la app y se limita a 2000 puntos para no crecer indefinidamente.
   * **`getGamificacion()` y `getNotificaciones()`:** Consultan el perfil de puntos/bonos y las jornadas asignadas al chofer.

4. **[lib/screens/login_screen.dart](file:///c:/Users/gabri/Desktop/App%20Django%20Gabriel/ecoruta_frontend/lib/screens/login_screen.dart):**
   * Interfaz de inicio de sesión con validación de campos, ocultamiento de contraseña, autofill y configuración de la URL del servidor. El botón de demostración solo se muestra en compilaciones de depuración (`kDebugMode`).

5. **[lib/screens/home_screen.dart](file:///c:/Users/gabri/Desktop/App%20Django%20Gabriel/ecoruta_frontend/lib/screens/home_screen.dart):**
   * Muestra la tarjeta de perfil gamificado del chofer (Nivel actual, Puntos Eco, Distancia total y Jornadas exitosas).
   * Muestra la tarjeta de la jornada activa asignada por el supervisor desde el dashboard web.
   * Incluye el botón principal **"Iniciar Jornada de Recolección"** que abre `RouteActiveScreen` y la lista de insignias y bonos en USD obtenidos.

6. **[lib/screens/route_active_screen.dart](file:///c:/Users/gabri/Desktop/App%20Django%20Gabriel/ecoruta_frontend/lib/screens/route_active_screen.dart):**
   * Solicita permisos de ubicación satelital (`Geolocator.checkPermission()` / `requestPermission()`).
   * Activa un cronómetro de jornada (`_elapsedTimer` cada 1 segundo) y un temporizador de telemetría (`_gpsTimer` cada 10 segundos).
   * En `_captureAndSendGps()`: obtiene la posición GPS de alta precisión con límite de tiempo, convierte la velocidad de $\text{m/s}$ a $\text{km/h}$ (`position.speed * 3.6`) y la transmite al servidor.
   * **Resiliencia Offline (`_offlinePointsQueue`):** Si el envío falla por falta de cobertura móvil, el punto GPS se guarda en la cola persistente del dispositivo con su marca de tiempo y se muestra un indicador *"En Cola Offline"*. Al recuperarse la conexión, se sincroniza automáticamente con `sincronizarLote()`.
   * Maneja permisos denegados o bloqueados con acceso directo a los ajustes del sistema.

7. **[lib/screens/incident_screen.dart](file:///c:/Users/gabri/Desktop/App%20Django%20Gabriel/ecoruta_frontend/lib/screens/incident_screen.dart):**
   * Permite al chofer describir una eventualidad en la vía, tomar una foto con la cámara (`ImagePicker().pickImage(source: ImageSource.camera)`), capturar las coordenadas GPS exactas del incidente y enviarlo mediante una petición `http.MultipartRequest` a `/api/logistica/incidencias/`.

---

## 5. Flujo Completo de Operación (De Punta a Punta)

1. **Configuración Inicial (Web):** El administrador ingresa a `/dashboard/`, registra las unidades recolectoras (`Vehiculo`), los conductores (`Chofer` + `Usuario`) y traza las rutas ecológicas (`Ruta`) en `administracion/views.py`.
2. **Asignación de Recorrido (Web):** En `/dashboard/itinerario/`, el supervisor crea una `Jornada` asignando camión, ruta, chofer y fecha.
3. **Recepción en Campo (Móvil):** El chofer inicia sesión en la app Flutter (`login_screen.dart`), la cual consulta `/api/logistica/notificaciones/` y muestra la ruta asignada en `home_screen.dart`.
4. **Rastreo GPS en Tiempo Real (Móvil $\rightarrow$ API $\rightarrow$ Mapa Web):**
   * El chofer pulsa *"Iniciar Jornada"* (`route_active_screen.dart`) y su dispositivo emite coordenadas cada 10 segundos a `POST /api/logistica/puntos/` (o por lote en `/coordenadas/sincronizar_lote/` si hubo pérdida de señal).
   * El centro de monitoreo web (`/dashboard/mapa/`) consulta periódicamente `GET /api/logistica/monitoreo_en_vivo/` y actualiza en el mapa Leaflet la ubicación, velocidad y estela de recorrido de cada camión.
5. **Reporte y Resolución de Incidencias (Móvil $\leftrightarrow$ Web):** Si ocurre un imprevisto en la vía, el chofer toma una foto desde `incident_screen.dart`; la alerta aparece en el mapa y en `/dashboard/incidencias/`, donde el supervisor cambia su estado a *En Atención* o *Resuelta*, quedando registrado en `RegistroAuditoria`.
6. **Cierre, Gamificación y Reportes (API + Web):** Al finalizar las jornadas, el módulo `logistica/gamificacion.py` actualiza los kilómetros, puntos, nivel e insignias del chofer, y la dirección puede exportar el balance operativo en **Excel** o **PDF institucional** desde `/dashboard/recursos/`.

