import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nexus_app/core/theme/app_theme.dart';
import 'package:nexus_app/features/inventory/data/inventory_repository.dart';
import 'package:nexus_app/features/inventory/domain/product.dart';
import 'package:nexus_app/features/inventory/presentation/inventory_provider.dart';
import 'package:nexus_app/features/inventory/presentation/product_detail_screen.dart';
import 'package:nexus_app/features/inventory/presentation/widgets/action_grid.dart';
import 'package:nexus_app/features/inventory/presentation/widgets/stock_card.dart';

// ---------------------------------------------------------------------------
// Mock
// ---------------------------------------------------------------------------

class MockInventoryRepository extends Mock implements InventoryRepository {}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Product _makeProduct({
  String id = 'prod-001',
  String name = 'Coca-Cola 600ml',
  String sku = 'NEX-B0001',
  String? barcode = '7501055300018',
  double priceMxn = 18.00,
  double costMxn = 11.50,
  int availableStock = 48,
  int reservedStock = 2,
  int? minStockAlert = 10,
  String category = 'Bebidas',
}) {
  return Product(
    id: id,
    sku: sku,
    barcode: barcode,
    name: name,
    category: category,
    priceMxn: priceMxn,
    costMxn: costMxn,
    stock: availableStock + reservedStock,
    reservedStock: reservedStock,
    availableStock: availableStock,
    minStockAlert: minStockAlert,
    isActive: true,
    isOnCatalog: true,
    createdAt: DateTime(2026, 9, 1),
  );
}

/// Construye el widget en modo standalone (sin GoRouter) —
/// suficiente para tests de la pantalla de detalle.
Widget _buildWidget(
  Product product, {
  MockInventoryRepository? mockRepo,
}) {
  final repo = mockRepo ?? MockInventoryRepository();

  // Stub por si el provider cae en el fallback de getProductById
  when(() => repo.getProductById(any())).thenAnswer((_) async => product);
  when(
    () => repo.getProducts(
      query: any(named: 'query'),
      category: any(named: 'category'),
      lowStock: any(named: 'lowStock'),
      page: any(named: 'page'),
      pageSize: any(named: 'pageSize'),
    ),
  ).thenAnswer((_) async => PaginatedProducts(
        items: [product],
        total: 1,
        page: 1,
        pageSize: 20,
        totalPages: 1,
      ));

  return ProviderScope(
    overrides: [
      inventoryRepositoryProvider.overrideWithValue(repo),
      // Precarga el producto en el provider de detalle para que
      // el test no dependa del delay del mock del repositorio.
      productDetailProvider(product.id).overrideWith(
        (ref) async => product,
      ),
    ],
    child: MaterialApp(
      theme: AppTheme.dark,
      home: ProductDetailScreen(productId: product.id),
    ),
  );
}

