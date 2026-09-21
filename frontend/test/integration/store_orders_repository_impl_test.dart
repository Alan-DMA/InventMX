import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_test/hive_test.dart';
import 'package:nexus_app/core/network/dio_client.dart';
import 'package:nexus_app/core/storage/secure_storage.dart';
import 'package:nexus_app/features/inventory/data/inventory_repository.dart';
import 'package:nexus_app/features/sales_pos/data/sales_repository.dart';
import 'package:nexus_app/features/sales_pos/domain/cart_item.dart';
import 'package:nexus_app/features/sales_pos/domain/payment_entry.dart';
import 'package:nexus_app/features/whatsapp_catalog/data/order_events_channel.dart';
import 'package:nexus_app/features/whatsapp_catalog/data/store_orders_repository.dart';
import 'package:nexus_app/features/whatsapp_catalog/data/whatsapp_catalog_repository_impl.dart';
import 'package:nexus_app/features/whatsapp_catalog/domain/store_order.dart';
import 'package:nexus_app/features/whatsapp_catalog/domain/whatsapp_order.dart';

import '_harness.dart';

/// Pedidos web del tendero (plan del 20 sep 2026) — ciclo completo contra el
/// backend vivo: vitrina anónima → WebSocket avisa → abrir (visto) → Listo →
/// editar con historial → cobrar en caja (venta real, stock baja) → Entregado
/// con venta ligada → el ticket público lo refleja. Más: 409 y cancelación.
void main() {
  late bool backendUp;

  setUpAll(() async {
    await setUpTestHive();
    backendUp = await isBackendUp();
  });

  tearDownAll(() async {
    await tearDownTestHive();
  });

  WhatsappCatalogRepositoryImpl anonymousCatalog() =>
      WhatsappCatalogRepositoryImpl(
        client: DioClient(baseUrl: integrationBaseUrl, storage: SecureStorage()),
      );

  group('StoreOrdersRepositoryImpl + WS — contra backend real', () {
    test('ciclo completo: WS → visto → Listo → editar → cobrar → Entregado',
        () async {
      if (!backendUp) {
        markTestSkipped('Backend no disponible en $integrationBaseUrl');
        return;
      }

      final session = await signInIntegrationTenant();
      final orders = StoreOrdersRepositoryImpl(client: session.client);
      final inventory = InventoryRepositoryImpl(client: session.client);
      final sales = SalesRepositoryImpl(client: session.client);
      final owner = WhatsappCatalogRepositoryImpl(client: session.client);
      await owner.updateSettings(
        isCatalogEnabled: true,
        whatsappNumber: '5512345678',
        minOrderAmountMxn: 0,
        deliveryFeeMxn: 15,
        deliveryEnabled: true,
        pickupEnabled: true,
      );

      // 1. Canal en vivo abierto antes de que llegue el pedido.
      final channel = OrderEventsChannel(
        apiBaseUrl: integrationBaseUrl,
        readToken: session.storage.readAccessToken,
      );
      final received = <OrderEvent>[];
      final firstNew = Completer<StoreOrder>();
      final sub = channel.events().listen((e) {
        received.add(e);
        if (e.type == OrderEventType.newOrder && !firstNew.isCompleted) {
          firstNew.complete(e.order!);
        }
      });
      addTearDown(sub.cancel);
      // Esperar el hello (conexión aceptada).
      await Future<void>.delayed(const Duration(milliseconds: 800));
      expect(received.any((e) => e.type == OrderEventType.hello), isTrue,
          reason: 'el WS debería saludar al conectar');

      // 2. Un cliente anónimo pide desde la vitrina.
      final suffix = DateTime.now().millisecondsSinceEpoch;
      final product = await inventory.createProduct(
        name: 'Pedido web $suffix',
        priceMxn: 30,
        stock: 10,
        category: 'Abarrotes',
        costMxn: 20,
        minStockAlert: 1,
      );
      final catalog = await anonymousCatalog()
          .fetchPublicCatalog(integrationTestSlug, search: 'Pedido web $suffix');
      final shown = catalog.products.single;
      final submitted = await anonymousCatalog().submitOrder(
        integrationTestSlug,
        WhatsAppOrderDraft(
          customerName: 'Cliente WS',
          customerPhone: '5533334444',
          deliveryMethod: DeliveryMethod.pickup,
          cashTenderedMxn: 100,
          lines: [CartLine(product: shown, quantity: 2)],
        ),
      );

      // 3. El aviso llega por el socket en < 2 s, con el pedido completo.
      final pushed = await firstNew.future.timeout(const Duration(seconds: 2));
      expect(pushed.folio, submitted.folio);
      expect(pushed.status, OrderStatus.newOrder);
      expect(pushed.isSeen, isFalse);
      expect(pushed.order.totals.totalMxn, 60);

      // 4. Lista con badge del servidor.
      final list = await orders.list();
      expect(list.items.any((o) => o.folio == submitted.folio), isTrue);
      expect(list.newCount, greaterThanOrEqualTo(1));

      // 5. Abrirlo lo marca visto (y avisa por el socket).
      final opened = await orders.get(submitted.folio);
      expect(opened.isSeen, isTrue);
      expect(opened.seenByName, 'Integration Test');
      final after = await orders.list(scope: 'all');
      expect(
        after.items.firstWhere((o) => o.folio == submitted.folio).isSeen,
        isTrue,
      );

      // 6. Listo (con versión) y 409 con versión vieja.
      final ready = await orders.updateStatus(
        submitted.folio,
        status: OrderStatus.ready,
        expectedUpdatedAt: opened.order.updatedAt,
      );
      expect(ready.status, OrderStatus.ready);
      await expectLater(
        orders.updateStatus(
          submitted.folio,
          status: OrderStatus.delivered,
          expectedUpdatedAt: opened.order.updatedAt,
        ),
        throwsA(isA<OrderConflict>()),
      );

      // 7. Editar: 3 piezas a domicilio; la versión anterior se conserva.
      final edited = await orders.edit(
        submitted.folio,
        StoreOrderEdit(
          lines: [CartLine(product: shown, quantity: 3, notes: 'bolsa aparte')],
          deliveryMethod: DeliveryMethod.delivery,
          deliveryAddress: 'Calle Sol 12, Centro',
          orderNotes: 'Cambió por chat',
          expectedUpdatedAt: ready.order.updatedAt,
        ),
      );
      expect(edited.order.totals.subtotalMxn, 90);
      expect(edited.order.totals.deliveryFeeMxn, 15);
      expect(edited.order.totals.totalMxn, 105);
      expect(edited.order.totals.changeMxn, isNull); // ya no alcanza con $100
      expect(edited.order.storeEditedAt, isNotNull);
      expect(edited.revisions.single.totalMxn, 60);
      expect(edited.revisions.single.lines.single.quantity, 2);

      // 8. Cobrar en caja: venta real con el carrito del pedido → stock baja.
      final warehouseId = await fetchDefaultWarehouseId(session.client);
      final sale = await sales.checkout(
        items: [
          for (final line in edited.order.draft.lines)
            CartItem(
              id: 'ci-${line.product.id}',
              productId: line.product.id,
              name: line.product.name,
              unitPriceMxn: line.product.priceMxn,
              quantity: line.quantity,
            ),
        ],
        payments: const [
          PaymentEntry(id: 'pe-1', method: PaymentMethodMxn.cashMxn, amountMxn: 105),
        ],
        cashierName: 'Integration Test',
        warehouseId: warehouseId,
      );
      final delivered = await orders.updateStatus(
        submitted.folio,
        status: OrderStatus.delivered,
        saleId: sale.saleId,
      );
      expect(delivered.status, OrderStatus.delivered);
      expect(delivered.saleId, sale.saleId);
      expect(delivered.canReopen, isFalse);
      expect((await inventory.getProductById(product.id)).availableStock, 7);

      // Cobrado en caja: no se reabre desde aquí.
      await expectLater(
        orders.updateStatus(submitted.folio, status: OrderStatus.newOrder),
        throwsA(isA<OrderActionRejected>()),
      );

      // 9. El ticket público (sin sesión) refleja estado y edición.
      final ticket =
          await anonymousCatalog().fetchOrder(integrationTestSlug, submitted.folio,
              accessKey: submitted.accessKey);
      expect(ticket.status, OrderStatus.delivered);
      expect(ticket.storeEditedAt, isNotNull);
      expect(ticket.totals.totalMxn, 105);

      // 10. Todos los cambios avisaron por el socket.
      await Future<void>.delayed(const Duration(milliseconds: 300));
      final updates = received
          .where((e) => e.type == OrderEventType.updated && e.order?.folio == submitted.folio)
          .map((e) => e.order!.status)
          .toList();
      expect(updates, contains(OrderStatus.ready));
      expect(updates.last, OrderStatus.delivered);
    });

    test('cancelar con motivo, reabrir y el historial', () async {
      if (!backendUp) {
        markTestSkipped('Backend no disponible en $integrationBaseUrl');
        return;
      }
      final session = await signInIntegrationTenant();
      final orders = StoreOrdersRepositoryImpl(client: session.client);
      final inventory = InventoryRepositoryImpl(client: session.client);
      final product = await inventory.createProduct(
        name: 'Cancelable ${DateTime.now().millisecondsSinceEpoch}',
        priceMxn: 12,
        stock: 5,
        category: 'Dulces',
        costMxn: 8,
        minStockAlert: 1,
      );
      final catalog = await anonymousCatalog()
          .fetchPublicCatalog(integrationTestSlug, search: product.name);
      final submitted = await anonymousCatalog().submitOrder(
        integrationTestSlug,
        WhatsAppOrderDraft(
          customerName: 'Se arrepintió',
          lines: [CartLine(product: catalog.products.single, quantity: 1)],
        ),
      );

      await expectLater(
        orders.updateStatus(submitted.folio, status: OrderStatus.cancelled),
        throwsA(isA<OrderActionRejected>()),
      );
      final cancelled = await orders.updateStatus(
        submitted.folio,
        status: OrderStatus.cancelled,
        cancelReason: CancelReason.customerCancelled,
      );
      expect(cancelled.order.cancelReason, CancelReason.customerCancelled);

      final history = await orders.list(scope: 'history');
      expect(history.items.any((o) => o.folio == submitted.folio), isTrue);
      final active = await orders.list(scope: 'active');
      expect(active.items.any((o) => o.folio == submitted.folio), isFalse);

      final reopened =
          await orders.updateStatus(submitted.folio, status: OrderStatus.newOrder);
      expect(reopened.status, OrderStatus.newOrder);
      expect(reopened.order.cancelReason, isNull);

      await expectLater(
        orders.get('P-000000-ZZZZ'),
        throwsA(isA<OrderNotFound>()),
      );
    });
  });
}
