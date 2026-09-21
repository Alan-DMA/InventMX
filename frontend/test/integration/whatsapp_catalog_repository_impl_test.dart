import 'package:flutter_test/flutter_test.dart';
import 'package:hive_test/hive_test.dart';
import 'package:nexus_app/core/network/dio_client.dart';
import 'package:nexus_app/core/storage/secure_storage.dart';
import 'package:nexus_app/features/inventory/data/inventory_repository.dart';
import 'package:nexus_app/features/whatsapp_catalog/data/whatsapp_catalog_repository_impl.dart';
import 'package:nexus_app/features/whatsapp_catalog/domain/public_catalog.dart';
import 'package:nexus_app/features/whatsapp_catalog/domain/whatsapp_order.dart';

import '_harness.dart';

/// Catálogo web (Tarea 13.2 ↔ 13.1, Sep 2026) — `WhatsappCatalogRepositoryImpl`
/// contra el backend real: configuración del tendero (con slug), vitrina
/// pública sin sesión, pedido con folio y ticket, y catálogo apagado.
void main() {
  late bool backendUp;

  setUpAll(() async {
    await setUpTestHive();
    backendUp = await isBackendUp();
  });

  tearDownAll(() async {
    await tearDownTestHive();
  });

  /// Cliente **sin** token: así llega el cliente final desde el enlace.
  WhatsappCatalogRepositoryImpl anonymousRepo() =>
      WhatsappCatalogRepositoryImpl(
        client: DioClient(baseUrl: integrationBaseUrl, storage: SecureStorage()),
      );

  group('WhatsappCatalogRepositoryImpl — contra backend real', () {
    test('getSettings trae slug y nombre; updateSettings persiste y borra con vacío',
        () async {
      if (!backendUp) {
        markTestSkipped('Backend no disponible en $integrationBaseUrl');
        return;
      }

      final session = await signInIntegrationTenant();
      final repo = WhatsappCatalogRepositoryImpl(client: session.client);

      final settings = await repo.getSettings();
      expect(settings.slug, integrationTestSlug);
      expect(settings.storeName, 'Tienda de Integración');

      final updated = await repo.updateSettings(
        isCatalogEnabled: true,
        whatsappNumber: '5512345678',
        minOrderAmountMxn: 0,
        deliveryFeeMxn: 15,
        deliveryEnabled: true,
        pickupEnabled: true,
        businessHours: 'L-S 8:00-20:00',
      );
      expect(updated.whatsappNumber, '5512345678');
      expect(updated.deliveryFeeMxn, 15);
      expect(updated.slug, integrationTestSlug);

      // Se guardó de verdad (commit), no sólo en la respuesta del PUT.
      final again = await repo.getSettings();
      expect(again.whatsappNumber, '5512345678');
      expect(again.businessHours, 'L-S 8:00-20:00');

      final cleared = await repo.updateSettings(businessHours: '');
      expect(cleared.businessHours, isNull);
      expect(cleared.whatsappNumber, '5512345678'); // lo no enviado no cambia
    });

    test('vitrina pública sin sesión → vista previa → pedido con folio → ticket',
        () async {
      if (!backendUp) {
        markTestSkipped('Backend no disponible en $integrationBaseUrl');
        return;
      }

      final session = await signInIntegrationTenant();
      final owner = WhatsappCatalogRepositoryImpl(client: session.client);
      await owner.updateSettings(
        isCatalogEnabled: true,
        whatsappNumber: '5512345678',
        minOrderAmountMxn: 0,
        deliveryFeeMxn: 15,
        deliveryEnabled: true,
        pickupEnabled: true,
      );

      final suffix = DateTime.now().millisecondsSinceEpoch;
      final product = await InventoryRepositoryImpl(client: session.client)
          .createProduct(
        name: 'Vitrina $suffix',
        priceMxn: 28.50,
        stock: 12,
        category: 'Lácteos',
        costMxn: 20,
        minStockAlert: 2,
      );

      final public = anonymousRepo();
      final catalog = await public.fetchPublicCatalog(
        integrationTestSlug,
        search: 'Vitrina $suffix',
      );
      expect(catalog.store.slug, integrationTestSlug);
      expect(catalog.store.whatsappNumber, '5512345678');
      expect(catalog.store.deliveryFeeMxn, 15);
      final shown = catalog.products.single;
      expect(shown.id, product.id);
      expect(shown.priceMxn, 28.50);
      expect(shown.inStock, isTrue);
      expect(shown.availableStock, 12);
      expect(shown.categoryName, 'Lácteos');
      // Las categorías con conteo salen del catálogo completo, no del filtro.
      expect(catalog.categories.any((c) => c.name == 'Lácteos'), isTrue);

      final draft = WhatsAppOrderDraft(
        customerName: 'Ana López',
        customerPhone: '5533334444',
        deliveryMethod: DeliveryMethod.delivery,
        deliveryAddress: 'Calle Sol 12, Col. Centro',
        paymentMethod: PaymentMethodPreview.cash,
        cashTenderedMxn: 100,
        orderNotes: 'Tocar el timbre',
        lines: [CartLine(product: shown, quantity: 2, notes: 'bien fría')],
      );

      final preview = await public.buildWhatsAppOrder(integrationTestSlug, draft);
      expect(preview.subtotalMxn, 57.0);
      expect(preview.deliveryFeeMxn, 15.0);
      expect(preview.totalMxn, 72.0);
      expect(preview.changeMxn, 28.0);
      expect(preview.itemCount, 1);
      expect(preview.waLink.host, 'wa.me');
      expect(preview.waLink.path, '/525512345678');

      final order = await public.submitOrder(integrationTestSlug, draft);
      expect(order.folio, startsWith('P-'));
      expect(order.folio.length, 13);
      expect(order.slug, integrationTestSlug);
      expect(order.totals.totalMxn, 72.0);
      expect(order.totals.formattedText, preview.formattedText);
      expect(order.draft.customerName, 'Ana López');
      expect(order.draft.deliveryMethod, DeliveryMethod.delivery);
      expect(order.draft.lines.single.product.name, 'Vitrina $suffix');
      expect(order.draft.lines.single.quantity, 2);
      expect(order.draft.lines.single.notes, 'bien fría');

      // El ticket que abre la tienda desde el chat — también sin sesión.
      expect(order.accessKey, isNotNull);
      // Sin clave (o con otra) el ticket no existe para el público.
      await expectLater(
        public.fetchOrder(integrationTestSlug, order.folio),
        throwsA(isA<OrderNotFound>()),
      );
      final ticket = await public.fetchOrder(integrationTestSlug, order.folio,
          accessKey: order.accessKey);
      // El GET público no devuelve la clave; el resto es idéntico.
      expect(ticket.accessKey, isNull);
      expect(ticket.folio, order.folio);
      expect(ticket.draft, order.draft);
      expect(ticket.totals, order.totals);

      await expectLater(
        public.fetchOrder(integrationTestSlug, 'P-000000-ZZZZ'),
        throwsA(isA<OrderNotFound>()),
      );
    });

    test('reglas de la tienda → OrderRejected con el texto del backend',
        () async {
      if (!backendUp) {
        markTestSkipped('Backend no disponible en $integrationBaseUrl');
        return;
      }

      final session = await signInIntegrationTenant();
      final owner = WhatsappCatalogRepositoryImpl(client: session.client);
      await owner.updateSettings(
        isCatalogEnabled: true,
        minOrderAmountMxn: 500,
        deliveryEnabled: true,
        pickupEnabled: true,
      );
      final product = await InventoryRepositoryImpl(client: session.client)
          .createProduct(
        name: 'Barato ${DateTime.now().millisecondsSinceEpoch}',
        priceMxn: 5,
        stock: 3,
        category: 'Dulces',
        costMxn: 3,
        minStockAlert: 1,
      );
      final catalog = await anonymousRepo().fetchPublicCatalog(
        integrationTestSlug,
        search: product.name,
      );
      final draft = WhatsAppOrderDraft(
        customerName: 'Luis',
        lines: [CartLine(product: catalog.products.single, quantity: 1)],
      );

      await expectLater(
        anonymousRepo().submitOrder(integrationTestSlug, draft),
        throwsA(isA<OrderRejected>().having(
          (e) => e.message,
          'message',
          contains('pedido mínimo'),
        )),
      );

      await owner.updateSettings(minOrderAmountMxn: 0);
    });

    test('catálogo apagado → CatalogDisabled; slug inexistente → StoreNotFound',
        () async {
      if (!backendUp) {
        markTestSkipped('Backend no disponible en $integrationBaseUrl');
        return;
      }

      final session = await signInIntegrationTenant();
      final owner = WhatsappCatalogRepositoryImpl(client: session.client);
      final public = anonymousRepo();

      await owner.updateSettings(isCatalogEnabled: false);
      try {
        await expectLater(
          public.fetchPublicCatalog(integrationTestSlug),
          throwsA(isA<CatalogDisabled>()),
        );
      } finally {
        await owner.updateSettings(isCatalogEnabled: true);
      }

      await expectLater(
        public.fetchPublicCatalog('esta-tienda-no-existe'),
        throwsA(isA<StoreNotFound>()),
      );
    });
  });
}
