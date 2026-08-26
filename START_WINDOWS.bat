@echo off
setlocal
title StreamVista - iniciar aplicacion
cd /d "%~dp0"

echo.
echo === StreamVista IPTV para Windows ===
echo.

where flutter >nul 2>nul
if errorlevel 1 (
  echo ERROR: Flutter no esta disponible en PATH.
  echo Instala Flutter, cierra esta ventana y vuelve a abrir este archivo.
  pause
  exit /b 1
)

if not exist "pubspec.yaml" (
  echo ERROR: No se encontro pubspec.yaml.
  echo Extrae TODO el archivo ZIP antes de abrir este archivo.
  pause
  exit /b 1
)

if not exist "windows\CMakeLists.txt" (
  echo Preparando los archivos de Windows. Espera un momento...
  call flutter create --platforms=windows .
  if errorlevel 1 goto :failed
)

echo Descargando componentes de la aplicacion...
call flutter pub get
if errorlevel 1 goto :failed

echo Abriendo StreamVista...
call flutter run -d windows
goto :end

:failed
echo.
echo La preparacion no pudo terminar. Copia el texto de esta ventana y envialo.

:end
pause
