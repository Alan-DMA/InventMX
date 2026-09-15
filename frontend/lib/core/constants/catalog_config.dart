/// Dónde vive la vitrina pública — Tarea 13.2 (RF-23).
///
/// El dominio real no está definido en ningún documento del proyecto
/// (`nexus.com/tienda/...` es el ejemplo del Doc. Maestro). Se inyecta en
/// build (`--dart-define=CATALOG_BASE_URL=https://...`) para no tocar código
/// cuando Alan publique el dominio. Pendiente registrado en la bitácora.
const String kCatalogBaseUrl = String.fromEnvironment(
  'CATALOG_BASE_URL',
  defaultValue: 'https://nexus.com/tienda',
);

/// `https://nexus.com/tienda/abarrotes-don-pepe`.
String publicCatalogUrl(String slug) => '$kCatalogBaseUrl/$slug';

/// `https://nexus.com/tienda/abarrotes-don-pepe/pedido/P-260914-AB6F`.
String publicOrderUrl(String slug, String folio) =>
    '$kCatalogBaseUrl/$slug/pedido/$folio';
