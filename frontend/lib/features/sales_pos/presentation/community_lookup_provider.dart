import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/community_catalog_repository.dart';
import '../domain/ean_lookup_result.dart';

/// Consulta al motor de dos niveles para un código de barras (Tarea 15.2.1).
///
/// `autoDispose` + `family`: cada código escaneado tiene su propio futuro y
/// se libera al cerrar el panel de resultados. Un fallo de red se convierte
/// en "no encontrado": la red comunitaria nunca bloquea ni ensucia una venta
/// con un banner de error — el cajero simplemente registra el producto a mano.
final eanLookupProvider =
    FutureProvider.autoDispose.family<EanLookupResult, String>((ref, barcode) async {
  final repo = ref.watch(communityCatalogRepositoryProvider);
  try {
    return await repo.lookupEan(barcode);
  } catch (_) {
    return EanLookupResult.notFound(barcode);
  }
});
