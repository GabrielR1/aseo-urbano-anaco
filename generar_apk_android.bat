@echo off
chcp 65001 >nul
title Generador de APK para Teléfono Android - EcoRuta Chofer

echo =========================================================
echo    GENERANDO INSTALADOR APK PARA TELÉFONO ANDROID
echo =========================================================
echo.
echo Compilando la aplicación móvil de Flutter para Android...
echo Por favor espera un momento mientras se crea el archivo .apk
echo.

set "PATH=%PATH%;C:\Users\gabri\flutter\bin;%LOCALAPPDATA%\Android\Sdk\platform-tools"

cd /d "%~dp0ecoruta_frontend"
call flutter build apk --release

echo.
if exist "%~dp0ecoruta_frontend\build\app\outputs\flutter-apk\app-release.apk" (
    echo =========================================================
    echo  [OK] ¡APK GENERADO CON ÉXITO!
    echo =========================================================
    echo.
    echo Ubicación del archivo instalador:
    echo "%~dp0ecoruta_frontend\build\app\outputs\flutter-apk\app-release.apk"
    echo.
    echo Pasos para instalarlo en tu teléfono:
    echo 1. Pásate el archivo "app-release.apk" al teléfono por WhatsApp, Telegram, Cable USB o Google Drive.
    echo 2. En tu teléfono, ábrelo y pulsa "Instalar".
    echo 3. ¡Listo! Tendrás la app Aseo Urbano Chofer con su icono oficial en tu celular.
    echo =========================================================
    explorer /select,"%~dp0ecoruta_frontend\build\app\outputs\flutter-apk\app-release.apk"
) else (
    echo [!] Si no tienes configurado el SDK de Android en tu PC, 
    echo     puedes usar la app en modo Web o probarla en Chrome con:
    echo     iniciar_app_movil.bat
)

pause
