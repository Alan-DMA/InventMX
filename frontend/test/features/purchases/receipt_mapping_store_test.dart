import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_app/features/purchases/data/receipt_mapping_store.dart';
import 'package:nexus_app/features/purchases/domain/receipt_scan.dart';

void main() {
  group('normalizeSupplier', () {
    test('mayúsculas, sin acentos ni puntuación, espacios simples', () {
      expect(
        normalizeSupplier('  Distribuidora  Bimbo   Norte. '),
        'DISTRIBUIDORA BIMBO NORTE',
      );
      expect(normalizeSupplier('Panificación Ángel, S.A.'),
          'PANIFICACION ANGEL S A');
    });

    test('dos lecturas distintas del mismo proveedor dan la misma clave', () {
      expect(
        normalizeSupplier('DISTRIBUIDORA BIMBO NORTE'),
        normalizeSupplier('distribuidora bimbo norte'),
      );
    });
  });

  group('ReceiptColumnMapping', () {
    test('sobrevive el viaje por mapa (Hive guarda mapas dinámicos)', () {
      const mapping = ReceiptColumnMapping(
        nameCol: 1,
        quantityCol: 2,
        priceCol: 3,
        subtotalCol: 6,
      );
      expect(ReceiptColumnMapping.fromMap(mapping.toMap()), mapping);
    });

    test('fitsColumnCount rechaza índices fuera de la tabla', () {
      const mapping =
          ReceiptColumnMapping(nameCol: 1, quantityCol: 2, priceCol: 6);
      expect(mapping.fitsColumnCount(7), isTrue);
      expect(mapping.fitsColumnCount(4), isFalse);
    });
  });
}
