/// Dónde vive la vitrina pública — Tarea 13.2 (RF-23).
///
/// El dominio real no está definido en ningún documento del proyecto
/// (`nexus.com/tienda/...` es el ejemplo del Doc. Maestro). Se inyecta en
/// build (`--dart-define=CATALOG_BASE_URL=https://...`) para no tocar código
/// cuando Alan publique el dominio. Pendiente registrado en la bitácora.
const String kCatalogBaseUrl = String.fromEnvironment(
  'CATALOG_BASE_URL',
  defaultValue: 'https://nexus.com/tienda',
  // En QA LAN: --dart-define=CATALOG_BASE_URL=http://<IP>:8000/tienda
  // (la vitrina la sirve el backend en desarrollo, sin `#`).
);

/// `https://nexus.com/tienda/abarrotes-don-pepe`.
String publicCatalogUrl(String slug) => '$kCatalogBaseUrl/$slug';

/// `https://nexus.com/tienda/abarrotes-don-pepe/pedido/P-260914-AB6F?k=…`.
/// La clave (`k`) es la que protege el ticket: el folio solo es adivinable.
String publicOrderUrl(String slug, String folio, {String? key}) =>
    '$kCatalogBaseUrl/$slug/pedido/$folio${key == null ? '' : '?k=$key'}';
