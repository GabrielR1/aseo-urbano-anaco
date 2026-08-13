# 🌿 EcoRuta - Sistema de Gestión y Transporte Ecológico

> **"Limpiando nuestro presente, para disfrutar el futuro."**

EcoRuta es una plataforma integral de gestión de rutas ecológicas y recolección de desechos, conformada por un **Backend en Django** (Panel Web Administrativo y API REST) y un **Frontend en Flutter** (Aplicación Móvil para Choferes y Personal de Campo).

---

## 👨‍🏫 Guía Rápida para el Profesor / Evaluador

Para clonar y ejecutar el proyecto localmente en su equipo, siga los siguientes pasos:

### 1️⃣ Clonar el Repositorio de GitHub

Abra su terminal / consola de comandos y ejecute:

```bash
git clone https://github.com/Omar8394/programacion4.git
cd programacion4
```

---

### 2️⃣ Configuración y Ejecución del Backend (Django)

#### En Windows (PowerShell / Command Prompt):
```cmd
# 1. Crear entorno virtual (si no existe)
python -m venv venv

# 2. Activar el entorno virtual
venv\Scripts\activate

# 3. Instalar las dependencias del proyecto
pip install -r ecoruta_backend/requirements.txt

# 4. Entrar al directorio del backend
cd ecoruta_backend

# 5. Iniciar el servidor local
python manage.py runserver 0.0.0.0:8000
```

#### En Linux / macOS:
```bash
# 1. Crear entorno virtual
python3 -m venv venv

# 2. Activar el entorno virtual
source venv/bin/activate

# 3. Instalar dependencias
pip install -r ecoruta_backend/requirements.txt

# 4. Entrar al directorio del backend
cd ecoruta_backend

# 5. Iniciar el servidor
python manage.py runserver 0.0.0.0:8000
```

---

### 🔑 Credenciales de Acceso para Pruebas

El repositorio incluye la base de datos preconfigurada con datos de prueba (Rutas, Vehículos, Cargas y Personal). Puede ingresar inmediatamente con las siguientes credenciales:

* **Panel Dashboard Web (Administrativo):** [http://127.0.0.1:8000/dashboard/](http://127.0.0.1:8000/dashboard/)
* **Panel de Administración Django:** [http://127.0.0.1:8000/admin/](http://127.0.0.1:8000/admin/)
* **Usuario:** `admin`
* **Contraseña:** `admin123`

---

### 3️⃣ Ejecución del Frontend Móvil (Flutter - Opcional)

Si desea probar la aplicación móvil para choferes:

```bash
cd ecoruta_frontend
flutter pub get
flutter run -d chrome   # Para ejecutar en navegador Web
# o bien:
flutter run             # Para ejecutar en emulador/dispositivo Android o iOS
```

---

## 🛠️ Tecnologías y Arquitectura

* **Backend:** Python 3.12, Django 5.x, Django REST Framework (DRF), JWT Authentication, SQLite/PostgreSQL.
* **Frontend Web:** HTML5, CSS3 Glassmorphism (Diseño Eco-Verde Esmeralda), JavaScript Vanilla, FontAwesome, Google Fonts (Outfit).
* **Aplicación Móvil:** Flutter SDK (Dart 3.x), Provider (Gestión de Estado), HTTP REST Client.
* **Documentación:** [`MANUAL_DE_USUARIO.md`](MANUAL_DE_USUARIO.md) incluido en el directorio raíz.
