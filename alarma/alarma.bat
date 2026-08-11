@echo off
rem Lanzador: abre alarma.ps1 (mismo nombre, misma carpeta) sin consola visible.
start "" powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dpn0.ps1" %*
