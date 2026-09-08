import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nexus_app/core/theme/app_theme.dart';
import 'package:nexus_app/features/inventory/data/inventory_repository.dart';
import 'package:nexus_app/features/inventory/domain/product.dart';
import 'package:nexus_app/features/inventory/presentation/widgets/adjust_stock_modal.dart';

// ---------------------------------------------------------------------------
// Mock
// ---------------------------------------------------------------------------

class MockInventoryRepository extends Mock implements InventoryRepository {}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Product _makeProduct({int availableStock = 48}) => Product(
      id: 'prod-001',
      sku: 'NEX-B0001',
      name: 'Coca-Cola 600ml',
      category: 'Bebidas',
      priceMxn: 18.0,
      costMxn: 11.0,
      stock: availableStock,
      reservedStock: 0,
      availableStock: availableStock,
      minStockAlert: 10,
      isActive: true,
      isOnCatalog: true,
      createdAt: DateTime(2026, 9, 1),
    );

void _stubRepo(MockInventoryRepository mock, {bool throws = false}) {
  when(
    () => mock.getProducts(
      query: any(named: 'query'),
      category: any(named: 'category'),
      lowStock: any(named: 'lowStock'),
      page: any(named: 'page'),
      pageSize: any(named: 'pageSize'),
    ),
  ).thenAnswer((_) async => const PaginatedProducts(
        items: [], total: 0, page: 1, pageSize: 20, totalPages: 1));

  when(
    () => mock.adjustStock(
      productId: any(named: 'productId'),
      movementType: any(named: 'movementType'),
      quantity: any(named: 'quantity'),
      reason: any(named: 'reason'),
    ),
  ).thenAnswer((_) async {
    if (throws) throw Exception('Error de red');
  });
}

Widget _buildWidget(Product product, MockInventoryRepository mock) {
  return ProviderScope(
    overrides: [inventoryRepositoryProvider.overrideWithValue(mock)],
    child: MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(body: AdjustStockModal(product: product)),
    ),
  );
}

// Finders
Finder get _applyBtn =>
    find.widgetWithText(ElevatedButton, 'Aplicar ajuste');
Finder get _reasonField =>
    find.widgetWithText(TextFormField, 'Ej: Conteo físico mensual');

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late MockInventoryRepository mock;
  setUp(() => mock = MockInventoryRepository());

  // ── Chip de tipo cambia a Entrada ─────────────────────────────────────────
  testWidgets('chip Entrada visible y seleccionable', (tester) async {
    _stubRepo(mock);
    await tester.pumpWidget(_buildWidget(_makeProduct(), mock));
    await tester.pump();

    expect(find.text('Entrada'), findsOneWidget);
    expect(find.text('Salida'),  findsOneWidget);
    expect(find.text('Merma'),   findsOneWidget);

    await tester.tap(find.text('Salida'));
    await tester.pump();
    // El preview debe mostrar la flecha de bajada
    expect(find.textContaining('↓'), findsOneWidget);
  });

  // ── Preview reactivo — entrada suma ───────────────────────────────────────
  testWidgets('preview muestra stock resultado correcto en entrada',
      (tester) async {
    _stubRepo(mock);
    final product = _makeProduct(availableStock: 48);
    await tester.pumpWidget(_buildWidget(product, mock));
    await tester.pump();

    // Por defecto tipo=Entrada, cantidad=1 → resultado = 49
    expect(find.textContaining('49'), findsOneWidget);
    expect(find.textContaining('↑'), findsOneWidget);
  });

  // ── Botón deshabilitado sin motivo ────────────────────────────────────────
  testWidgets('botón deshabilitado cuando motivo está vacío', (tester) async {
    _stubRepo(mock);
    await tester.pumpWidget(_buildWidget(_makeProduct(), mock));
    await tester.pump();

    final btn = tester.widget<ElevatedButton>(_applyBtn);
    expect(btn.onPressed, isNull);
  });

  // ── Botón habilitado con motivo válido ────────────────────────────────────
  testWidgets('botón habilitado con motivo de al menos 3 caracteres',
      (tester) async {
    _stubRepo(mock);
    await tester.pumpWidget(_buildWidget(_makeProduct(), mock));
    await tester.pump();

    await tester.enterText(_reasonField, 'Conteo físico mensual');
    await tester.pump();

    final btn = tester.widget<ElevatedButton>(_applyBtn);
    expect(btn.onPressed, isNotNull);
  });

  // ── Stock negativo — botón muestra "Stock insuficiente" ───────────────────
  testWidgets('stock negativo deshabilita botón con label Stock insuficiente',
      (tester) async {
    _stubRepo(mock);
    final product = _makeProduct(availableStock: 1);
    await tester.pumpWidget(_buildWidget(product, mock));
    await tester.pump();

    // Tipo Salida, cantidad 1 = stock actual → resultado = 0 (ok)
    // Selecciona salida y sube la cantidad a 2 para que sea negativo
    await tester.tap(find.text('Salida'));
    await tester.pump();

    // Presiona + dos veces → cantidad = 3 → resultado = 1 - 3 = -2
    await tester.tap(find.byIcon(Icons.add_rounded));
    await tester.tap(find.byIcon(Icons.add_rounded));
    await tester.pump();

    expect(find.widgetWithText(ElevatedButton, 'Stock insuficiente'),
        findsOneWidget);
    final btn = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Stock insuficiente'));
    expect(btn.onPressed, isNull);
  });
}
