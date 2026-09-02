# ============================================================
#  IMPERIUM OS - INSTALLER PORTABLE (Chrome Web Store)
#  v32.0
#  Arquitectura: install force_installed via Windows Registry Policy
#  Requiere: Windows 10/11, Chrome instalado, privilegios Admin
#  NO usa servidor local, NO rutas locales del dev, NO .crx/.pem,
#  NO --load-extension, NO ACL deny-delete, NO guard en loop.
#  Idempotente: ejecutable varias veces sin duplicar/corromper.
# ============================================================

# ---------- Config (ajustable) ----------
$ExtensionID  = "ajilohlkmkjipipjagpnokhinhbjfkfb"
$UpdateURL    = "https://clients2.google.com/service/update2/crx"
$BaseDir      = Join-Path $env:LOCALAPPDATA "ImperiumOS"
$LogPath      = Join-Path $BaseDir "install.log"
# Hardening Windows opcionales (fáciles de apagar)
$ApplyFastUserSwitch = $true
$ApplyWidgets        = $true
$ApplyStoreEdge      = $true

# ---------- Auto-elevation ----------
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Se requieren permisos de administrador. Elevando..." -ForegroundColor Yellow
    Start-Process powershell -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    exit
}

$ErrorActionPreference = "SilentlyContinue"

function Log($m) {
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$ts] $m"
    if (-not (Test-Path $BaseDir)) { New-Item -ItemType Directory -Path $BaseDir -Force | Out-Null }
    $line | Out-File -FilePath $LogPath -Append -Encoding utf8
}
function Write-Ok($m)  { Write-Host "        $m" -ForegroundColor Green;  Log "OK  $m" }
function Write-Wr($m) { Write-Host "        $m" -ForegroundColor Yellow; Log "WARN $m" }
function Write-Err($m){ Write-Host "        $m" -ForegroundColor Red;   Log "ERR  $m" }
function Write-Step($n,$t){ Write-Host ""; Write-Host "   [$n] $t" -ForegroundColor Cyan }

Log "=== IMPERIUM INSTALL (portable) START ==="

# ============================================================
# FASE 0 - COMPROBACIONES
# ============================================================
Write-Step "00/07" "Comprobaciones"

# 0.1 Detectar Chrome
$chromeExe = $null
$chromePaths = @(
    "C:\Program Files\Google\Chrome\Application\chrome.exe",
    "C:\Program Files (x86)\Google\Chrome\Application\chrome.exe",
    (Join-Path $env:LOCALAPPDATA "Google\Chrome\Application\chrome.exe")
)
foreach ($p in $chromePaths) { if (Test-Path $p) { $chromeExe = $p; break } }
if (-not $chromeExe) {
    $appPath = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\chrome.exe" -ErrorAction SilentlyContinue).'(default)'
    if ($appPath -and (Test-Path $appPath)) { $chromeExe = $appPath }
}
if (-not $chromeExe) {
    Write-Err "Chrome no detectado. Instala Google Chrome primero."
    Write-Err "Requisitos: Windows 10/11 + Chrome + permisos Admin."
    Read-Host "Presiona ENTER para cerrar"
    exit 1
}
Write-Ok "Chrome detectado: $chromeExe"

# 0.2 Crear carpeta base
if (-not (Test-Path $BaseDir)) { New-Item -ItemType Directory -Path $BaseDir -Force | Out-Null }
Write-Ok "Carpeta base: $BaseDir"

# ============================================================
# FASE 1 - INSTALAR EXTENSION FORZADA (SOLO CHROME)
# ============================================================
Write-Step "01/07" "Instalar extension forzada en Chrome"
$polBase = "HKLM:\SOFTWARE\Policies\Google\Chrome"

# Crear base de politicas si falta
if (-not (Test-Path $polBase)) { New-Item -Path $polBase -Force | Out-Null }

# 1.1 ExtensionInstallForcelist -> valor "1"
$fcList = Join-Path $polBase "ExtensionInstallForcelist"
if (-not (Test-Path $fcList)) { New-Item -Path $fcList -Force | Out-Null }
$expectedForcelist = "$ExtensionID;$UpdateURL"
$currentForcelist = (Get-ItemProperty $fcList -Name "1" -ErrorAction SilentlyContinue)."1"
if ($currentForcelist -ne $expectedForcelist) {
    New-ItemProperty $fcList -Name "1" -PropertyType String -Value $expectedForcelist -Force | Out-Null
    Log "Set Forcelist[1] = $expectedForcelist"
}
Write-Ok "ExtensionInstallForcelist = $ExtensionID;...update2/crx"

