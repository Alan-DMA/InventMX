// QA de Eduardo (Sep 27) sobre Compras:
//  · el buscador de productos del formulario sólo miraba lo cargado en
//    memoria — un producto existente fuera de la primera página no salía;
//  · la tabla de resumen no decía que el nombre se puede cambiar para buscar
//    otro producto;
//  · Dueño y Encargado veían todas las órdenes mezcladas sin poder filtrar
//    por almacén → la leyenda del encabezado cambia el alcance (D28).
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nexus_app/core/network/dio_client.dart';
import 'package:nexus_app/core/theme/app_theme.dart';
import 'package:nexus_app/features/account/presentation/data_scope_provider.dart';
import 'package:nexus_app/features/account/presentation/widgets/warehouse_scope_badge.dart';
import 'package:nexus_app/features/inventory/data/inventory_repository.dart';
import 'package:nexus_app/features/inventory/domain/product.dart';
import 'package:nexus_app/features/inventory/presentation/inventory_provider.dart';
import 'package:nexus_app/features/management/presentation/management_provider.dart'
    show canViewAllWarehousesProvider;
import 'package:nexus_app/features/purchases/data/purchases_repository.dart';
import 'package:nexus_app/features/purchases/domain/purchase_order.dart';
import 'package:nexus_app/features/purchases/presentation/widgets/product_field.dart';
import 'package:nexus_app/features/purchases/presentation/widgets/purchase_items_summary_table.dart';

class _MockInventoryRepository extends Mock implements InventoryRepository {}

class _MockDioClient extends Mock implements DioClient {}

final _cocoLight = Product(
  id: 'prod-coco',
  sku: 'COCO-1',
  name: 'Coco Light 355ml',
  category: 'Bebidas',
  priceMxn: 20,
  costMxn: 12,
  stock: 8,
  reservedStock: 0,
  availableStock: 8,
  isActive: true,
  isOnCatalog: false,
  createdAt: DateTime(2026, 9, 1),
);

PaginatedProducts _page(List<Product> items) => PaginatedProducts(
    items: items, total: items.length, page: 1, pageSize: 20, totalPages: 1);

