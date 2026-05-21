@echo off
set SCRIPT_DIR=%~dp0
powershell.exe -STA -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%DesktopPet.ps1" -PetId "kai"
