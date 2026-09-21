// Búsqueda del POS en el servidor (QA de Eduardo, Sep 21): un producto que no
// está en la lista local de Inventario (páginas no cargadas) aparece igual,
// tecleado o escaneado, porque el panel pregunta a `GET /inventory/products?q=`.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nexus_app/core/theme/app_theme.dart';
import 'package:nexus_app/features/inventory/data/inventory_repository.dart';
import 'package:nexus_app/features/inventory/domain/product.dart';
import 'package:nexus_app/features/inventory/presentation/inventory_provider.dart';
import 'package:nexus_app/features/sales_pos/data/community_catalog_repository.dart';
import 'package:nexus_app/features/sales_pos/presentation/cart_provider.dart';
import 'package:nexus_app/features/sales_pos/presentation/widgets/product_search_results.dart';
import 'package:nexus_app/features/whatsapp_catalog/data/store_orders_repository.dart';
import 'package:nexus_app/features/whatsapp_catalog/domain/store_order.dart';
import 'package:nexus_app/features/whatsapp_catalog/presentation/store_orders_provider.dart';

class MockInventoryRepository extends Mock implements InventoryRepository {}

Product _p(String id, String name, {String? barcode}) => Product(
      id: id,
      name: name,
      sku: id.toUpperCase(),
      barcode: barcode,
      category: 'Bebidas',
      priceMxn: 20,
      costMxn: 12,
      stock: 10,
      reservedStock: 0,
      availableStock: 10,
      isActive: true,
      isOnCatalog: false,
      createdAt: DateTime(2026, 9, 1),
    );

/// Página 1 (lo que Inventario ya cargó) y el catálogo completo del servidor.
final _page1 = [_p('coca', 'Coca-Cola 600ml'), _p('sabritas', 'Sabritas 45g')];
final _server = [..._page1, _p('cocolight', 'Coco Light 355ml', barcode: '7501055300099'), _p('skyrim', 'Skyrim Energy')];

void main() {
  late MockInventoryRepository repo;
  late int serverCalls;

  setUp(() {
    repo = MockInventoryRepository();
    serverCalls = 0;
    when(() => repo.getProducts(
          query: any(named: 'query'),
          category: any(named: 'category'),
          lowStock: any(named: 'lowStock'),
          page: any(named: 'page'),
          pageSize: any(named: 'pageSize'),
        )).thenAnswer((inv) async {
      final q = (inv.namedArguments[#query] as String?)?.toLowerCase().trim();
      if (q == null || q.isEmpty) {
        // Página 1 de Inventario: sólo dos productos.
        return PaginatedProducts(items: _page1, total: 4, page: 1, pageSize: 20, totalPages: 2);
      }
      serverCalls++;
      final items = _server
          .where((p) => p.name.toLowerCase().contains(q) || (p.barcode?.contains(q) ?? false))
          .toList();
      return PaginatedProducts(items: items, total: items.length, page: 1, pageSize: 20, totalPages: 1);
    });
  });

  Widget build(String query) => ProviderScope(
        overrides: [
          orderEventsProvider.overrideWithValue(const Stream<OrderEvent>.empty()),
          storeOrdersRepositoryProvider
              .overrideWithValue(StoreOrdersRepositoryMock(latency: Duration.zero)),
          inventoryRepositoryProvider.overrideWithValue(repo),
          communityCatalogRepositoryProvider
              .overrideWithValue(CommunityCatalogRepositoryMock(delay: Duration.zero)),
        ],
        child: MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(body: ProductSearchResults(query: query, onProductAdded: () {})),
        ),
      );

  testWidgets('un producto fuera de la página local aparece tras consultar al servidor',
      (tester) async {
    await tester.pumpWidget(build('coco'));
    await tester.pump();
    // Antes del debounce: nada local coincide → "buscando", no "sin resultados".
    expect(find.byKey(const Key('posSearchLoading')), findsOneWidget);
    expect(find.textContaining('No encontramos'), findsNothing);

    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(find.text('Coco Light 355ml'), findsOneWidget);
    expect(serverCalls, 1);
  });

  testWidgets('lo local sale al instante y el servidor sólo agrega lo que falta',
      (tester) async {
    await tester.pumpWidget(build('s'));
    await tester.pump();
    // "Sabritas" está en la página local: se muestra sin esperar al servidor.
    expect(find.text('Sabritas 45g'), findsOneWidget);
    expect(find.text('Skyrim Energy'), findsNothing);

    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(find.text('Sabritas 45g'), findsOneWidget); // sin duplicar
    expect(find.text('Skyrim Energy'), findsOneWidget);
  });

  testWidgets('un código escaneado de un producto propio fuera de la página no cae en la comunidad',
      (tester) async {
    await tester.pumpWidget(build('7501055300099'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(find.text('Coco Light 355ml'), findsOneWidget);
    expect(find.byKey(const Key('communitySuggestion')), findsNothing);
  });

  testWidgets('sin coincidencia en ningún lado, "sin resultados" sólo tras responder el servidor',
      (tester) async {
    await tester.pumpWidget(build('zzz'));
    await tester.pump();
    expect(find.byKey(const Key('posSearchLoading')), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('posSearchLoading')), findsNothing);
    expect(find.textContaining('zzz'), findsOneWidget);
  });
}
