@echo off
title LawnHive Workspace - Update
cd /d "%~dp0"

:: Show "updating" message
mshta "javascript:var sh=new ActiveXObject('WScript.Shell');sh.Popup('LawnHive Workspace is updating... Please keep the software closed during this process.',0,'LawnHive Workspace Update',64);close()"

:: Pull latest image silently
docker compose pull --quiet >nul 2>&1
if errorlevel 1 goto :fail

:: Restart containers with new image silently
docker compose up -d --remove-orphans >nul 2>&1
if errorlevel 1 goto :fail

:: Wait a moment for containers to start
timeout /t 5 /nobreak >nul

:: Show success message
mshta "javascript:var sh=new ActiveXObject('WScript.Shell');sh.Popup('Update completed successfully! Now click the LawnHive Workspace icon to open the software.',0,'LawnHive Workspace Update',64);close()"

exit /b 0

:fail
:: Show error message
mshta "javascript:var sh=new ActiveXObject('WScript.Shell');sh.Popup('Update could not be completed. Please check your internet connection and try again.',0,'LawnHive Workspace Update',16);close()"

exit /b 1
