# ============================================================
#  IMPERIUM OS - UNINSTALL / ROLLBACK (portable)
#  v32.0
#  Retira SOLO lo que el instalador de Imperium creo.
#  - Politicas de extension (Forcelist/ExtensionSettings) en Chrome
#  - Hardening incognito/invitado/perfiles en Chrome y Edge
#  - Tareas programadas ImperiumOS-*
#  - Carpeta %LOCALAPPDATA%\ImperiumOS (guard/reparador/logs)
#  NO toca datos del usuario, Core ni el Megafiltro/extension instalada
#  en Chrome (eso lo gestiona Chrome, no este script).
# ============================================================

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Se requieren permisos de administrador. Elevando..." -ForegroundColor Yellow
    Start-Process powershell -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    exit
}

$ErrorActionPreference = "SilentlyContinue"
$ExtensionID = "ajilohlkmkjipipjagpnokhinhbjfkfb"

Write-Host ""
Write-Host "==============================================" -ForegroundColor Yellow
Write-Host "  IMPERIUM OS - DESINSTALAR / ROLLBACK" -ForegroundColor Yellow
Write-Host "==============================================" -ForegroundColor Yellow
Write-Host ""

# ---------- 1. Quitar politica de extension en Chrome ----------
$polBase = "HKLM:\SOFTWARE\Policies\Google\Chrome"
$fcList = Join-Path $polBase "ExtensionInstallForcelist"
# Quitar solo la entrada "1" si corresponde a Imperium; dejar otras politicas intactas
$cur = (Get-ItemProperty $fcList -Name "1" -ErrorAction SilentlyContinue)."1"
if ($cur -like "$ExtensionID*") {
    Remove-ItemProperty $fcList -Name "1" -ErrorAction SilentlyContinue
    Write-Host "  [OK] Quitada ExtensionInstallForcelist[1] (Imperium)" -ForegroundColor Green
}

# ExtensionSettings: quitar solo la clave de Imperium dentro del JSON si es posible
$curSet = (Get-ItemProperty $polBase -Name "ExtensionSettings" -ErrorAction SilentlyContinue).ExtensionSettings
if ($curSet) {
    try {
        $obj = $curSet | ConvertFrom-Json
        if ($obj.PSObject.Properties.Name -contains $ExtensionID) {
            $obj.PSObject.Properties.Remove($ExtensionID)
            if ($obj.PSObject.Properties.Count -gt 0) {
                New-ItemProperty $polBase -Name "ExtensionSettings" -PropertyType String -Value ($obj | ConvertTo-Json -Compress) -Force | Out-Null
            } else {
                Remove-ItemProperty $polBase -Name "ExtensionSettings" -ErrorAction SilentlyContinue
            }
            Write-Host "  [OK] Quitada ExtensionSettings de Imperium" -ForegroundColor Green
        }
    } catch { Write-Host "  [--] ExtensionSettings no modificada (no parseable)" -ForegroundColor DarkGray }
}

# ---------- 2. Quitar hardening incognito/invitado/perfiles (Chrome + Edge) ----------
$hardeningKeys = @(
    "IncognitoModeAvailability",
    "BrowserGuestModeEnabled",
    "BrowserAddPersonEnabled",
    "BrowserProfilePickerAvailability",
    "InPrivateModeAvailability",
    "BrowserAddProfileEnabled",
    "PreventEdgeDownloadEnabled"
)
foreach ($base in @($polBase, "HKLM:\SOFTWARE\Policies\Microsoft\Edge")) {
    foreach ($k in $hardeningKeys) {
        Remove-ItemProperty $base -Name $k -ErrorAction SilentlyContinue
    }
    Write-Host "  [OK] Quitado hardening incognito/invitado/perfiles: $base" -ForegroundColor Green
}

# ---------- 3. Tareas programadas ----------
@("ImperiumOS-HealthCheck","ImperiumOS-Reapply-Boot","ImperiumOS-Reapply-Login","ImperiumOS-ExtensionGuard","ImperiumOS-UpdateServer") | ForEach-Object {
    if (Get-ScheduledTask -TaskName $_ -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $_ -Confirm:$false -ErrorAction SilentlyContinue
        Write-Host "  [OK] Tarea eliminada: $_" -ForegroundColor Green
    }
}

# ---------- 4. Carpeta base + autostart ----------
$BaseDir = Join-Path $env:LOCALAPPDATA "ImperiumOS"
if (Test-Path $BaseDir) {
    Remove-Item $BaseDir -Recurse -Force
    Write-Host "  [OK] Carpeta base eliminada: $BaseDir" -ForegroundColor Green
}
Remove-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "ImperiumSentinel" -ErrorAction SilentlyContinue
Remove-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "ImperiumMonitor" -ErrorAction SilentlyContinue

# ---------- 5. Notas ----------
Write-Host ""
Write-Host "==============================================" -ForegroundColor Yellow
Write-Host "  ROLLBACK COMPLETO" -ForegroundColor Yellow
Write-Host "==============================================" -ForegroundColor Yellow
Write-Host ""
Write-Host "  NOTA: la extension ya instalada en Chrome no se elimina desde aqui." -ForegroundColor DarkGray
Write-Host "  Con la politica retirada, Chrome dejara de tratarla como administrada" -ForegroundColor DarkGray
Write-Host "  y podras desinstalarla desde chrome://extensions si lo deseas." -ForegroundColor DarkGray
Write-Host ""
Read-Host "Presiona ENTER para cerrar"
