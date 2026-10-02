#!/usr/bin/env bash
# Build de la vitrina web en Render (lo llama `render.yaml` → nexus-tienda).
#
# Render no trae Flutter instalado: se descarga la versión fijada en
# FLUTTER_VERSION, se compila la app a web con las URLs de producción
# horneadas (--dart-define) y Render publica `frontend/build/web`.
#
# Se ejecuta desde `frontend/` (rootDir del servicio).
set -euo pipefail

: "${FLUTTER_VERSION:?Falta FLUTTER_VERSION}"
: "${API_URL:?Falta API_URL (https://<tu-api>.onrender.com)}"
: "${CATALOG_BASE_URL:?Falta CATALOG_BASE_URL (https://<tu-vitrina>.onrender.com/tienda)}"

FLUTTER_DIR="$HOME/flutter-$FLUTTER_VERSION"
if [ ! -x "$FLUTTER_DIR/bin/flutter" ]; then
  echo "── Descargando Flutter $FLUTTER_VERSION"
  git clone --depth 1 --branch "$FLUTTER_VERSION" https://github.com/flutter/flutter.git "$FLUTTER_DIR"
fi
export PATH="$FLUTTER_DIR/bin:$PATH"

flutter config --no-analytics >/dev/null
flutter --version
flutter pub get

echo "── Compilando vitrina contra $API_URL"
flutter build web --release \
  --dart-define=API_URL="$API_URL" \
  --dart-define=CATALOG_BASE_URL="$CATALOG_BASE_URL"
