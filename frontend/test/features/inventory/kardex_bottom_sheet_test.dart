import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nexus_app/core/theme/app_theme.dart';
import 'package:nexus_app/features/inventory/data/inventory_repository.dart';
import 'package:nexus_app/features/inventory/domain/inventory_movement.dart';
import 'package:nexus_app/features/inventory/presentation/widgets/kardex_bottom_sheet.dart';

// ---------------------------------------------------------------------------
// Mock
// ---------------------------------------------------------------------------

class MockInventoryRepository extends Mock implements InventoryRepository {}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

InventoryMovement _makeMovement({
  String id = 'mv-01',
  MovementType type = MovementType.saleOut,
  int quantity = -3,
  int stockBefore = 60,
  int stockAfter = 57,
  String? notes = 'Folio NV-2026-001547',
}) {
  return InventoryMovement(
    id: id,
    productId: 'prod-001',
    warehouseId: 'wh-001',
    movementType: type,
    quantity: quantity,
    stockBefore: stockBefore,
    stockAfter: stockAfter,
    unitCostMxn: 0,
    createdAt: DateTime(2026, 9, 6, 14, 32),
    notes: notes,
  );
}

void _stubRepo(
  MockInventoryRepository mock, {
  List<InventoryMovement>? items,
  bool throws = false,
}) {
  // Stub getProducts — requerido por InventoryNotifier.build()
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
    () => mock.getMovements(
      productId: any(named: 'productId'),
      movementType: any(named: 'movementType'),
      dateFrom: any(named: 'dateFrom'),
      dateTo: any(named: 'dateTo'),
      page: any(named: 'page'),
      pageSize: any(named: 'pageSize'),
    ),
  ).thenAnswer((_) async {
    if (throws) throw Exception('Sin conexión');
    final list = items ??
        [
          _makeMovement(id: 'mv-01', type: MovementType.saleOut, quantity: -3),
          _makeMovement(
              id: 'mv-02',
              type: MovementType.manualAdjustmentIn,
              quantity: 12,
              stockBefore: 48,
              stockAfter: 60,
              notes: 'Conteo físico'),
        ];
    return PaginatedMovements(
      items: list,
      total: list.length,
      page: 1,
      pageSize: 20,
      totalPages: 1,
    );
  });
}

/// Monta KardexBottomSheet directamente como home para testear sin BottomSheet.
Widget _buildWidget(MockInventoryRepository mock) {
  return ProviderScope(
    overrides: [inventoryRepositoryProvider.overrideWithValue(mock)],
    child: MaterialApp(
      theme: AppTheme.dark,
      home: const Scaffold(
        body: KardexBottomSheet(
          productId: 'prod-001',
          productName: 'Coca-Cola 600ml',
        ),
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late MockInventoryRepository mock;
  setUp(() => mock = MockInventoryRepository());

  // ── CA-02: movimientos visibles tras carga ─────────────────────────────
  testWidgets('muestra tipo, cantidad y notas de cada movimiento',
      (tester) async {
    _stubRepo(mock);
    await tester.pumpWidget(_buildWidget(mock));
    await tester.pumpAndSettle();

    // Tipo de movimiento
    expect(find.text('Venta'), findsOneWidget);
    expect(find.text('Ajuste entrada'), findsOneWidget);

    // Cantidades con signo
    expect(find.text('-3'), findsOneWidget);
    expect(find.text('+12'), findsOneWidget);

    // Stock antes → después
    expect(find.text('60 → 57 pzs'), findsOneWidget);
    expect(find.text('48 → 60 pzs'), findsOneWidget);
  });

  // ── CA-04: botón embudo abre el panel de filtros ───────────────────────
  testWidgets('botón embudo muestra y oculta el panel de filtros',
      (tester) async {
    _stubRepo(mock);
    await tester.pumpWidget(_buildWidget(mock));
    await tester.pumpAndSettle();

    // Panel no visible inicialmente
    expect(find.text('Todos los tipos'), findsNothing);

    // Tap en embudo
    await tester.tap(find.byIcon(Icons.filter_list_rounded));
    await tester.pumpAndSettle();

    // Panel visible
    expect(find.text('Todos los tipos'), findsOneWidget);

    // Segundo tap — oculta
    await tester.tap(find.byIcon(Icons.filter_list_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Todos los tipos'), findsNothing);
  });

  // ── CA-07: empty state sin filtros activos ─────────────────────────────
  testWidgets('empty state correcto cuando no hay movimientos', (tester) async {
    _stubRepo(mock, items: []);
    await tester.pumpWidget(_buildWidget(mock));
    await tester.pumpAndSettle();

    expect(
      find.text('Aún no hay movimientos\nregistrados'),
      findsOneWidget,
    );
  });

  // ── CA-09: error state con botón Reintentar ────────────────────────────
  testWidgets('error de carga muestra estado de error con Reintentar',
      (tester) async {
    _stubRepo(mock, throws: true);
    await tester.pumpWidget(_buildWidget(mock));
    await tester.pumpAndSettle();

    expect(find.text('No se pudo cargar\nel historial'), findsOneWidget);
    expect(find.text('Reintentar'), findsOneWidget);
  });
}
