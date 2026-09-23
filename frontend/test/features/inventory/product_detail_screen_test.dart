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
import 'package:nexus_app/features/management/domain/app_permission.dart';
import 'package:nexus_app/features/management/presentation/management_provider.dart';

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
  double? suggestedMaxPriceMxn,
  String? suggestedMaxPriceSource,
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
    suggestedMaxPriceMxn: suggestedMaxPriceMxn,
    suggestedMaxPriceSource: suggestedMaxPriceSource,
  );
}

/// Construye el widget en modo standalone (sin GoRouter) —
/// suficiente para tests de la pantalla de detalle.
Widget _buildWidget(
  Product product, {
  MockInventoryRepository? mockRepo,
  Set<String>? permissions,
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
      // Puertas por rol (Fase A): sin sesión no hay permisos y la ficha
      // esconde Editar/Ajustar/Trasladar. Por defecto, Dueño.
      myPermissionsProvider.overrideWithValue(permissions ?? Permissions.all),
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

    // Encuentra el widget StockCard (RESERVADO se retiró — Sep 2026, ver
    // decisión: era un hold temporal de checkout, casi siempre en 0, sin
    // valor para el dueño de la tienda)
    expect(find.byType(StockCard), findsOneWidget);

    // La etiqueta DISPONIBLE y la cantidad aparecen en pantalla
    expect(find.text('DISPONIBLE'), findsOneWidget);
    expect(find.text('48'), findsOneWidget);
  });

  // ── CA-06: Precio máximo sugerido — historial vs. margen de respaldo ─────
  testWidgets(
      'precio máximo sugerido muestra el valor real y su leyenda (historial)',
      (tester) async {
    final product = _makeProduct(
      suggestedMaxPriceMxn: 24.50,
      suggestedMaxPriceSource: 'historical',
    );

    await tester.pumpWidget(_buildWidget(product));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Información adicional'));
    await tester.tap(find.text('Información adicional'));
    await tester.pumpAndSettle();

    expect(find.text('\$24.50'), findsOneWidget);
    expect(find.text('según tu historial de ventas'), findsOneWidget);
  });

  testWidgets(
      'precio máximo sugerido cae al margen configurado cuando no hay historial',
      (tester) async {
    final product = _makeProduct(
      suggestedMaxPriceMxn: 16.10,
      suggestedMaxPriceSource: 'margin_fallback',
    );

    await tester.pumpWidget(_buildWidget(product));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Información adicional'));
    await tester.tap(find.text('Información adicional'));
    await tester.pumpAndSettle();

    expect(find.text('\$16.10'), findsOneWidget);
    expect(find.text('según margen máximo configurado'), findsOneWidget);
  });

  testWidgets('precio máximo sugerido muestra "—" si el backend no lo envía',
      (tester) async {
    final product = _makeProduct();

    await tester.pumpWidget(_buildWidget(product));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Información adicional'));
    await tester.tap(find.text('Información adicional'));
    await tester.pumpAndSettle();

    expect(find.text('Precio máximo sugerido'), findsOneWidget);
    expect(find.text('—'), findsWidgets);
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
    expect(find.byTooltip('Editar producto'), findsOneWidget);
  });

  testWidgets(
      'un Cajero ve precio, costo y kardex, pero no edita ni ajusta (CA-07)',
      (tester) async {
    final product = _makeProduct();

    await tester.pumpWidget(_buildWidget(
      product,
      permissions: const {Permissions.inventoryView, Permissions.salesCheckout},
    ));
    await tester.pumpAndSettle();

    // Costo visible para todos los roles (D12).
    expect(find.text('COSTO'), findsOneWidget);
    expect(find.text('MARGEN'), findsOneWidget);
    expect(find.text('Ver Kardex'), findsOneWidget);
    expect(find.text('Etiqueta'), findsOneWidget);
    expect(find.text('Ajustar stock'), findsNothing);
    expect(find.text('Trasladar'), findsNothing);
    expect(find.byTooltip('Editar producto'), findsNothing);
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
