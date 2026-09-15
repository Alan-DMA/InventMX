import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_app/features/inventory/domain/product.dart';
import 'package:nexus_app/features/whatsapp_catalog/data/whatsapp_catalog_repository.dart';
import 'package:nexus_app/features/whatsapp_catalog/domain/catalog_settings.dart';
import 'package:nexus_app/features/whatsapp_catalog/domain/public_catalog.dart';
import 'package:nexus_app/features/whatsapp_catalog/domain/whatsapp_order.dart';

Product _product(
  String id,
  String name, {
  String category = 'Abarrotes',
  double price = 10,
  int stock = 5,
  bool active = true,
  bool onCatalog = true,
}) =>
    Product(
      id: id,
      sku: id.toUpperCase(),
      name: name,
      category: category,
      priceMxn: price,
      costMxn: price / 2,
      stock: stock,
      reservedStock: 0,
      availableStock: stock,
      isActive: active,
      isOnCatalog: onCatalog,
      createdAt: DateTime(2026, 9, 1),
    );

final _products = [
  _product('coca', 'Coca-Cola 600ml', category: 'Bebidas', price: 18),
  _product('pan', 'Pan Bimbo Grande', category: 'Panadería', price: 52),
  _product('sab', 'Sabritas 45g', category: 'Botanas', price: 17, stock: 0),
  _product('oculto', 'Cigarros', onCatalog: false),
  _product('inactivo', 'Producto viejo', active: false),
];

WhatsappCatalogRepositoryMock _repo({String? number = '+52 55 1234 5678'}) =>
    WhatsappCatalogRepositoryMock(
      storeName: 'Abarrotes Don Pepe',
      products: _products,
      latency: Duration.zero,
      whatsappNumber: number,
    );

