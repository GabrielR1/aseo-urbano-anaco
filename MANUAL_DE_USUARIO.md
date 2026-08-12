# 🌿 Manual de Usuario EcoRuta — Plataforma de Gestión de Rutas Ecológicas

Bienvenido al **Manual de Usuario de EcoRuta**. Este documento explica de forma resumida, clara y completa cómo operar el sistema **EcoRuta**, tanto desde la **Plataforma Web (Administrador)** como desde la **Aplicación Móvil (Chofer)**.

---

## 📌 1. Visión General del Sistema

EcoRuta consta de dos módulos integrados:
1. **EcoRuta Backend & Panel Web** (`ecoruta_backend`): Plataforma administrativa construida en Django para supervisar rutas, vehículos, conductores, combustible y monitoreo GPS en tiempo real.
2. **EcoRuta Móvil** (`ecoruta_frontend`): Aplicación móvil construida en Flutter para que los choferes registren el recorrido GPS automático de su jornada y reporten incidencias con fotografía.

---

## 🌐 2. Guía del Panel Web Administrador

### 🔑 2.1 Acceso al Sistema
- **URL Base**: [http://127.0.0.1:8000/accounts/login/](http://127.0.0.1:8000/accounts/login/)
- **URL Panel Admin Django**: [http://127.0.0.1:8000/admin/](http://127.0.0.1:8000/admin/)
- **Credenciales por defecto**:
  - **Administrador**: Usuario `admin` | Contraseña `admin123`

> 💡 **Funciones en Login**:
> - Utiliza el botón del **ojo (👁️)** a la derecha del campo de contraseña para mostrar u ocultar el texto ingresado.
> - Si olvidaste tu contraseña, haz clic en **"¿Olvidaste tu contraseña?"** para iniciar el flujo de restablecimiento.

---

### 📊 2.2 Secciones del Dashboard Web (`/dashboard/`)

#### A. Resumen Ejecutivo (`/dashboard/`)
- Muestra tarjetas dinámicas con indicadores clave:
  - 🚚 **Vehículos Activos**
  - 🗺️ **Jornadas Planificadas Hoy**
  - ⚠️ **Incidencias Registradas**
- Gráfico interactivo de **Efectividad Semanal de Recolección (Toneladas)**.

#### B. Planificación de Itinerarios (`/dashboard/itinerario/`)
- Vista de calendario interactivo para consultar asignaciones por fecha.
- **Asignar Nueva Jornada**: Haz clic en el botón verde **"+ Asignar Nueva Jornada"** para desplegar la ventana emergente e ingresar el vehículo, la ruta y la fecha.

#### C. Monitoreo en Vivo en Mapa (`/dashboard/mapa/`)
- Mapa interactivo GPS (Leaflet) que muestra la ubicación exacta de los camiones de recolección en servicio.
- Marcadores de **incidencias en tiempo real** reportadas por los choferes desde la aplicación móvil.

#### D. Gestión de Recursos (`/dashboard/recursos/`)
- Control mensual de consumo de combustible (Litros y Costo total).
- Tabla interactiva con historial de carga.
- **Registrar Combustible**: Haz clic en **"+ Nuevo Registro de Carga"** para abrir el formulario emergente.
- Tarjetas interactivas con el estado de salud y rendimiento de la flota de transporte.

---

## 📱 3. Guía de la Aplicación Móvil (Chofer)

### 🔑 3.1 Inicio de Sesión
- Abre la app `ecoruta_frontend`.
- Ingresa las credenciales del conductor:
  - **Chofer de Prueba**: Usuario `chofer1` | Contraseña `chofer123`
- Presiona **"Ingresar"**.

---

### 🚚 3.2 Iniciar y Ejecutar Jornada
1. En la pantalla principal, presiona **"Iniciar Jornada"**.
2. La app solicitará permisos de ubicación GPS. Al aceptarlos, se activará el **rastreo en tiempo real**.
3. Las coordenadas (latitud y longitud) se enviarán automáticamente cada 15 segundos al servidor central.

---

### 🚨 3.3 Reportar Incidencia con Foto
Si ocurre un obstáculo durante la ruta (falla mecánica, vía cerrada, derrame, etc.):
1. Presiona el botón rojo **"Reportar Incidencia"**.
2. Escribe una descripción breve del evento.
3. Presiona **"Tomar Foto"** para capturar la evidencia con la cámara.
4. Presiona **"Enviar Reporte"**. Las coordenadas exactas y la foto se registrarán de inmediato en el mapa del Administrador.

---

### 🛑 3.4 Finalizar Jornada
Al concluir el recorrido de recolección:
1. En la pantalla de ruta activa, presiona **"Finalizar Jornada"**.
2. El rastreo GPS automático se detendrá de inmediato.

---

## 🛠️ 4. Guía Rápida de Comandos de Inicio

Para iniciar los servidores manualmente desde la consola:

### Iniciar Backend Django:
```powershell
cd ecoruta_backend
..\venv\Scripts\python.exe manage.py runserver 0.0.0.0:8000
```

### Iniciar Frontend Flutter (Navegador o Windows):
```powershell
cd ecoruta_frontend
flutter run -d chrome
# o en versión nativa:
flutter run -d windows
```

---
*EcoRuta v1.0 — Innovación y Eficiencia en Gestión Ecológica de Rutas*
