import 'package:flutter_test/flutter_test.dart';
import 'package:hive_test/hive_test.dart';
import 'package:nexus_app/features/inventory/data/inventory_repository.dart';
import 'package:nexus_app/features/sales_pos/data/sales_repository.dart';
import 'package:nexus_app/features/sales_pos/domain/cart_item.dart';
import 'package:nexus_app/features/sales_pos/domain/payment_entry.dart';

import '_harness.dart';

/// Fase actual (Sep 2026) — `SalesRepositoryImpl` sólo tiene `checkout()`
/// implementado; `getSales`, `getSaleById`, `getCashiers` y `refundSale`
/// son `UnimplementedError` a propósito (pendiente de integración real del
/// Kardex — ver bitácora). El provider activo (`salesRepositoryProvider`)
/// sigue en `SalesRepositoryMock`; este test ejercita la clase real
/// directamente, no lo que la UI usa hoy.
void main() {
  late bool backendUp;

  setUpAll(() async {
    await setUpTestHive();
    backendUp = await isBackendUp();
  });

  tearDownAll(() async {
    await tearDownTestHive();
  });

  group('SalesRepositoryImpl — contra backend real', () {
    test('checkout() con un producto real cobra la venta', () async {
      if (!backendUp) {
        markTestSkipped('Backend no disponible en $integrationBaseUrl');
        return;
      }

      final session = await signInIntegrationTenant();
      final inventoryRepo = InventoryRepositoryImpl(client: session.client);
      final salesRepo = SalesRepositoryImpl(client: session.client);
      final warehouseId = await fetchDefaultWarehouseId(session.client);

      final uniqueSuffix = DateTime.now().millisecondsSinceEpoch;
      final product = await inventoryRepo.createProduct(
        name: 'Producto para venta $uniqueSuffix',
        priceMxn: 20.0,
        stock: 10,
        category: 'Abarrotes',
        costMxn: 12.0,
      );

      final result = await salesRepo.checkout(
        items: [
          CartItem(
            id: 'ci-1',
            productId: product.id,
            name: product.name,
            unitPriceMxn: product.priceMxn,
            quantity: 2,
          ),
        ],
        payments: const [
          PaymentEntry(
            id: 'pe-1',
            method: PaymentMethodMxn.cashMxn,
            amountMxn: 40.0,
          ),
        ],
        cashierName: 'Integration Test',
        warehouseId: warehouseId,
      );

      expect(result.saleId, isNotEmpty);
      expect(result.folio, isNotEmpty);
      expect(result.totalMxn, 40.0);
      expect(result.totalPaidMxn, 40.0);
      expect(result.changeGivenMxn, 0.0);
    });

    test(
      'checkout() descuenta el stock del producto vendido',
      () async {
        if (!backendUp) {
          markTestSkipped('Backend no disponible en $integrationBaseUrl');
          return;
        }

        final session = await signInIntegrationTenant();
        final inventoryRepo = InventoryRepositoryImpl(client: session.client);
        final salesRepo = SalesRepositoryImpl(client: session.client);
        final warehouseId = await fetchDefaultWarehouseId(session.client);

        final uniqueSuffix = DateTime.now().millisecondsSinceEpoch;
        final product = await inventoryRepo.createProduct(
          name: 'Producto stock $uniqueSuffix',
          priceMxn: 20.0,
          stock: 10,
          category: 'Abarrotes',
          costMxn: 12.0,
        );

        await salesRepo.checkout(
          items: [
            CartItem(
              id: 'ci-1',
              productId: product.id,
              name: product.name,
              unitPriceMxn: product.priceMxn,
              quantity: 2,
            ),
          ],
          payments: const [
            PaymentEntry(
              id: 'pe-1',
              method: PaymentMethodMxn.cashMxn,
              amountMxn: 40.0,
            ),
          ],
          cashierName: 'Integration Test',
          warehouseId: warehouseId,
        );

        final afterSale = await inventoryRepo.getProductById(product.id);
        expect(afterSale.stock, 8);
      },
      // BUG DE BACKEND confirmado por fuera de este test (curl directo,
      // Sep 2026): `POST /sales/checkout` crea la venta correctamente
      // (folio, totales, ítems) pero no descuenta `product_stock`. No es un
      // problema de mapeo del cliente — el backend nunca toca el stock.
      // Quitar este skip cuando Alan lo corrija.
      skip: 'Bug de backend: checkout no descuenta stock — ver comentario',
    );
  });
}