void main() {
  group('slugify', () {
    test('minúsculas, sin acentos, guiones', () {
      expect(slugify('Abarrotes Don Pepe'), 'abarrotes-don-pepe');
      expect(slugify('La Esperanza  S.A. de C.V.'), 'la-esperanza-s-a-de-c-v');
      expect(slugify('Tiendita Ñoño & Cía'), 'tiendita-nono-cia');
      expect(slugify('  --hola--  '), 'hola');
    });
  });

  group('WhatsappCatalogRepositoryMock.fetchPublicCatalog', () {
    test(
        'solo productos activos y en catálogo; agotados visibles pero '
        'no disponibles', () async {
      final catalog = await _repo().fetchPublicCatalog('abarrotes-don-pepe');

      expect(catalog.store.name, 'Abarrotes Don Pepe');
      expect(catalog.store.slug, 'abarrotes-don-pepe');
      expect(catalog.products.map((p) => p.name),
          ['Coca-Cola 600ml', 'Pan Bimbo Grande', 'Sabritas 45g']);
      expect(catalog.products.last.inStock, isFalse);
      expect(catalog.totalProducts, 3);
    });

    test('categorías con conteo, ordenadas por nombre', () async {
      final catalog = await _repo().fetchPublicCatalog('abarrotes-don-pepe');

      expect(catalog.categories.map((c) => c.name),
          ['Bebidas', 'Botanas', 'Panadería']);
      expect(catalog.categories.first.id, 'bebidas');
      expect(catalog.categories.first.productCount, 1);
    });

    test('búsqueda y categoría filtran sin tocar las categorías', () async {
      final repo = _repo();
      final byName =
          await repo.fetchPublicCatalog('abarrotes-don-pepe', search: 'coca');
      expect(byName.products.single.name, 'Coca-Cola 600ml');
      expect(byName.categories, hasLength(3));

      final byCategory = await repo.fetchPublicCatalog('abarrotes-don-pepe',
          categoryId: 'panaderia');
      expect(byCategory.products.single.name, 'Pan Bimbo Grande');
    });

    test('slug desconocido → StoreNotFound', () {
      expect(
        () => _repo().fetchPublicCatalog('otra-tienda'),
        throwsA(isA<StoreNotFound>()),
      );
    });

    test('catálogo apagado → CatalogDisabled con el nombre', () async {
      final repo = _repo();
      await repo.updateSettings(isCatalogEnabled: false);

      expect(
        () => repo.fetchPublicCatalog('abarrotes-don-pepe'),
        throwsA(isA<CatalogDisabled>()
            .having((e) => e.storeName, 'storeName', 'Abarrotes Don Pepe')),
      );
    });
  });

  group('WhatsappCatalogRepositoryMock — pedido y configuración', () {
    test('buildWhatsAppOrder arma el enlace con el número de la tienda',
        () async {
      final repo = _repo();
      final catalog = await repo.fetchPublicCatalog('abarrotes-don-pepe');
      final build = await repo.buildWhatsAppOrder(
        'abarrotes-don-pepe',
        WhatsAppOrderDraft(
          customerName: 'Ana',
          lines: [CartLine(product: catalog.products.first, quantity: 3)],
        ),
      );

      expect(build.waLink.path, '/525512345678');
      expect(build.totalMxn, 54);
    });

    test('getSettings / updateSettings persisten en memoria', () async {
      final repo = _repo(number: null);
      final before = await repo.getSettings();
      expect(before.hasWhatsappNumber, isFalse);
      expect(before.isCatalogEnabled, isTrue);

      await repo.updateSettings(whatsappNumber: '+52 33 0000 1111');
      final after = await repo.updateSettings(isCatalogEnabled: false);

      expect(after.whatsappNumber, '+52 33 0000 1111');
      expect(after.isCatalogEnabled, isFalse);
      expect((await repo.getSettings()), after);
    });

    test('la vitrina refleja el número recién guardado', () async {
      final repo = _repo(number: null);
      await repo.updateSettings(whatsappNumber: '+52 33 0000 1111');
      final catalog = await repo.fetchPublicCatalog('abarrotes-don-pepe');

      expect(catalog.store.canReceiveOrders, isTrue);
      expect(catalog.store.whatsappNumber, '+52 33 0000 1111');
    });
  });

  group('WhatsappCatalogRepositoryMock — pedidos registrados', () {
    test('submitOrder asigna folio y fetchOrder lo devuelve', () async {
      final repo = WhatsappCatalogRepositoryMock(
        storeName: 'Abarrotes Don Pepe',
        products: _products,
        latency: Duration.zero,
        now: () => DateTime(2026, 9, 14, 12),
      );
      final catalog = await repo.fetchPublicCatalog('abarrotes-don-pepe');
      final draft = WhatsAppOrderDraft(
        customerName: 'Ana',
        lines: [CartLine(product: catalog.products.first, quantity: 3)],
      );

      final saved = await repo.submitOrder('abarrotes-don-pepe', draft);
      expect(saved.folio, startsWith('P-260914-'));
      expect(saved.totals.totalMxn, 54);
      expect(saved.itemCount, 3);

      final fetched = await repo.fetchOrder('abarrotes-don-pepe', saved.folio);
      expect(fetched, saved);
    });

    test('submitOrder aplica las reglas de la tienda', () async {
      final repo = _repo();
      final catalog = await repo.fetchPublicCatalog('abarrotes-don-pepe');
      final draft = WhatsAppOrderDraft(
        customerName: 'Ana',
        lines: [CartLine(product: catalog.products.first, quantity: 1)],
      );

      expect(() => repo.submitOrder('abarrotes-don-pepe', draft),
          throwsA(isA<OrderRejected>()));
    });

    test('folio desconocido → OrderNotFound; slug ajeno → StoreNotFound',
        () async {
      final repo = _repo();
      expect(() => repo.fetchOrder('abarrotes-don-pepe', 'P-000000-0000'),
          throwsA(isA<OrderNotFound>()));
      expect(() => repo.fetchOrder('otra', 'P-000000-0000'),
          throwsA(isA<StoreNotFound>()));
    });
  });
}