# 1.2 ExtensionSettings -> installation_mode force_installed
$settingsJson = '{"' + $ExtensionID + '":{"installation_mode":"force_installed","update_url":"' + $UpdateURL + '"}}'
$currentSettings = (Get-ItemProperty $polBase -Name "ExtensionSettings" -ErrorAction SilentlyContinue).ExtensionSettings
if ($currentSettings -ne $settingsJson) {
    New-ItemProperty $polBase -Name "ExtensionSettings" -PropertyType String -Value $settingsJson -Force | Out-Null
    Log "Set ExtensionSettings = $settingsJson"
}
Write-Ok "ExtensionSettings = force_installed (no desinstalable/deshabilitable)"

# 1.3 Limpiar bloqueo si existe (ExtensionInstallBlocklist podria bloquearla)
$blk = Join-Path $polBase "ExtensionInstallBlocklist"
if (Test-Path $blk) { Remove-Item $blk -Recurse -Force; Log "Removed ExtensionInstallBlocklist" }
Remove-ItemProperty $polBase -Name "ExtensionInstallBlocklist" -ErrorAction SilentlyContinue

# ============================================================
# FASE 2 - HARDENING INCOGNITO/INVITADO/PERFILES (CHROME + EDGE)
# ============================================================
Write-Step "02/07" "Hardening incognito/invitado/perfiles (Chrome + Edge)"

$privatePolicies = @{
    "IncognitoModeAvailability"       = 1   # Chrome; Edge: bloquea InPrivate
    "BrowserGuestModeEnabled"         = 0   # bloquea modo invitado
    "BrowserAddPersonEnabled"         = 0   # no anadir personas/cuentas
    "BrowserProfilePickerAvailability"= 1   # sin selector de perfiles
}
$edgeExtra = @{
    "InPrivateModeAvailability"       = 1   # Edge refuerzo
    "BrowserAddProfileEnabled"        = 0   # Edge no crear perfiles
    "PreventEdgeDownloadEnabled"      = 1   # Edge bloquear descarga/reinstalacion
}

# --- Chrome ---
foreach ($k in $privatePolicies.Keys) {
    New-ItemProperty $polBase -Name $k -PropertyType DWord -Value $privatePolicies[$k] -Force | Out-Null
}
Write-Ok "Chrome: incognito/invitado/perfiles bloqueados"

# --- Edge ---
$edgeBase = "HKLM:\SOFTWARE\Policies\Microsoft\Edge"
if (-not (Test-Path $edgeBase)) { New-Item -Path $edgeBase -Force | Out-Null }
foreach ($k in $privatePolicies.Keys) {
    New-ItemProperty $edgeBase -Name $k -PropertyType DWord -Value $privatePolicies[$k] -Force | Out-Null
}
foreach ($k in $edgeExtra.Keys) {
    New-ItemProperty $edgeBase -Name $k -PropertyType DWord -Value $edgeExtra[$k] -Force | Out-Null
}
Write-Ok "Edge: incognito/invitado/perfiles bloqueados"

# ============================================================
# FASE 3 - HARDENING WINDOWS (configurable)
# ============================================================
Write-Step "03/07" "Hardening Windows"

if ($ApplyFastUserSwitch) {
    New-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name "DisableFastUserSwitching" -PropertyType DWord -Value 1 -Force | Out-Null
    New-Item -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" -Force | Out-Null
    New-ItemProperty "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" -Name "HideFastUserSwitching" -PropertyType DWord -Value 1 -Force | Out-Null
    Write-Ok "Fast User Switching desactivado"
}

if ($ApplyWidgets) {
    New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Dsh" -Force | Out-Null
    New-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Dsh" -Name "AllowNewsAndInterests" -PropertyType DWord -Value 0 -Force | Out-Null
    New-Item -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Force | Out-Null
    New-ItemProperty "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "TaskbarDa" -PropertyType DWord -Value 0 -Force | Out-Null
    New-ItemProperty "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "EnableWidgets" -PropertyType DWord -Value 0 -Force | Out-Null
    Write-Ok "Widgets eliminados de la barra de tareas"
}

if ($ApplyStoreEdge) {
    New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\WindowsStore" -Force | Out-Null
    New-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\WindowsStore" -Name "RemoveWindowsStoreCapability" -PropertyType DWord -Value 1 -Force | Out-Null
    Write-Ok "Microsoft Store deshabilitado"
}

# ============================================================
# FASE 4 - REPARACION ADMIN EXPLICITA (no loop, no pelea con admin)
# ============================================================
Write-Step "04/07" "Reparacion administrativa explicita"

