<#
.SYNOPSIS
  Compila el APK de la tienda de prueba apuntando al servidor desplegado.

.DESCRIPTION
  La app no lee la URL del servidor en tiempo de ejecución: se "hornea" al
  compilar con --dart-define. Este script junta en un solo lugar todos los
  valores de producción para no olvidar ninguno:

      powershell -ExecutionPolicy Bypass -File tools\build_apk_prueba.ps1 `
          -ApiUrl https://nexus-api.onrender.com `
          -CatalogUrl https://nexus-tienda.onrender.com/tienda

  El APK queda en frontend\build\app\outputs\flutter-apk\app-release.apk.
  Se instala copiándolo al teléfono (instalación de "orígenes desconocidos");
  va firmado con la llave de depuración, válido para prueba, no para Play.

  Si cambia la URL del servidor, hay que recompilar.

.PARAMETER ApiUrl
  URL pública del API en Render, sin "/" final.

.PARAMETER CatalogUrl
  URL de la vitrina web + "/tienda" (los enlaces que se comparten por WhatsApp).
#>
param(
    [Parameter(Mandatory = $true)][string]$ApiUrl,
    [Parameter(Mandatory = $true)][string]$CatalogUrl
)

$ErrorActionPreference = 'Stop'
$frontend = Join-Path (Split-Path -Parent $PSScriptRoot) 'frontend'

$ApiUrl = $ApiUrl.TrimEnd('/')
$CatalogUrl = $CatalogUrl.TrimEnd('/')
if (-not $ApiUrl.StartsWith('https://')) {
    throw "ApiUrl debe ser https:// (Android bloquea HTTP sin cifrar fuera de la red local)."
}

Write-Host "Comprobando que el servidor responde en $ApiUrl/health ..." -ForegroundColor Cyan
Write-Host "(si Render estaba dormido puede tardar ~1 min)" -ForegroundColor DarkGray
try {
    $health = Invoke-RestMethod "$ApiUrl/health" -TimeoutSec 90
    Write-Host "  servidor: $($health.status) · base de datos: $($health.database)" -ForegroundColor Green
} catch {
    Write-Warning "El servidor no respondió. El APK se compila igual, pero revisa el deploy antes de instalarlo."
}

Push-Location $frontend
try {
    flutter build apk --release `
        "--dart-define=API_URL=$ApiUrl" `
        "--dart-define=CATALOG_BASE_URL=$CatalogUrl"
    if ($LASTEXITCODE -ne 0) { throw "flutter build apk falló ($LASTEXITCODE)." }
} finally {
    Pop-Location
}

$apk = Join-Path $frontend 'build\app\outputs\flutter-apk\app-release.apk'
Write-Host "`nAPK listo: $apk" -ForegroundColor Green
