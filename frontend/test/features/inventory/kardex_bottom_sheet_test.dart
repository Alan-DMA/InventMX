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

  // ── CA-10: deserialización tolerante de strings decimales del backend ───
  test('InventoryMovement.fromJson parsea strings decimales de Postgres correctamente', () {
    final payloadEntrada = {
      'id': '97ca3214-5fb0-4241-b2b9-543bd3b55db3',
      'product_id': 'b1a2a3a4-b1b2-c1c2-d1d2-000000000001',
      'warehouse_id': 'f1a2a3a4-b1b2-c1c2-d1d2-000000000001',
      'quantity': '20.0000',
      'type': 'ENTRADA',
      'previous_stock': '21.0000',
      'new_stock': '41.0000',
      'notes': 'Prueba 2',
      'created_at': '2026-09-14T13:20:57.744370',
    };

    final mEntrada = InventoryMovement.fromJson(payloadEntrada);
    expect(mEntrada.quantity, 20);
    expect(mEntrada.stockBefore, 21);
    expect(mEntrada.stockAfter, 41);
    expect(mEntrada.movementType, MovementType.manualAdjustmentIn);

    final payloadSalida = {
      'id': '5637df6f-9182-4675-b3ae-e00d5787c8d7',
      'product_id': 'b1a2a3a4-b1b2-c1c2-d1d2-000000000001',
      'warehouse_id': 'f1a2a3a4-b1b2-c1c2-d1d2-000000000001',
      'quantity': '2.0000',
      'type': 'SALIDA',
      'reference_document': 'NV-2026-000002',
      'previous_stock': '23.0000',
      'new_stock': '21.0000',
      'notes': 'Venta POS (NV-2026-000002): Venta POS mostrador: 2 x Harina PAN 1kg',
      'created_at': '2026-09-14T12:46:37.632175',
    };

    final mSalida = InventoryMovement.fromJson(payloadSalida);
    expect(mSalida.quantity, -2); // Normalizado a negativo
    expect(mSalida.stockBefore, 23);
    expect(mSalida.stockAfter, 21);
    expect(mSalida.movementType, MovementType.saleOut);
    expect(mSalida.referenceId, 'NV-2026-000002');
  });

  test('asiento inicial en alta de producto se clasifica como Stock inicial con cantidad positiva', () {
    final payloadAlta = {
      'id': '73b9d2c5-e144-4406-b8b5-19861dea0108',
      'product_id': '511dde2e-9f7c-4513-a78f-7dad242eb59b',
      'warehouse_id': '51513cee-b691-4034-925c-62e565b39ab1',
      'movement_type': 'ADJUSTMENT_IN',
      'quantity': '25.00',
      'previous_stock': '0.00',
      'new_stock': '25.00',
      'notes': 'Inventario inicial registrado en alta de producto',
      'created_at': '2026-09-14T23:02:00.000000',
    };

    final mAlta = InventoryMovement.fromJson(payloadAlta);
    expect(mAlta.movementType, MovementType.initialStock);
    expect(mAlta.movementType.label, 'Stock inicial');
    expect(mAlta.quantity, 25); // Positivo, NO negativo
    expect(mAlta.stockBefore, 0);
    expect(mAlta.stockAfter, 25);

    // Movimientos con palabra 'inventario' no deben confundirse con 'VENTA'
    final payloadConteo = {
      'id': '88b9d2c5-e144-4406-b8b5-19861dea0109',
      'product_id': '511dde2e-9f7c-4513-a78f-7dad242eb59b',
      'warehouse_id': '51513cee-b691-4034-925c-62e565b39ab1',
      'movement_type': 'ADJUSTMENT_IN',
      'quantity': '10.00',
      'previous_stock': '25.00',
      'new_stock': '35.00',
      'notes': 'Conteo físico de inventario de fin de mes',
      'created_at': '2026-09-14T23:05:00.000000',
    };

    final mConteo = InventoryMovement.fromJson(payloadConteo);
    expect(mConteo.movementType, MovementType.manualAdjustmentIn);
    expect(mConteo.quantity, 10);
  });
}
