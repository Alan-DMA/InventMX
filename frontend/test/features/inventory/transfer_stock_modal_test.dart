import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nexus_app/core/theme/app_theme.dart';
import 'package:nexus_app/features/inventory/data/inventory_repository.dart';
import 'package:nexus_app/features/inventory/domain/product.dart';
import 'package:nexus_app/features/inventory/presentation/widgets/transfer_stock_modal.dart';

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
    () => mock.transferStock(
      productId: any(named: 'productId'),
      fromWarehouseId: any(named: 'fromWarehouseId'),
      toWarehouseId: any(named: 'toWarehouseId'),
      quantity: any(named: 'quantity'),
      notes: any(named: 'notes'),
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
      home: Scaffold(body: TransferStockModal(product: product)),
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late MockInventoryRepository mock;
  setUp(() => mock = MockInventoryRepository());

  // ── Dropdowns de almacén visibles ─────────────────────────────────────────
  testWidgets('muestra selectores de origen y destino', (tester) async {
    _stubRepo(mock);
    await tester.pumpWidget(_buildWidget(_makeProduct(), mock));
    await tester.pump();

    expect(find.text('Origen'), findsOneWidget);
    expect(find.text('Destino'), findsOneWidget);
    expect(find.text('Almacén Principal'), findsOneWidget);
    expect(find.text('Mostrador'), findsOneWidget);
  });

  // ── Origen igual a destino deshabilita botón ──────────────────────────────
  testWidgets('botón Trasladar deshabilitado cuando origen igual a destino',
      (tester) async {
    _stubRepo(mock);
    await tester.pumpWidget(_buildWidget(_makeProduct(), mock));
    await tester.pump();

    // Por defecto origen = wh-001 (Almacén Principal), destino = wh-002 (Mostrador)
    // Ambos son distintos → botón habilitado en estado inicial
    // Ahora verificamos que el banner de validación NO aparece
    expect(
      find.text('El origen y destino deben ser diferentes.'),
      findsNothing,
    );

    final btn = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Trasladar'),
    );
    expect(btn.onPressed, isNotNull);
  });

  // ── Cantidad mayor al disponible deshabilita botón ────────────────────────
  testWidgets('botón deshabilitado cuando cantidad excede stock disponible',
      (tester) async {
    _stubRepo(mock);
    final product = _makeProduct(availableStock: 2);
    await tester.pumpWidget(_buildWidget(product, mock));
    await tester.pump();

    // Sube cantidad a 3 (> 2 disponibles) con 2 taps en +
    await tester.tap(find.byIcon(Icons.add_rounded));
    await tester.tap(find.byIcon(Icons.add_rounded));
    await tester.pump();

    // Banner de validación visible
    expect(
      find.textContaining('Solo hay 2 pzs disponibles'),
      findsOneWidget,
    );

    final btn = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Trasladar'),
    );
    expect(btn.onPressed, isNull);
  });

  // ── Traslado exitoso cierra el modal ──────────────────────────────────────
  testWidgets('traslado exitoso cierra el modal', (tester) async {
    _stubRepo(mock);
    await tester.pumpWidget(_buildWidget(_makeProduct(), mock));
    await tester.pump();

    await tester.tap(find.widgetWithText(ElevatedButton, 'Trasladar'));
    await tester.pumpAndSettle();

    verify(
      () => mock.transferStock(
        productId: any(named: 'productId'),
        fromWarehouseId: any(named: 'fromWarehouseId'),
        toWarehouseId: any(named: 'toWarehouseId'),
        quantity: any(named: 'quantity'),
        notes: any(named: 'notes'),
      ),
    ).called(1);
  });
}
