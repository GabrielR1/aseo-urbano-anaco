@echo off
chcp 65001 >nul
title Servidor EcoRuta Backend - Django

:: Obtener la IP local de la maquina
set "MY_IP=127.0.0.1"
for /f "tokens=2 delims=:" %%i in ('ipconfig ^| findstr /i "IPv4"') do (
    set "MY_IP=%%i"
)
set "MY_IP=%MY_IP: =%"

echo ===================================================
echo        INICIANDO SERVIDOR ECORUTA BACKEND
echo ===================================================
echo.
echo [!] Dashboard Local (PC):   http://127.0.0.1:8000/dashboard/
echo [!] Dashboard Red Local:    http://%MY_IP%:8000/dashboard/
echo [!] Django Admin:           http://127.0.0.1:8000/admin/
echo.
echo [!] INICIANDO TÚNEL PÚBLICO EN OTRA VENTANA...
echo     Copia el enlace HTTPS (https://....trycloudflare.com)
echo     de la otra ventana y envíaselo a tu profesor.
echo ===================================================
echo.

set "PROJECT_DIR=C:\Users\gabri\Desktop\App Django Gabriel"
set "BACKEND_DIR=%PROJECT_DIR%\ecoruta_backend"
set "PYTHON_EXE=%PROJECT_DIR%\venv\Scripts\python.exe"

cd /d "%BACKEND_DIR%"

:: Abrir el túnel público de Cloudflare en una ventana secundaria
if exist "%PROJECT_DIR%\cloudflared.exe" (
    start "ENLACE PUBLICO PARA EL PROFESOR" cmd /k ""%PROJECT_DIR%\cloudflared.exe" tunnel --url http://127.0.0.1:8000"
)

:: Abrir navegador local automáticamente
start /b cmd /c "timeout /t 2 /nobreak >nul & start http://127.0.0.1:8000/dashboard/"

:: Ejecutar el servidor Django
"%PYTHON_EXE%" manage.py runserver 0.0.0.0:8000

echo.
echo [!] Servidor finalizado.
pause


