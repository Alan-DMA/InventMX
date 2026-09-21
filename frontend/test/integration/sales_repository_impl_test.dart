import 'package:flutter_test/flutter_test.dart';
import 'package:hive_test/hive_test.dart';
import 'package:nexus_app/features/inventory/data/inventory_repository.dart';
import 'package:nexus_app/features/sales_pos/data/sales_repository.dart';
import 'package:nexus_app/features/sales_pos/domain/cart_item.dart';
import 'package:nexus_app/features/sales_pos/domain/cart_state.dart';
import 'package:nexus_app/features/sales_pos/domain/payment_entry.dart';

import '_harness.dart';

/// Fase actual (Sep 2026) — `SalesRepositoryImpl` cubre los 5 métodos del
/// contrato (checkout, getSales, getSaleById, getCashiers, refundSale) sin
/// `UnimplementedError`. El provider activo (`salesRepositoryProvider`)
/// sigue en `SalesRepositoryMock` a propósito — ver bitácora
/// (docs/architecture/integrations.md, pendiente #2): `cash_session_
/// provider.dart` y los repos de analytics/comisiones siguen leyendo
/// `SalesRepositoryMock.todaysSales` directo, así que voltear el provider
/// hoy dejaría esas pantallas sin datos del día. Este test ejercita la
/// clase real directamente, no lo que la UI usa hoy.
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
      // Bug real de backend (Sep 2026, ver docs/architecture/integrations.md):
      // no era que `checkout()` no descontara el stock — es que `SalesService`
      // nunca llamaba `session.commit()` (a diferencia de todos los demás
      // servicios del backend), así que TODA la transacción de la venta se
      // revertía al cerrarse la sesión de la petición. Corregido agregando
      // el commit explícito en checkout/cancel/pago/reembolso.
    );

    test('getSaleById() trae el detalle completo de la venta cobrada', () async {
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
        name: 'Producto detalle $uniqueSuffix',
        priceMxn: 25.0,
        stock: 10,
        category: 'Abarrotes',
        costMxn: 15.0,
      );

      final result = await salesRepo.checkout(
        items: [
          CartItem(
            id: 'ci-1',
            productId: product.id,
            name: product.name,
            unitPriceMxn: product.priceMxn,
            quantity: 3,
          ),
        ],
        payments: const [
          PaymentEntry(
            id: 'pe-1',
            method: PaymentMethodMxn.cashMxn,
            amountMxn: 75.0,
          ),
        ],
        cashierName: 'Integration Test',
        warehouseId: warehouseId,
      );

      final detail = await salesRepo.getSaleById(result.saleId);
      expect(detail.saleId, result.saleId);
      expect(detail.folio, result.folio);
      expect(detail.totalMxn, 75.0);
      expect(detail.items, hasLength(1));
      expect(detail.items.single.name, product.name);
      expect(detail.items.single.quantity, 3);
      expect(detail.cashierName, isNotEmpty);
      expect(detail.isRefunded, isFalse);
    });

    test('getSaleById() con un id inexistente lanza SaleNotFoundException',
        () async {
      if (!backendUp) {
        markTestSkipped('Backend no disponible en $integrationBaseUrl');
        return;
      }

      final session = await signInIntegrationTenant();
      final salesRepo = SalesRepositoryImpl(client: session.client);

      expect(
        () => salesRepo.getSaleById('00000000-0000-0000-0000-000000000000'),
        throwsA(isA<SaleNotFoundException>()),
      );
    });

    test('getSales() lista la venta recién cobrada con el total en el header',
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
        name: 'Producto listado $uniqueSuffix',
        priceMxn: 12.0,
        stock: 10,
        category: 'Abarrotes',
        costMxn: 7.0,
      );

      final result = await salesRepo.checkout(
        items: [
          CartItem(
            id: 'ci-1',
            productId: product.id,
            name: product.name,
            unitPriceMxn: product.priceMxn,
            quantity: 1,
          ),
        ],
        payments: const [
          PaymentEntry(
            id: 'pe-1',
            method: PaymentMethodMxn.cashMxn,
            amountMxn: 12.0,
          ),
        ],
        cashierName: 'Integration Test',
        warehouseId: warehouseId,
      );

      final page = await salesRepo.getSales(page: 1, pageSize: 50);
      expect(page.total, greaterThanOrEqualTo(1));
      expect(page.items.any((s) => s.id == result.saleId), isTrue);
    });

    test('getCashiers() incluye al usuario de la sesión de integración',
        () async {
      if (!backendUp) {
        markTestSkipped('Backend no disponible en $integrationBaseUrl');
        return;
      }

      final session = await signInIntegrationTenant();
      final salesRepo = SalesRepositoryImpl(client: session.client);

      final cashiers = await salesRepo.getCashiers();
      expect(cashiers, contains('Integration Test'));
    });

    test(
        'refundSale() total repone el ciclo de la venta a REFUNDED y un segundo intento falla',
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
        name: 'Producto reembolso $uniqueSuffix',
        priceMxn: 30.0,
        stock: 10,
        category: 'Abarrotes',
        costMxn: 18.0,
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
            amountMxn: 60.0,
          ),
        ],
        cashierName: 'Integration Test',
        warehouseId: warehouseId,
      );

      final refunded = await salesRepo.refundSale(
        saleId: result.saleId,
        reason: 'Cliente devolvió el producto completo',
        refundToStock: true,
      );

      expect(refunded.isRefunded, isTrue);
      expect(refunded.refund!.refundAmountMxn, 60.0);
      expect(refunded.refund!.reason, 'Cliente devolvió el producto completo');

      // Un segundo reembolso sobre la misma venta ya cerrada -> 422 real,
      // mapeado a la excepción de dominio (réplica del contrato mock).
      expect(
        () => salesRepo.refundSale(
          saleId: result.saleId,
          reason: 'Segundo intento',
          refundToStock: true,
        ),
        throwsA(isA<SaleAlreadyRefundedException>()),
      );

      // NOTA: no se verifica la reposición de stock aquí — depende del mismo
      // bug de backend documentado arriba (`checkout()` no descuenta stock),
      // así que "reponer" sobre un stock que nunca bajó no es una aserción
      // significativa. Cubierto sin ese bug en el test unitario del backend
      // (`test_refund_sale_total_reverses_stock_and_closes_cycle`).
    });

    test('refundSale() parcial por renglón reembolsa sólo la cantidad pedida',
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
        name: 'Producto reembolso parcial $uniqueSuffix',
        priceMxn: 10.0,
        stock: 10,
        category: 'Abarrotes',
        costMxn: 6.0,
      );

      final result = await salesRepo.checkout(
        items: [
          CartItem(
            id: 'ci-1',
            productId: product.id,
            name: product.name,
            unitPriceMxn: product.priceMxn,
            quantity: 4,
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

      final detail = await salesRepo.getSaleById(result.saleId);
      final serverItemId = detail.items.single.id;

      final refunded = await salesRepo.refundSale(
        saleId: result.saleId,
        reason: '2 piezas defectuosas',
        refundToStock: false,
        itemsToRefund: [
          RefundedLine(cartItemId: serverItemId, quantity: 2),
        ],
      );

      expect(refunded.isRefunded, isTrue);
      expect(refunded.refund!.refundAmountMxn, 20.0);
      expect(refunded.refund!.lines.single.quantity, 2);
    });
  });
}
