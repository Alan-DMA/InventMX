import 'package:hive_flutter/hive_flutter.dart';

import '../domain/receipt_scan.dart';

/// Recuerda qué columna es cada dato en la factura de cada proveedor.
///
/// Bimbo siempre trae la misma tabla: una vez confirmado el mapeo, el
/// siguiente escaneo abre con él preseleccionado y basta un toque. Se guarda
/// SOLO cuando el OCR detectó proveedor — sin proveedor no hay clave, y
/// pedirle al usuario que lo nombre es una tarea aparte (fuera del MVP).
abstract interface class ReceiptMappingStore {
  Future<ReceiptColumnMapping?> load(String supplier);
  Future<void> save(String supplier, ReceiptColumnMapping mapping);
}

/// Hive con mapa dinámico, mismo patrón que `OnboardingRepositoryHive` —
/// sin generación de código, sin backend (Alan, Tarea 12.1 pendiente).
class ReceiptMappingStoreHive implements ReceiptMappingStore {
  static const _boxName = 'nexus_receipt_mappings';

  Future<Box> get _box async => Hive.isBoxOpen(_boxName)
      ? Hive.box(_boxName)
      : await Hive.openBox(_boxName);

  @override
  Future<ReceiptColumnMapping?> load(String supplier) async {
    final raw = (await _box).get(normalizeSupplier(supplier));
    return raw == null ? null : ReceiptColumnMapping.fromMap(raw as Map);
  }

  @override
  Future<void> save(String supplier, ReceiptColumnMapping mapping) async {
    await (await _box).put(normalizeSupplier(supplier), mapping.toMap());
  }
}

/// "Distribuidora Bimbo Norte" y "DISTRIBUIDORA BIMBO NORTE." deben ser el
/// mismo proveedor: mayúsculas, sin acentos ni puntuación, espacios simples.
String normalizeSupplier(String supplier) {
  const accents = 'ÁÉÍÓÚÜÑáéíóúüñ';
  const plain = 'AEIOUUNaeiouun';
  final buffer = StringBuffer();
  for (final rune in supplier.runes) {
    final ch = String.fromCharCode(rune);
    final i = accents.indexOf(ch);
    buffer.write(i >= 0 ? plain[i] : ch);
  }
  return buffer
      .toString()
      .toUpperCase()
      .replaceAll(RegExp(r'[^A-Z0-9 ]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
