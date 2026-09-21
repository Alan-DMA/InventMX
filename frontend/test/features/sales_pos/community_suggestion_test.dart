import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nexus_app/core/theme/app_theme.dart';
import 'package:nexus_app/features/inventory/data/inventory_repository.dart';
import 'package:nexus_app/features/inventory/domain/product.dart';
import 'package:nexus_app/features/sales_pos/data/community_catalog_repository.dart';
import 'package:nexus_app/features/sales_pos/domain/ean_lookup_result.dart';
import 'package:nexus_app/features/sales_pos/presentation/cart_provider.dart';
import 'package:nexus_app/features/sales_pos/presentation/widgets/product_search_results.dart';
import 'package:nexus_app/features/whatsapp_catalog/data/store_orders_repository.dart';
import 'package:nexus_app/features/whatsapp_catalog/domain/store_order.dart';
import 'package:nexus_app/features/whatsapp_catalog/presentation/store_orders_provider.dart';

// ---------------------------------------------------------------------------
// Mocks y fixtures — Tarea 15.2.1 (badge y autocompletado comunitario)
// ---------------------------------------------------------------------------

class MockInventoryRepository extends Mock implements InventoryRepository {}

const _communityBarcode = '7501017001118';
const _seedBarcode = '7501055300075';
const _unknownBarcode = '9999999999999';

Product _makeProduct({
  String id = 'prod-001',
  String name = 'Coca-Cola 600ml',
  String? barcode,
  double priceMxn = 18,
}) {
  return Product(
    id: id,
    sku: 'NEX-B0001',
    barcode: barcode,
    name: name,
    category: 'Bebidas',
    priceMxn: priceMxn,
    costMxn: 0,
    stock: 48,
    reservedStock: 0,
    availableStock: 48,
    isActive: true,
    isOnCatalog: false,
    createdAt: DateTime(2026, 9, 1),
  );
}

