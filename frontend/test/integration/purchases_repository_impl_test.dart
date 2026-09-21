import 'package:flutter_test/flutter_test.dart';
import 'package:hive_test/hive_test.dart';
import 'package:nexus_app/features/inventory/data/inventory_repository.dart';
import 'package:nexus_app/features/purchases/data/purchases_repository.dart';
import 'package:nexus_app/features/purchases/domain/account_payable.dart';
import 'package:nexus_app/features/purchases/domain/purchase_order.dart';
import 'package:nexus_app/features/purchases/domain/supplier.dart';

import '_harness.dart';

/// `PurchasesRepositoryImpl` contra el backend real de `purchasing_suppliers`
/// (Sep 2026). El provider activo (`purchasesRepositoryProvider`) sigue en
/// `PurchasesRepositoryMock` a propósito: "Nueva orden de compra" todavía
/// captura productos por nombre libre, no por selección real del catálogo,
/// y el backend exige un `product_id` real que sí exista — ver bitácora
/// (docs/architecture/registro_implementacion.md). Este test ejercita la
/// clase real directamente, creando primero un producto real de catálogo
/// (mismo rol que tendría el selector de producto una vez resuelto ese
/// punto), no lo que la UI usa hoy.
void main() {
  late bool backendUp;

  setUpAll(() async {
    await setUpTestHive();
    backendUp = await isBackendUp();
  });

  tearDownAll(() async {
    await tearDownTestHive();
  });

  group('PurchasesRepositoryImpl — contra backend real', () {
    test('ciclo completo: proveedor → producto → orden → recepción → CxP → pago', () async {
      if (!backendUp) {
        markTestSkipped('Backend no disponible en $integrationBaseUrl');
        return;
      }

      final session = await signInIntegrationTenant();
      final purchasesRepo = PurchasesRepositoryImpl(client: session.client);
      final inventoryRepo = InventoryRepositoryImpl(client: session.client);
      final warehouseId = await fetchDefaultWarehouseId(session.client);
      final uniqueSuffix = DateTime.now().millisecondsSinceEpoch;

      // 1. Proveedor — crear, editar, verificar en el listado.
      final supplier = await purchasesRepo.createSupplier(
        name: 'Proveedor Integración $uniqueSuffix',
        phone: '+525500000000',
        creditDays: 15,
      );
      expect(supplier.id, isNotEmpty);
      expect(supplier.creditDays, 15);
      expect(supplier.status, SupplierStatus.active);

      final renamed = await purchasesRepo.updateSupplier(
        id: supplier.id,
        name: 'Proveedor Integración Renombrado $uniqueSuffix',
      );
      expect(renamed.name, 'Proveedor Integración Renombrado $uniqueSuffix');
      expect(renamed.creditDays, 15); // no se tocó — se conserva

      final list = await purchasesRepo.listSuppliers(search: 'Renombrado $uniqueSuffix');
      expect(list.any((s) => s.id == supplier.id), isTrue);

      // 2. Producto real de catálogo — la orden de compra exige un
      // `product_id` que exista de verdad, no un nombre libre.
      final product = await inventoryRepo.createProduct(
        name: 'Producto para compra $uniqueSuffix',
        priceMxn: 25.0,
        stock: 0,
        category: 'Abarrotes',
        costMxn: 15.0,
      );

      // 3. Orden de compra — el backend real la crea ya CONFIRMED.
      final order = await purchasesRepo.createPurchaseOrder(
        supplierId: supplier.id,
        warehouseId: warehouseId,
        items: [
          PurchaseOrderItem(
            productId: product.id,
            productName: product.name,
            quantity: 10,
            unitCostMxn: 15.0,
          ),
        ],
      );
      expect(order.status, PurchaseOrderStatus.confirmed);
      expect(order.totalMxn, 150.0);
      expect(order.items.single.id, isNotNull);

      final ordersList = await purchasesRepo.listPurchaseOrders(search: order.folio);
      expect(ordersList.any((o) => o.id == order.id), isTrue);

      // 4. Recepción total — debe subir a RECEIVED, aumentar stock real y
      // generar una cuenta por pagar nueva.
      final receivedItems = order.items
          .map((i) => i.copyWith(quantityReceived: i.quantity))
          .toList();
      final received = await purchasesRepo.receivePurchaseOrder(
        purchaseOrderId: order.id,
        updatedItems: receivedItems,
      );
      expect(received.status, PurchaseOrderStatus.received);
      expect(received.items.single.quantityReceived, 10);

      final updatedProduct = await inventoryRepo.getProductById(product.id);
      expect(updatedProduct.stock, 10);

      // 5. Cuenta por pagar generada por la recepción.
      final payablesResult = await purchasesRepo.listAccountsPayable();
      final payable = payablesResult.items.firstWhere(
        (p) => p.purchaseOrderId == order.id,
        orElse: () => throw StateError('No se generó CxP para la orden ${order.id}'),
      );
      expect(payable.originalAmountMxn, 150.0);
      expect(payable.status, AccountPayableStatus.pending);

      // 6. Abono parcial y verificación del saldo restante.
      final afterPayment = await purchasesRepo.payAccountPayable(
        accountPayableId: payable.id,
        amountPaidMxn: 50.0,
        paymentMethod: SupplierPaymentMethod.cashMxn,
      );
      expect(afterPayment.paidAmountMxn, 50.0);
      expect(afterPayment.balanceMxn, 100.0);
      expect(afterPayment.status, AccountPayableStatus.partiallyPaid);

      // 7. Recibir una segunda vez sin unidades pendientes nuevas debe
      // rechazarse (mismo delta, no hay nada nuevo que recepcionar).
      expect(
        () => purchasesRepo.receivePurchaseOrder(
          purchaseOrderId: order.id,
          updatedItems: receivedItems,
        ),
        throwsA(isA<PurchasesException>()),
      );
    }, timeout: const Timeout(Duration(seconds: 30)));

    // NOTA (Sep 2026): el mock rechaza con 422 si el proveedor tiene órdenes
    // activas (SENT/CONFIRMED/PARTIALLY_RECEIVED) — el backend real
    // (`purchasing_service.py::deactivate_supplier`) no implementa esa
    // validación todavía, desactiva sin condición. `PurchasesRepositoryImpl.
    // deactivateSupplier()` ya sabe mapear un 422 a
    // `SupplierHasActiveOrdersException` si el backend algún día lo agrega;
    // por ahora este test documenta el comportamiento real, no el deseado.
    // Ver nota para Alan en `integrations.md`.
    test('deactivateSupplier con el backend real de hoy: desactiva sin validar órdenes activas',
        () async {
      if (!backendUp) {
        markTestSkipped('Backend no disponible en $integrationBaseUrl');
        return;
      }

      final session = await signInIntegrationTenant();
      final purchasesRepo = PurchasesRepositoryImpl(client: session.client);
      final inventoryRepo = InventoryRepositoryImpl(client: session.client);
      final warehouseId = await fetchDefaultWarehouseId(session.client);
      final uniqueSuffix = DateTime.now().millisecondsSinceEpoch;

      final supplier = await purchasesRepo.createSupplier(
        name: 'Proveedor Con Orden $uniqueSuffix',
      );
      final product = await inventoryRepo.createProduct(
        name: 'Producto orden activa $uniqueSuffix',
        priceMxn: 10.0,
        stock: 0,
      );
      await purchasesRepo.createPurchaseOrder(
        supplierId: supplier.id,
        warehouseId: warehouseId,
        items: [
          PurchaseOrderItem(productId: product.id, productName: product.name, quantity: 1, unitCostMxn: 10.0),
        ],
      );

      await purchasesRepo.deactivateSupplier(supplier.id);
      final list = await purchasesRepo.listSuppliers(search: 'Con Orden $uniqueSuffix');
      expect(list.firstWhere((s) => s.id == supplier.id).status, SupplierStatus.inactive);
    }, timeout: const Timeout(Duration(seconds: 30)));
  });
}
