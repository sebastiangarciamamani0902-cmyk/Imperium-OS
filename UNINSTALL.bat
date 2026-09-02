@echo off
:: ============================================
:: IMPERIUM OS - UNINSTALL / ROLLBACK (Auto-Admin)
:: Double-click or run in CMD. Requests Admin.
:: ============================================
net session >nul 2>&1
if %errorLevel% neq 0 (
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0imperium_uninstall.ps1"