void main() {
  testWidgets('el buscador de Compras encuentra un producto que no está en memoria',
      (tester) async {
    final inventory = _MockInventoryRepository();
    // La lista cargada de Inventario (sin texto) no lo trae…
    when(() => inventory.getProducts(
          query: null,
          category: any(named: 'category'),
          lowStock: any(named: 'lowStock'),
          page: any(named: 'page'),
          pageSize: any(named: 'pageSize'),
        )).thenAnswer((_) async => _page(const []));
    // …pero el servidor sí lo encuentra al buscarlo.
    when(() => inventory.getProducts(
          query: 'Coco',
          category: any(named: 'category'),
          lowStock: any(named: 'lowStock'),
          page: any(named: 'page'),
          pageSize: any(named: 'pageSize'),
        )).thenAnswer((_) async => _page([_cocoLight]));

    Product? picked;
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    final container = ProviderContainer(
        overrides: [inventoryRepositoryProvider.overrideWithValue(inventory)]);
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: StatefulBuilder(
            builder: (_, setState) => ProductField(
              fieldKey: const Key('field'),
              controller: controller,
              resolved: picked,
              onResolvedChanged: (p) => setState(() => picked = p),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('field')), 'Coco');
    await tester.pump(); // el campo se reconstruye y arranca la búsqueda
    await tester.pump(const Duration(milliseconds: 300)); // debounce
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('productFieldResult_prod-coco')), findsOneWidget);
    await tester.tap(find.byKey(const Key('productFieldResult_prod-coco')));
    await tester.pumpAndSettle();

    expect(picked?.id, 'prod-coco');
    // Queda registrado para quien amarra renglones por id.
    expect(container.read(pickedProductsProvider)['prod-coco'], isNotNull);
  });

  testWidgets('un renglón "Se creará" invita a buscarlo y todos llevan lápiz',
      (tester) async {
    final inventory = _MockInventoryRepository();
    when(() => inventory.getProducts(
          query: any(named: 'query'),
          category: any(named: 'category'),
          lowStock: any(named: 'lowStock'),
          page: any(named: 'page'),
          pageSize: any(named: 'pageSize'),
        )).thenAnswer((_) async => _page(const []));

    await tester.pumpWidget(ProviderScope(
      overrides: [inventoryRepositoryProvider.overrideWithValue(inventory)],
      child: MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: PurchaseItemsSummaryTable(
            lines: const [
              PurchaseDraftLine(
                item: PurchaseOrderItem(
                    productId: 'draft-1',
                    productName: 'Coca Cola 600',
                    quantity: 10,
                    unitCostMxn: 18),
              ),
            ],
            marginPercent: 40,
            onRemove: (_) {},
            onEdit: (_, __) {},
            onResolve: (_, __) {},
            onSalePriceChanged: (_, __) {},
          ),
        ),
      ),
    ));
    await tester.pump();

    expect(find.byKey(const Key('purchaseItemEdit-draft-1')), findsOneWidget);
    expect(find.text('¿Ya existe? Búscalo'), findsOneWidget);

    await tester.tap(find.byKey(const Key('purchaseItemSearch-draft-1')));
    await tester.pumpAndSettle();
    // Abre la edición con el buscador listo.
    expect(find.byKey(const Key('purchaseItemEditName-draft-1')), findsOneWidget);
  });

  group('alcance desde la leyenda (D28)', () {
    Widget app(ProviderContainer container) => UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.dark,
            home: Scaffold(
              appBar: AppBar(
                title: const ScopedAppBarTitle(
                    title: Text('Compras'), switchable: true),
              ),
            ),
          ),
        );

    const warehouses = [
      WarehouseOption(id: 'wh-1', name: 'Almacén Principal', isDefault: true),
      WarehouseOption(id: 'wh-2', name: 'Almacén en Valencia'),
    ];

    testWidgets('quien ve todo arranca en "Todos" y baja a un almacén',
        (tester) async {
      final container = ProviderContainer(overrides: [
        canViewAllWarehousesProvider.overrideWith((ref) => true),
        warehousesProvider.overrideWith((ref) async => warehouses),
      ]);
      addTearDown(container.dispose);
      await tester.pumpWidget(app(container));
      await tester.pumpAndSettle();

      expect(find.text('Todos los almacenes'), findsOneWidget);
      await tester.tap(find.byKey(const Key('warehouseScopeSwitcher')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('scopeOption-wh-2')));
      await tester.pumpAndSettle();

      expect(container.read(dataScopeProvider), 'wh-2');
      expect(find.text('Almacén en Valencia'), findsOneWidget);
    });

    testWidgets('un empleado no tiene conmutador', (tester) async {
      final container = ProviderContainer(overrides: [
        canViewAllWarehousesProvider.overrideWith((ref) => false),
        warehousesProvider.overrideWith((ref) async => warehouses),
      ]);
      addTearDown(container.dispose);
      await tester.pumpWidget(app(container));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('warehouseScopeSwitcher')), findsNothing);
    });
  });

  test('el repositorio de Compras manda el alcance elegido', () async {
    final client = _MockDioClient();
    when(() => client.get<dynamic>(
          any(),
          queryParameters: any(named: 'queryParameters'),
          options: any(named: 'options'),
        )).thenAnswer((_) async => Response(
          data: const [],
          statusCode: 200,
          requestOptions: RequestOptions(),
        ));

    String? scope = 'wh-2';
    final repo = PurchasesRepositoryImpl(client: client, resolveScope: () => scope);
    await repo.listPurchaseOrders();
    final sent = verify(() => client.get<dynamic>(
          '/api/v1/purchase-orders',
          queryParameters: captureAny(named: 'queryParameters'),
          options: any(named: 'options'),
        )).captured.last as Map<String, dynamic>;
    expect(sent['warehouse_id'], 'wh-2');

    scope = null;
    await repo.listPurchaseOrders();
    final all = verify(() => client.get<dynamic>(
          '/api/v1/purchase-orders',
          queryParameters: captureAny(named: 'queryParameters'),
          options: any(named: 'options'),
        )).captured.last as Map<String, dynamic>;
    expect(all.containsKey('warehouse_id'), isFalse);
  });
}
