@echo off
chcp 65001 >nul
title EcoRuta Movil - App de Chofer (Flutter)

echo ===================================================
echo    INICIANDO APLICACION MOVIL DEL CHOFER (FLUTTER)
echo ===================================================
echo.
echo [!] Usuario de prueba Chofer: chofer1
echo [!] Contraseña Chofer:        chofer123
echo.
echo Presiona cualquier tecla para abrir la app en Chrome...
echo ===================================================
echo.

set "PATH=%PATH%;C:\Users\gabri\flutter\bin"

cd /d "%~dp0ecoruta_frontend"
flutter run -d chrome

pause
