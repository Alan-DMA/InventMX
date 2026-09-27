// Tope de existencias en el carrito del POS (QA de Eduardo, Sep 26): antes
// se podía cargar un producto sin stock, o 6 de algo que tiene 3, y el cajero
// se enteraba hasta darle a Cobrar. Decisiones: bloquear con aviso al
// agregar, sin stock visible pero no agregable, y el pedido web se carga tal
// cual y se marca el renglón que excede.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nexus_app/core/theme/app_theme.dart';
import 'package:nexus_app/features/inventory/data/inventory_repository.dart';
import 'package:nexus_app/features/inventory/domain/product.dart';
import 'package:nexus_app/features/inventory/presentation/inventory_provider.dart';
import 'package:nexus_app/features/sales_pos/domain/cart_item.dart';
import 'package:nexus_app/features/sales_pos/presentation/cart_provider.dart';
import 'package:nexus_app/features/sales_pos/presentation/widgets/cart_item_tile.dart';

import '../whatsapp_catalog/store_order_fixtures.dart';

class MockInventoryRepository extends Mock implements InventoryRepository {}

Product _product({String id = 'p-1', String name = 'Coca-Cola 600ml', int stock = 3}) =>
    Product(
      id: id,
      sku: 'NEX-1',
      name: name,
      category: 'Bebidas',
      priceMxn: 18,
      costMxn: 12,
      stock: stock,
      reservedStock: 0,
      availableStock: stock,
      isActive: true,
      isOnCatalog: false,
      createdAt: DateTime(2026, 9, 1),
    );

ProviderContainer _container({MockInventoryRepository? inventory}) {
  final container = ProviderContainer(overrides: [
    // Sin almacenes reales: el aviso sale sin "en <almacén>".
    warehousesProvider.overrideWith((ref) async => const []),
    if (inventory != null) inventoryRepositoryProvider.overrideWithValue(inventory),
  ]);
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('agregar respeta las existencias de mi almacén', () {
    test('dentro del tope se agrega y recuerda el máximo', () {
      final container = _container();
      final notifier = container.read(cartProvider.notifier);

      expect(notifier.addProduct(_product()), isNull);
      expect(notifier.addProduct(_product(), qty: 2), isNull);

      final item = container.read(cartProvider).items.single;
      expect(item.quantity, 3);
      expect(item.maxQuantity, 3);
      expect(item.atStockLimit, isTrue);
    });

    test('pasarse no agrega y avisa en ese momento (no al cobrar)', () {
      final container = _container();
      final notifier = container.read(cartProvider.notifier);
      notifier.addProduct(_product(), qty: 3);

      expect(notifier.addProduct(_product()), 'Solo hay 3 de Coca-Cola 600ml.');
      expect(container.read(cartProvider).items.single.quantity, 3);

      expect(notifier.addProduct(_product(id: 'p-2', name: 'Otra'), qty: 6),
          isNotNull);
    });

    test('sin existencias no se agrega', () {
      final container = _container();
      final notice = container
          .read(cartProvider.notifier)
          .addProduct(_product(stock: 0));
      expect(notice, 'No hay existencias de Coca-Cola 600ml.');
      expect(container.read(cartProvider).isEmpty, isTrue);
    });

    test('+ en el tope avisa y no suma', () {
      final container = _container();
      final notifier = container.read(cartProvider.notifier);
      notifier.addProduct(_product(), qty: 3);
      final id = container.read(cartProvider).items.single.id;

      expect(notifier.increment(id), isNotNull);
      expect(container.read(cartProvider).items.single.quantity, 3);
    });

    test('la venta al vuelo no tiene tope', () {
      final container = _container();
      final notifier = container.read(cartProvider.notifier);
      notifier.addOnTheFly(name: 'Hielo', priceMxn: 30, qty: 50);
      final item = container.read(cartProvider).items.single;
      expect(item.maxQuantity, isNull);
      expect(notifier.increment(item.id), isNull);
      expect(container.read(cartProvider).items.single.quantity, 51);
    });
  });

  group('pedido web cobrado en caja', () {
    test('se carga lo pactado y se marca el renglón que excede; no se cobra',
        () async {
      final inventory = MockInventoryRepository();
      // El pedido de Laura pide 3 Coca-Colas; en mi almacén hay 2.
      when(() => inventory.getProductById('prod-001'))
          .thenAnswer((_) async => _product(id: 'prod-001', stock: 2));
      final container = _container(inventory: inventory);

      container.read(cartProvider.notifier).loadFromStoreOrder(lauraOrder());
      await Future<void>.delayed(Duration.zero);

      final cart = container.read(cartProvider);
      expect(cart.items.single.quantity, 3, reason: 'no se recorta en silencio');
      expect(cart.items.single.maxQuantity, 2);
      expect(cart.stockConflicts, hasLength(1));

      await expectLater(
        container.read(cartProvider.notifier).checkout(payments: const []),
        throwsA(predicate((e) => e.toString().contains('Solo hay 2'))),
      );
    });
  });

  testWidgets('el renglón muestra "máx. N" en el tope y rojo si excede',
      (tester) async {
    Future<void> pump(CartItem item) => tester.pumpWidget(ProviderScope(
          child: MaterialApp(
            theme: AppTheme.dark,
            home: Scaffold(body: CartItemTile(item: item)),
          ),
        ));

    await pump(const CartItem(
        id: 'c-1', productId: 'p-1', name: 'Coca', unitPriceMxn: 18, quantity: 3, maxQuantity: 3));
    expect(find.text('máx. 3'), findsOneWidget);
    expect(find.byKey(const Key('cartItemStockConflict')), findsNothing);

    await pump(const CartItem(
        id: 'c-1', productId: 'p-1', name: 'Coca', unitPriceMxn: 18, quantity: 3, maxQuantity: 2));
    expect(find.text('Solo hay 2 · ajusta'), findsOneWidget);
  });
}