void _stubInventory(MockInventoryRepository repo, List<Product> products) {
  when(() => repo.getProducts(
        query: any(named: 'query'),
        category: any(named: 'category'),
        lowStock: any(named: 'lowStock'),
        page: any(named: 'page'),
        pageSize: any(named: 'pageSize'),
      )).thenAnswer((_) async => PaginatedProducts(
        items: products,
        total: products.length,
        page: 1,
        pageSize: 20,
        totalPages: 1,
      ));
  when(() => repo.createProduct(
        name: any(named: 'name'),
        priceMxn: any(named: 'priceMxn'),
        stock: any(named: 'stock'),
        category: any(named: 'category'),
        barcode: any(named: 'barcode'),
        costMxn: any(named: 'costMxn'),
        minStockAlert: any(named: 'minStockAlert'),
        imageUrl: any(named: 'imageUrl'),
      )).thenAnswer((inv) async => _makeProduct(
        id: 'prod-new',
        name: inv.namedArguments[#name] as String,
        barcode: inv.namedArguments[#barcode] as String?,
        priceMxn: inv.namedArguments[#priceMxn] as double,
      ));
}

Widget _build({
  required String query,
  List<Product> products = const [],
  VoidCallback? onProductAdded,
}) {
  final repo = MockInventoryRepository();
  _stubInventory(repo, products);
  return ProviderScope(
    overrides: [
      // Pedidos web (20 sep 2026): el shell abre el canal en vivo; en tests
      // se sustituye por un stream vacío y el repo mock (sin timers ni red).
      orderEventsProvider.overrideWithValue(const Stream<OrderEvent>.empty()),
      storeOrdersRepositoryProvider.overrideWithValue(
            StoreOrdersRepositoryMock(latency: Duration.zero)),
      inventoryRepositoryProvider.overrideWithValue(repo),
      // Delay 0: el reloj falso de los tests no avanza un Future.delayed real.
      communityCatalogRepositoryProvider.overrideWithValue(
        CommunityCatalogRepositoryMock(delay: Duration.zero),
      ),
    ],
    child: MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(
        body: ProductSearchResults(
          query: query,
          onProductAdded: onProductAdded ?? () {},
        ),
      ),
    ),
  );
}

void main() {
  group('looksLikeBarcode', () {
    test('acepta EAN-8, EAN-13 y GTIN-14; rechaza texto y longitudes fuera de rango', () {
      expect(looksLikeBarcode('75010553'), isTrue);
      expect(looksLikeBarcode('7501055300075'), isTrue);
      expect(looksLikeBarcode(' 17501055300075 '), isTrue);
      expect(looksLikeBarcode('coca'), isFalse);
      expect(looksLikeBarcode('1234567'), isFalse);
      expect(looksLikeBarcode('750105530007A'), isFalse);
    });
  });

  group('EanLookupResult.fromJson', () {
    test('mapea el contrato SeedProductLookup', () {
      final r = EanLookupResult.fromJson({
        'barcode': '7501017001118',
        'name': 'Frijoles La Costeña 430g',
        'category': 'Abarrotes',
        'source': 'COMMUNITY_VERIFIED',
        'confidence_score': 4,
      });
      expect(r.source, EanSource.communityVerified);
      expect(r.confidenceScore, 4);
      expect(r.isFound, isTrue);
    });

    test('NOT_FOUND nunca es "encontrado" aunque traiga nombre', () {
      final r = EanLookupResult.fromJson({'barcode': 'x', 'name': 'y', 'source': 'NOT_FOUND'});
      expect(r.isFound, isFalse);
    });
  });

  // ── CA-01: chip comunitario cuando el mock conoce el código ─────────────
  testWidgets('muestra la sugerencia verificada por la comunidad con el conteo de comercios',
      (tester) async {
    await tester.pumpWidget(_build(query: _communityBarcode));
    await tester.pumpAndSettle(); // resuelve el FutureProvider (delay 0)

    expect(find.byKey(const Key('communitySuggestion')), findsOneWidget);
    expect(find.text('Verificado por la comunidad Nexus'), findsOneWidget);
    expect(find.text('Frijoles Negros Refritos La Costeña 430g'), findsOneWidget);
    expect(find.textContaining('5 comercios coinciden'), findsOneWidget);
    expect(find.byKey(const Key('useSuggestionButton')), findsOneWidget);
  });

  testWidgets('distingue el catálogo semilla oficial del consenso comunitario',
      (tester) async {
    await tester.pumpWidget(_build(query: _seedBarcode));
    await tester.pumpAndSettle();

    expect(find.text('Catálogo semilla oficial'), findsOneWidget);
    expect(find.textContaining('comercios coinciden'), findsNothing);
    expect(find.textContaining('código $_seedBarcode'), findsOneWidget);
  });

  // ── CA-01: hint normal cuando no hay coincidencia en ningún catálogo ─────
  testWidgets('código desconocido cae al hint "Sin resultados"', (tester) async {
    await tester.pumpWidget(_build(query: _unknownBarcode));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('communitySuggestion')), findsNothing);
    expect(find.text('Sin resultados para "$_unknownBarcode"'), findsOneWidget);
  });

  testWidgets('texto libre sin coincidencia local no consulta la red', (tester) async {
    await tester.pumpWidget(_build(query: 'frituras caseras'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('communityLookupLoading')), findsNothing);
    expect(find.text('Sin resultados para "frituras caseras"'), findsOneWidget);
  });

  testWidgets('con coincidencia local gana el inventario propio, sin consultar la red',
      (tester) async {
    await tester.pumpWidget(_build(
      query: _communityBarcode,
      products: [_makeProduct(name: 'Frijoles de la casa', barcode: _communityBarcode)],
    ));
    await tester.pumpAndSettle();

    expect(find.text('Frijoles de la casa'), findsOneWidget);
    expect(find.byKey(const Key('communitySuggestion')), findsNothing);
  });

  // ── Regresión: el panel se desmonta mientras el modal está abierto (el
  // buscador del POS pierde el foco al abrirse el modal) y aun así el
  // producto debe llegar al carrito ──────────────────────────────────────────
  testWidgets('agrega al carrito aunque el panel de resultados se cierre con el modal abierto',
      (tester) async {
    final repo = MockInventoryRepository();
    _stubInventory(repo, const []);
    final host = _HostKey();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        // Pedidos web (20 sep 2026): el shell abre el canal en vivo; en tests
        // se sustituye por un stream vacío y el repo mock (sin timers ni red).
        orderEventsProvider.overrideWithValue(const Stream<OrderEvent>.empty()),
        storeOrdersRepositoryProvider.overrideWithValue(
            StoreOrdersRepositoryMock(latency: Duration.zero)),
        inventoryRepositoryProvider.overrideWithValue(repo),
        communityCatalogRepositoryProvider.overrideWithValue(
          CommunityCatalogRepositoryMock(delay: Duration.zero),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.dark,
        home: _ResultsHost(key: host, query: _communityBarcode),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('useSuggestionButton')));
    await tester.pumpAndSettle();

    // Simula el listener de foco del checkout: el panel desaparece.
    host.currentState!.hide();
    await tester.pumpAndSettle();
    expect(find.byType(ProductSearchResults), findsNothing);

    await tester.enterText(find.widgetWithText(TextFormField, '0.00'), '19.00');
    await tester.pump();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Agregar producto'));
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(tester.element(find.byType(Scaffold)));
    final cart = container.read(cartProvider);
    expect(cart.items.single.name, 'Frijoles Negros Refritos La Costeña 430g');
    expect(cart.items.single.unitPriceMxn, 19.00);
  });

  // ── CA-02: "Usar" abre el alta prellenada y, al guardar, el producto va al carrito ──
  testWidgets('usar la sugerencia prellena el alta y agrega el producto al carrito',
      (tester) async {
    var added = false;
    await tester.pumpWidget(_build(
      query: _communityBarcode,
      onProductAdded: () => added = true,
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('useSuggestionButton')));
    await tester.pumpAndSettle();

    // Modal de alta con el nombre sugerido ya escrito
    final nameField = find.widgetWithText(TextFormField, 'Ej: Coca-Cola 600ml');
    expect(tester.widget<TextFormField>(nameField).controller?.text, 'Frijoles Negros Refritos La Costeña 430g');

    // La tienda pone su propio precio — la red nunca lo sugiere
    await tester.enterText(find.widgetWithText(TextFormField, '0.00'), '24.50');
    await tester.pump();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Agregar producto'));
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(ProductSearchResults)),
    );
    final cart = container.read(cartProvider);
    expect(cart.items.single.name, 'Frijoles Negros Refritos La Costeña 430g');
    expect(cart.items.single.unitPriceMxn, 24.50);
    expect(added, isTrue);
  });
}

// ---------------------------------------------------------------------------
// Host que puede ocultar el panel a mitad del flujo (simula la pérdida de
// foco del buscador en CheckoutScreen).
// ---------------------------------------------------------------------------

typedef _HostKey = GlobalKey<_ResultsHostState>;

class _ResultsHost extends StatefulWidget {
  const _ResultsHost({super.key, required this.query});
  final String query;

  @override
  State<_ResultsHost> createState() => _ResultsHostState();
}

class _ResultsHostState extends State<_ResultsHost> {
  bool _visible = true;

  void hide() => setState(() => _visible = false);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _visible
          ? ProductSearchResults(query: widget.query, onProductAdded: () {})
          : const SizedBox.shrink(),
    );
  }
}