/// Construye el widget en estado de error.
Widget _buildErrorWidget(String productId) {
  final repo = MockInventoryRepository();
  when(() => repo.getProductById(any())).thenThrow(Exception('Sin conexión'));
  when(
    () => repo.getProducts(
      query: any(named: 'query'),
      category: any(named: 'category'),
      lowStock: any(named: 'lowStock'),
      page: any(named: 'page'),
      pageSize: any(named: 'pageSize'),
    ),
  ).thenThrow(Exception('Sin conexión'));

  return ProviderScope(
    overrides: [
      inventoryRepositoryProvider.overrideWithValue(repo),
      productDetailProvider(productId).overrideWith(
        (ref) async => throw Exception('Sin conexión'),
      ),
    ],
    child: MaterialApp(
      theme: AppTheme.dark,
      home: ProductDetailScreen(productId: productId),
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // ── CA-01: Nombre y SKU visibles ─────────────────────────────────────────
  testWidgets('muestra nombre y SKU del producto', (tester) async {
    final product = _makeProduct(
      name: 'Coca-Cola 600ml',
      sku: 'NEX-B0001',
    );

    await tester.pumpWidget(_buildWidget(product));
    await tester.pumpAndSettle();

    // El nombre aparece en el AppBar (truncado) y en el body (headlineMedium)
    expect(find.text('Coca-Cola 600ml'), findsWidgets);
    // El SKU aparece solo en el chip del body
    expect(find.text('SKU: NEX-B0001'), findsOneWidget);
  });

  // ── CA-03: Precio, costo y margen correctos ───────────────────────────────
  testWidgets('muestra precio, costo y margen correctos', (tester) async {
    // precio: 18.00, costo: 11.50 → margen: (18-11.5)/18 * 100 = 36.1%
    final product = _makeProduct(priceMxn: 18.00, costMxn: 11.50);

    await tester.pumpWidget(_buildWidget(product));
    await tester.pumpAndSettle();

    expect(find.text('\$18.00'), findsOneWidget);
    expect(find.text('\$11.50'), findsOneWidget);
    expect(find.text('36.1%'), findsOneWidget);
  });

  // ── CA-04: Margen "—" cuando costo es 0 ──────────────────────────────────
  testWidgets('margen muestra "—" cuando cost_mxn es 0', (tester) async {
    final product = _makeProduct(priceMxn: 18.00, costMxn: 0.0);

    await tester.pumpWidget(_buildWidget(product));
    await tester.pumpAndSettle();

    expect(find.text('—'), findsWidgets); // margen + subtexto 'Sin costo'
    expect(find.text('Sin costo'), findsOneWidget);
  });

  // ── CA-05: Tarjeta DISPONIBLE con semáforo correcto ───────────────────────
  testWidgets('tarjeta DISPONIBLE muestra cantidad disponible', (tester) async {
    final product = _makeProduct(availableStock: 48, minStockAlert: 10);

    await tester.pumpWidget(_buildWidget(product));
    await tester.pumpAndSettle();

    // Encuentra los widgets StockCard
    expect(find.byType(StockCard), findsNWidgets(2));

    // La etiqueta DISPONIBLE y la cantidad aparecen en pantalla
    expect(find.text('DISPONIBLE'), findsOneWidget);
    expect(find.text('48'), findsOneWidget);
  });

  // ── CA-06: Tarjeta RESERVADO en muted cuando es 0 ────────────────────────
  testWidgets('tarjeta RESERVADO muestra 0 pzs cuando reserved_stock es 0',
      (tester) async {
    final product = _makeProduct(reservedStock: 0);

    await tester.pumpWidget(_buildWidget(product));
    await tester.pumpAndSettle();

    expect(find.text('RESERVADO'), findsOneWidget);
    expect(find.text('0'), findsOneWidget);
  });

  // ── CA-07: Cuadrícula muestra las 4 acciones ──────────────────────────────
  testWidgets('cuadrícula muestra las 4 acciones con etiquetas correctas',
      (tester) async {
    final product = _makeProduct();

    await tester.pumpWidget(_buildWidget(product));
    await tester.pumpAndSettle();

    expect(find.byType(ActionGrid), findsOneWidget);
    expect(find.text('Ajustar stock'), findsOneWidget);
    expect(find.text('Trasladar'), findsOneWidget);
    expect(find.text('Ver Kardex'), findsOneWidget);
    expect(find.text('Etiqueta'), findsOneWidget);
  });

  // ── Skeleton durante carga ────────────────────────────────────────────────
  testWidgets('muestra skeleton mientras el provider está cargando',
      (tester) async {
    // Completer que nunca resuelve — no deja timers pendientes
    final completer = Completer<Product>();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          inventoryRepositoryProvider.overrideWithValue(
            MockInventoryRepository(),
          ),
          // Override que nunca completa → provider queda en AsyncLoading
          productDetailProvider('prod-skeleton').overrideWith(
            (ref) => completer.future,
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.dark,
          home: const ProductDetailScreen(productId: 'prod-skeleton'),
        ),
      ),
    );

    // Primer frame: el provider está en AsyncLoading → skeleton visible
    await tester.pump();

    // Skeleton usa AnimatedBuilder internamente
    expect(find.byType(AnimatedBuilder), findsWidgets);
    // Datos del producto NO deben estar aún
    expect(find.text('Coca-Cola 600ml'), findsNothing);
  });

  // ── CA-09: Pantalla de error completa con Reintentar ─────────────────────
  testWidgets('error de carga muestra pantalla de error con botón Reintentar',
      (tester) async {
    await tester.pumpWidget(_buildErrorWidget('prod-error'));
    await tester.pumpAndSettle();

    expect(find.text('No se pudo cargar\nel producto'), findsOneWidget);
    expect(find.text('Reintentar'), findsOneWidget);
  });
}
