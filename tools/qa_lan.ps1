<#
.SYNOPSIS
  Levanta el entorno de QA en LAN de InvenMX (backend + vitrina web) y deja el
  firewall de Windows listo para que otros dispositivos de la red lleguen al PC.

.DESCRIPTION
  Ejecutar como ADMINISTRADOR (se autoeleva si hace falta):

      powershell -ExecutionPolicy Bypass -File tools\qa_lan.ps1

  Hace, en orden:
    1. Quita las reglas de BLOQUEO de python.exe del firewall (las crea Windows
       cuando se cancela el diálogo "¿Permitir que python.exe se comunique…?";
       ganan sobre cualquier regla de permiso por puerto — causa del "sin
       conexión" del 20 sep 2026).
    2. Marca la red Ethernet como Privada (donde python.exe ya tiene permiso,
       igual que node.exe cuando se trabaja con NestJS).
    3. Abre el puerto 8000 en todos los perfiles.
    4. Arranca el backend en 0.0.0.0:8000 en su propia ventana. El backend
       sirve también la vitrina web (frontend/build/web) con rutas limpias
       (/tienda/...) — un solo proceso, enlaces clicables en WhatsApp.
    5. Imprime las URLs con la IP de LAN del PC.

  Requisitos: Postgres corriendo, migraciones aplicadas, y `flutter build web`
  hecho con CATALOG_BASE_URL=http://<IP>:8000/tienda (ver -BuildWeb).

.PARAMETER BuildWeb
  Recompila la vitrina web antes de servirla (tarda ~2 min).

.PARAMETER NoServers
  Sólo arregla firewall/perfil de red; no arranca nada.

.PARAMETER Ip
  IP de LAN de ESTE PC (la que verán el teléfono y otros dispositivos). Si se
  omite, se toma del adaptador 'Ethernet'; si tampoco existe, cae en la IP de
  la máquina de Eduardo (192.168.50.56) — en otra máquina pásala explícita:

      powershell -ExecutionPolicy Bypass -File tools\qa_lan.ps1 -Ip 192.168.1.20 -BuildWeb

  (`ipconfig` → "Dirección IPv4" del adaptador conectado a la misma red que el
  teléfono). Con -BuildWeb la IP queda horneada en la vitrina web; si cambia,
  hay que recompilar.
#>
param(
    [switch]$BuildWeb,
    [switch]$NoServers,
    [string]$Ip
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot

# ── 0. Autoelevación ─────────────────────────────────────────────────────────
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
           ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "Se necesitan privilegios de administrador (firewall). Pidiendo elevación..." -ForegroundColor Yellow
    $args = @('-ExecutionPolicy', 'Bypass', '-NoExit', '-File', $PSCommandPath)
    if ($BuildWeb)  { $args += '-BuildWeb' }
    if ($NoServers) { $args += '-NoServers' }
    Start-Process powershell -Verb RunAs -ArgumentList $args
    exit
}

# ── 1. Reglas de bloqueo de python.exe ───────────────────────────────────────
$blocks = Get-NetFirewallRule -DisplayName 'python.exe' -ErrorAction SilentlyContinue |
          Where-Object { $_.Action -eq 'Block' }
if ($blocks) {
    $blocks | Remove-NetFirewallRule
    Write-Host "Firewall: eliminadas $(@($blocks).Count) regla(s) de BLOQUEO de python.exe." -ForegroundColor Green
} else {
    Write-Host "Firewall: sin reglas de bloqueo de python.exe." -ForegroundColor Green
}

# ── 2. Red Ethernet como Privada ─────────────────────────────────────────────
$eth = Get-NetConnectionProfile | Where-Object { $_.InterfaceAlias -eq 'Ethernet' } | Select-Object -First 1
if ($eth -and $eth.NetworkCategory -ne 'Private') {
    Set-NetConnectionProfile -InterfaceAlias 'Ethernet' -NetworkCategory Private
    Write-Host "Red 'Ethernet' marcada como Privada." -ForegroundColor Green
}

# ── 3. Puertos ───────────────────────────────────────────────────────────────
foreach ($rule in @(@{ Name = 'Nexus API 8000'; Port = 8000 })) {
    if (-not (Get-NetFirewallRule -DisplayName $rule.Name -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule -DisplayName $rule.Name -Direction Inbound -Protocol TCP `
            -LocalPort $rule.Port -Action Allow -Profile Any | Out-Null
        Write-Host "Firewall: regla '$($rule.Name)' creada." -ForegroundColor Green
    }
}

# ── 4. IP de LAN ─────────────────────────────────────────────────────────────
# Prioridad: -Ip explícita → adaptador 'Ethernet' → IP de la máquina de Eduardo.
# El último caso es un default de conveniencia para su PC: en cualquier otra
# máquina se avisa en rojo, porque los enlaces quedarían apuntando a otro equipo.
if ($Ip) {
    $ip = $Ip
} else {
    $ip = (Get-NetIPAddress -AddressFamily IPv4 -InterfaceAlias 'Ethernet' -ErrorAction SilentlyContinue |
           Where-Object { $_.IPAddress -notlike '169.254.*' } | Select-Object -First 1).IPAddress
}
if (-not $ip) {
    $ip = '192.168.50.56'
    Write-Host "AVISO: no se detectó IP en el adaptador 'Ethernet'; usando $ip (PC de Eduardo)." -ForegroundColor Red
    Write-Host "       Si esta no es tu máquina, vuelve a correr con -Ip <tu IP de LAN> (ver ipconfig)." -ForegroundColor Red
}
Write-Host "IP de LAN usada: $ip" -ForegroundColor Cyan

if ($NoServers) {
    Write-Host "`nListo. Prueba desde el teléfono: http://${ip}:8000/health" -ForegroundColor Cyan
    return
}

# ── 5. Vitrina web (opcional: recompilar) ────────────────────────────────────
$frontend = Join-Path $root 'frontend'
if ($BuildWeb) {
    Write-Host "Compilando la vitrina web para http://${ip}:8000/tienda ..." -ForegroundColor Cyan
    Push-Location $frontend
    flutter build web --release "--dart-define=CATALOG_BASE_URL=http://${ip}:8000/tienda"
    Pop-Location
}
$webDir = Join-Path $frontend 'build\web'
if (-not (Test-Path (Join-Path $webDir 'index.html'))) {
    Write-Host "No existe frontend/build/web — corre con -BuildWeb." -ForegroundColor Red
    return
}

# ── 6. Backend en ventana propia (sobrevive a quien lo lanzó) ─────────────────
$python = Join-Path $root 'backend\.venv\Scripts\python.exe'
$listening = Get-NetTCPConnection -State Listen -LocalPort 8000 -ErrorAction SilentlyContinue
if ($listening) {
    Write-Host "Backend: ya hay algo escuchando en :8000 — no se vuelve a lanzar." -ForegroundColor Yellow
} else {
    Start-Process powershell -ArgumentList '-NoExit', '-Command',
        "Set-Location '$($root)\backend'; & '$python' -m uvicorn app.main:app --host 0.0.0.0 --port 8000"
    Write-Host "Backend lanzado en http://${ip}:8000 (ventana aparte)." -ForegroundColor Green
}
Write-Host ""
Write-Host "Salud del API:      http://${ip}:8000/health" -ForegroundColor Cyan
Write-Host "Catálogo público:   http://${ip}:8000/tienda/tiendita-nexus" -ForegroundColor Cyan
Write-Host "App del Samsung:    ya compilada contra http://${ip}:8000 — sólo ábrela." -ForegroundColor Cyan
