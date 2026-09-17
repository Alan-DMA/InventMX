import '../../sales_pos/data/community_catalog_repository.dart';
import 'import_repository.dart';

/// Motor de dos niveles para el escáner (Const. Art. VII 7.5, RF-29):
/// primero el catálogo semilla precargado (Tier 1) y, solo si no hay
/// coincidencia, la red comunitaria (Tier 2, Tarea 15.2).
///
/// Ningún fallo de red bloquea el escaneo: ante error o sin coincidencia
/// devuelve `null` y la tarjeta sale editable para registrar a mano.
Future<EanLookupResult?> lookupEanTwoTier({
  required ImportRepository seed,
  required CommunityCatalogRepository community,
  required String barcode,
}) async {
  try {
    final hit = await seed.lookupEan(barcode);
    if (hit != null) return hit;
  } catch (_) {
    // Tier 1 no disponible: sigue al Tier 2.
  }

  try {
    final hit = await community.lookupEan(barcode);
    if (!hit.isFound) return null;
    return EanLookupResult(
      barcode: hit.barcode,
      name: hit.name!,
      category: hit.category ?? 'General',
      source: hit.source.apiValue,
      confidenceScore: hit.confidenceScore?.toDouble(),
    );
  } catch (_) {
    return null;
  }
}
