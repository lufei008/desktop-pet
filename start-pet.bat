@echo off
set SCRIPT_DIR=%~dp0
set PET_ID=%~1
if "%PET_ID%"=="" set PET_ID=bully
powershell.exe -STA -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%DesktopPet.ps1" -PetId "%PET_ID%"
