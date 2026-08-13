# 🌿 EcoRuta - Sistema de Gestión y Transporte Ecológico

> **"Limpiando nuestro presente, para disfrutar el futuro."**

EcoRuta es una plataforma integral para la gestión, optimización y seguimiento de rutas ecológicas y recolección de desechos. El sistema consta de un **Backend en Django** (Panel Web Administrativo y API REST) y un **Frontend en Flutter** (Aplicación Móvil para Choferes y Personal de Campo).

---

## 🏗️ Arquitectura del Sistema

* **Backend (Django 5.x):**
  * Panel Web Administrativo con interfaz moderna Eco-Verde (Glassmorphism UI).
  * API RESTful construida con Django REST Framework y autenticación mediante JWT.
  * Base de Datos SQLite preconfigurada para entorno de desarrollo y pruebas.

* **Frontend (Flutter 3.x):**
  * Aplicación móvil multiplataforma para choferes y recolectores.
  * Seguimiento de rutas de recolección en tiempo real y reporte de incidencias.

---

## 🚀 Instalación y Configuración del Entorno Local

### 1. Requisitos Previos
* Python 3.10 o superior
* Flutter SDK 3.x (Opcional, para ejecución del módulo móvil)

### 2. Configuración del Backend (Django)

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

# 4. Iniciar el servidor de desarrollo
cd ecoruta_backend
python manage.py runserver 0.0.0.0:8000
```

---

## 🔑 Accesos del Sistema

* **Panel Dashboard Web:** [http://127.0.0.1:8000/dashboard/](http://127.0.0.1:8000/dashboard/)
* **Panel de Administración Django:** [http://127.0.0.1:8000/admin/](http://127.0.0.1:8000/admin/)
* **Usuario por defecto:** `admin`
* **Contraseña por defecto:** `admin123`

---

## 📱 Configuración del Frontend (Flutter)

```bash
cd ecoruta_frontend
flutter pub get
flutter run -d chrome
```

---

## 📄 Documentación Adicional

Para más información sobre la arquitectura detallada, modelos de datos y flujo de trabajo, consulte el archivo [`MANUAL_DE_USUARIO.md`](MANUAL_DE_USUARIO.md).