# Guard: detective NO destructivo. Detecta si la politica sigue y registra estado.
$guardScript = Join-Path $BaseDir "imperium_guard.ps1"
$guardBody = @"
# IMPERIUM OS - GUARD (detective, no pelea con el admin)
$ErrorActionPreference = "SilentlyContinue"
`$ExtID = "$ExtensionID"
`$Pol = "HKLM:\SOFTWARE\Policies\Google\Chrome"
`$Fc = Join-Path `$Pol "ExtensionInstallForcelist"
`$Log = Join-Path "$BaseDir" "guard.log"
`$val = (Get-ItemProperty `$Fc -Name "1" -ErrorAction SilentlyContinue)."1"
if (`$val -like "`$ExtID*") {
    "[`$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] OK politica presente" | Out-File `$Log -Append
} else {
    "[`$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] POLITICA FALTANTE - ejecuta el reparador" | Out-File `$Log -Append
}
"@
$guardBody | Out-File -FilePath $guardScript -Encoding utf8
Write-Ok "Guard creado: registra estado (no re-aplica en loop)"

# Reparador: script que el admin ejecuta para re-aplicar (reutiliza este mismo instalador)
# Se crea un acces directo/script "reparar" que llama de nuevo a este instalador.
$repairLink = Join-Path $BaseDir "REPARAR_IMPERIUM.ps1"
$repairBody = "Start-Process powershell -Verb RunAs -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"'"
$repairBody | Out-File -FilePath $repairLink -Encoding utf8
Write-Ok "Reparador creado: $repairLink"

# Tarea programada: ejecuta el GUARD (detecta) al arranque. No re-aplica.
$taskName = "ImperiumOS-HealthCheck"
if (-not (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue)) {
    $a = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$guardScript`""
    $t = New-ScheduledTaskTrigger -AtStartup
    $p = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
    Register-ScheduledTask -TaskName $taskName -Action $a -Trigger $t -Principal $p -Force | Out-Null
    Log "Scheduled task $taskName created (detect only)"
}
Write-Ok "Health-check programado al arranque (solo detecta)"

# ============================================================
# FASE 5 - VERIFICACION
# ============================================================
Write-Step "05/07" "Verificacion"

$fcCheck = (Get-ItemProperty $fcList -Name "1" -ErrorAction SilentlyContinue)."1"
$setCheck = (Get-ItemProperty $polBase -Name "ExtensionSettings" -ErrorAction SilentlyContinue).ExtensionSettings

$allOk = $true
if ($fcCheck -ne $expectedForcelist) { $allOk = $false; Write-Err "Forcelist no coincide" }
if ($setCheck -ne $settingsJson)     { $allOk = $false; Write-Err "ExtensionSettings no coincide" }
if ($allOk) { Write-Ok "Politicas de extension escritas y verificadas" } else { Write-Err "Revisar politicas en chrome://policy" }

# ============================================================
# FASE 6 - RESUMEN Y ACCIONES
# ============================================================
Write-Step "06/07" "Final"
Write-Host ""
Write-Host "==============================================" -ForegroundColor Green
Write-Host "  IMPERIUM OS INSTALADO" -ForegroundColor Green
Write-Host "  Extension: force_installed (Chrome)" -ForegroundColor Green
Write-Host "  Incognito/Invitado/Perfiles: bloqueado (Chrome+Edge)" -ForegroundColor Green
if ($ApplyFastUserSwitch) { Write-Host "  Fast User Switch: desactivado" -ForegroundColor Green }
if ($ApplyWidgets)        { Write-Host "  Widgets: eliminados" -ForegroundColor Green }
if ($ApplyStoreEdge)      { Write-Host "  Microsoft Store: deshabilitado" -ForegroundColor Green }
Write-Host "==============================================" -ForegroundColor Green
Write-Host ""
Write-Host "  REQUISITOS cumplidos: Windows 10/11 + Chrome + Admin" -ForegroundColor DarkGray
Write-Host ""

# Abrir chrome://policy y chrome://extensions para verificacion visual
if ($chromeExe) {
    try {
        Start-Process $chromeExe -ArgumentList "chrome://policy"
        Start-Sleep -Milliseconds 800
        Start-Process $chromeExe -ArgumentList "chrome://extensions"
    } catch {}
}

Write-Host "  CHECKLIST (verifica manualmente):" -ForegroundColor Cyan
Write-Host "  1. chrome://extensions -> Imperium OS -> 'Instalado por el administrador'" -ForegroundColor White
Write-Host "  2. NO aparece la opcion 'Eliminar extension'" -ForegroundColor White
Write-Host "  3. NO puede deshabilitarse desde Chrome" -ForegroundColor White
Write-Host "  4. Reinicia Chrome y luego Windows para confirmar persistencia" -ForegroundColor White
Write-Host "  5. Si la politica se pierde, ejecuta: REPARAR_IMPERIUM.ps1 (en $BaseDir)" -ForegroundColor Yellow
Write-Host ""

Log "=== IMPERIUM INSTALL (portable) DONE: allOk=$allOk ==="
Read-Host "Presiona ENTER para cerrar"
exit $(if ($allOk) { 0 } else { 1 })
