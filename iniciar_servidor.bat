@echo off
chcp 65001 >nul
title Servidor Local EcoRuta Backend - Django

:: Obtener la IP local de la maquina
set "MY_IP=127.0.0.1"
for /f "tokens=2 delims=:" %%i in ('ipconfig ^| findstr /i "IPv4"') do (
    set "MY_IP=%%i"
)
set "MY_IP=%MY_IP: =%"

echo ===================================================
echo        INICIANDO SERVIDOR LOCAL ECORUTA
echo ===================================================
echo.
echo [!] Dashboard Local:      http://127.0.0.1:8000/dashboard/
echo [!] Dashboard Red Local:  http://%MY_IP%:8000/dashboard/
echo [!] Panel de Admin:       http://127.0.0.1:8000/admin/
echo ===================================================
echo.

set "PROJECT_DIR=%~dp0"
set "BACKEND_DIR=%PROJECT_DIR%ecoruta_backend"

cd /d "%BACKEND_DIR%"

:: Abrir navegador local automaticamente despues de 2 segundos
start /b cmd /c "timeout /t 2 /nobreak >nul & start http://127.0.0.1:8000/dashboard/"

:: Ejecutar servidor Django con python del sistema o entorno virtual
if exist "%PROJECT_DIR%venv\Scripts\python.exe" (
    "%PROJECT_DIR%venv\Scripts\python.exe" manage.py runserver 0.0.0.0:8000
) else (
    python manage.py runserver 0.0.0.0:8000
)

echo.
echo [!] Servidor finalizado.
pause
