import 'package:flutter_test/flutter_test.dart';
import 'package:hive_test/hive_test.dart';
import 'package:nexus_app/features/inventory/data/inventory_repository.dart';

import '_harness.dart';

/// Fase actual (Sep 2026) — `InventoryRepositoryImpl` cubre los 9 métodos
/// del contrato sin `UnimplementedError`. Este test hace una ida y vuelta
/// real: crear → leer → listar → actualizar → ajustar stock.
void main() {
  late bool backendUp;

  setUpAll(() async {
    await setUpTestHive();
    backendUp = await isBackendUp();
  });

  tearDownAll(() async {
    await tearDownTestHive();
  });

  group('InventoryRepositoryImpl — contra backend real', () {
    test('createProduct → getProductById → getProducts → updateProduct → adjustStock',
        () async {
      if (!backendUp) {
        markTestSkipped('Backend no disponible en $integrationBaseUrl');
        return;
      }

      final session = await signInIntegrationTenant();
      final repo = InventoryRepositoryImpl(client: session.client);

      final uniqueSuffix = DateTime.now().millisecondsSinceEpoch;
      final created = await repo.createProduct(
        name: 'Producto Integración $uniqueSuffix',
        priceMxn: 25.50,
        stock: 10,
        category: 'Abarrotes',
        costMxn: 15.00,
        minStockAlert: 3,
      );

      expect(created.id, isNotEmpty);
      expect(created.priceMxn, 25.50);
      expect(created.stock, 10);

      final fetched = await repo.getProductById(created.id);
      expect(fetched.id, created.id);
      expect(fetched.name, 'Producto Integración $uniqueSuffix');

      final page = await repo.getProducts(
        query: 'Integración $uniqueSuffix',
        pageSize: 20,
      );
      expect(page.items.any((p) => p.id == created.id), isTrue);

      final updated = await repo.updateProduct(
        productId: created.id,
        priceMxn: 30.00,
      );
      expect(updated.priceMxn, 30.00);

      // No debe lanzar — la respuesta es void, la validación real es que
      // el movimiento haya quedado registrado (se comprueba abajo).
      await repo.adjustStock(
        productId: created.id,
        movementType: 'MANUAL_ADJUSTMENT_IN',
        quantity: 5,
        reason: 'Ajuste de prueba de integración',
      );

      final afterAdjust = await repo.getProductById(created.id);
      expect(afterAdjust.stock, 15);

      final movements = await repo.getMovements(productId: created.id);
      expect(movements.items, isNotEmpty);
    });
  });
}
