import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nexus_app/core/theme/app_theme.dart';
import 'package:nexus_app/features/inventory/data/clone_catalog_repository.dart';
import 'package:nexus_app/features/inventory/data/inventory_repository.dart';
import 'package:nexus_app/features/inventory/domain/clone_catalog.dart';
import 'package:nexus_app/features/inventory/domain/product.dart';
import 'package:nexus_app/features/inventory/presentation/widgets/clone_catalog_sheet.dart';

// ---------------------------------------------------------------------------
// Fixtures — Tarea 15.2.2 (clonación de catálogo)
// ---------------------------------------------------------------------------

class MockInventoryRepository extends Mock implements InventoryRepository {}

Product _p(String id, String name, String category, {bool active = true}) => Product(
      id: id,
      sku: 'NEX-$id',
      name: name,
      category: category,
      priceMxn: 10,
      costMxn: 5,
      stock: 1,
      reservedStock: 0,
      availableStock: 1,
      isActive: active,
      isOnCatalog: false,
      createdAt: DateTime(2026, 9, 1),
    );

final _products = [
  _p('1', 'Coca-Cola 600ml', 'Bebidas'),
  _p('2', 'Pepsi 2L', 'Bebidas'),
  _p('3', 'Sabritas 45g', 'Botanas'),
  _p('4', 'Producto dado de baja', 'Botanas', active: false),
];

Widget _build({CloneCatalogRepository? repo}) {
  final inv = MockInventoryRepository();
  when(() => inv.getProducts(
        query: any(named: 'query'),
        category: any(named: 'category'),
        lowStock: any(named: 'lowStock'),
        page: any(named: 'page'),
        pageSize: any(named: 'pageSize'),
      )).thenAnswer((_) async => PaginatedProducts(
        items: _products,
        total: _products.length,
        page: 1,
        pageSize: 20,
        totalPages: 1,
      ));

  return ProviderScope(
    overrides: [
      inventoryRepositoryProvider.overrideWithValue(inv),
      cloneCatalogRepositoryProvider.overrideWithValue(
        repo ?? CloneCatalogRepositoryMock(stepDelay: Duration.zero, lookupDelay: Duration.zero),
      ),
    ],
    child: MaterialApp(
      theme: AppTheme.dark,
      home: const Scaffold(body: SingleChildScrollView(child: CloneCatalogSheet())),
    ),
  );
}

Future<void> _lookup(WidgetTester tester, String code) async {
  await tester.enterText(find.byKey(const Key('cloneTargetCodeField')), code);
  await tester.tap(find.byKey(const Key('cloneLookupButton')));
  await tester.pumpAndSettle();
}

void main() {
  group('CloneCatalogRequest.toJson', () {
    test('sigue el contrato POST /inventory/clone-catalog', () {
      const r = CloneCatalogRequest(
        targetTenantId: 't-1',
        includePrices: false,
        filterCategory: 'Bebidas',
      );
      expect(r.toJson(), {
        'target_tenant_id': 't-1',
        'include_prices': false,
        'include_categories': true,
        'filter_category': 'Bebidas',
      });
    });
  });

  // ── CA-03: sin destino no se puede clonar; el resumen lo dice ────────────
  testWidgets('arranca con el botón deshabilitado y cuenta solo productos activos',
      (tester) async {
    await tester.pumpWidget(_build());
    await tester.pumpAndSettle();

    final btn = tester.widget<FilledButton>(find.byKey(const Key('cloneConfirmButton')));
    expect(btn.onPressed, isNull);
    expect(find.text('3 productos por clonar · falta la tienda destino'), findsOneWidget);
    expect(find.text('Clonar 3 productos'), findsOneWidget);
  });

  testWidgets('código desconocido muestra el aviso y mantiene deshabilitado', (tester) async {
    await tester.pumpWidget(_build());
    await tester.pumpAndSettle();

    await _lookup(tester, '000000');

    expect(find.byKey(const Key('cloneTargetNotFound')), findsOneWidget);
    expect(find.byKey(const Key('cloneTargetCard')), findsNothing);
    final btn = tester.widget<FilledButton>(find.byKey(const Key('cloneConfirmButton')));
    expect(btn.onPressed, isNull);
  });

  testWidgets('código válido muestra la tienda y habilita la clonación', (tester) async {
    await tester.pumpWidget(_build());
    await tester.pumpAndSettle();

    await _lookup(tester, '220118');

    expect(find.byKey(const Key('cloneTargetCard')), findsOneWidget);
    expect(find.text('Bodega El Sol — Sucursal Centro'), findsOneWidget);
    expect(find.text('Se clonarán 3 productos a Bodega El Sol — Sucursal Centro'), findsOneWidget);
    final btn = tester.widget<FilledButton>(find.byKey(const Key('cloneConfirmButton')));
    expect(btn.onPressed, isNotNull);
  });

  testWidgets('editar el código invalida el destino encontrado', (tester) async {
    await tester.pumpWidget(_build());
    await tester.pumpAndSettle();
    await _lookup(tester, '220118');
    expect(find.byKey(const Key('cloneTargetCard')), findsOneWidget);

    await tester.enterText(find.byKey(const Key('cloneTargetCodeField')), '2201');
    await tester.pump();

    expect(find.byKey(const Key('cloneTargetCard')), findsNothing);
  });

  // ── CA-03: el wizard completa con progreso y resumen honesto ─────────────
  testWidgets('clona, muestra el resumen y dice qué no se copió', (tester) async {
    await tester.pumpWidget(_build());
    await tester.pumpAndSettle();
    await _lookup(tester, '220118');

    await tester.ensureVisible(find.byKey(const Key('cloneConfirmButton')));
    await tester.tap(find.byKey(const Key('cloneConfirmButton')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('cloneDone')), findsOneWidget);
    expect(find.text('3 productos clonados a Bodega El Sol — Sucursal Centro'), findsOneWidget);
    expect(find.textContaining('Stock, kardex y costos no se copiaron'), findsOneWidget);
    expect(find.byKey(const Key('cloneCloseButton')), findsOneWidget);
  });

  testWidgets('filtrar por categoría reduce el conteo y lo que se clona', (tester) async {
    await tester.pumpWidget(_build());
    await tester.pumpAndSettle();
    await _lookup(tester, '220118');

    await tester.tap(find.byKey(const Key('cloneFilterCategory')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Solo Bebidas').last);
    await tester.pumpAndSettle();

    expect(find.text('Clonar 2 productos'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('cloneConfirmButton')));
    await tester.tap(find.byKey(const Key('cloneConfirmButton')));
    await tester.pumpAndSettle();
    expect(find.textContaining('2 productos clonados'), findsOneWidget);
  });

  testWidgets('apagar "Copiar precios" cambia el resumen final', (tester) async {
    await tester.pumpWidget(_build());
    await tester.pumpAndSettle();
    await _lookup(tester, '220118');

    await tester.tap(find.byKey(const Key('cloneIncludePrices')));
    await tester.pump();
    expect(find.textContaining('se clonan en \$0.00'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('cloneConfirmButton')));
    await tester.tap(find.byKey(const Key('cloneConfirmButton')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Precios en \$0.00'), findsOneWidget);
  });

  testWidgets('un error del backend vuelve al paso 1 con el mensaje', (tester) async {
    final failing = _FailingRepo();
    await tester.pumpWidget(_build(repo: failing));
    await tester.pumpAndSettle();
    await _lookup(tester, '220118');

    await tester.ensureVisible(find.byKey(const Key('cloneConfirmButton')));
    await tester.tap(find.byKey(const Key('cloneConfirmButton')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('cloneError')), findsOneWidget);
    expect(find.text('La clonación de catálogos solo está disponible en el plan Corporativo.'),
        findsOneWidget);
    expect(find.byKey(const Key('cloneConfirmButton')), findsOneWidget);
  });
}

class _FailingRepo implements CloneCatalogRepository {
  @override
  Future<CloneTarget?> findTargetByCode(String code) async =>
      CloneCatalogRepositoryMock.targets.first;

  @override
  Future<CloneCatalogResult> cloneCatalog(
    CloneCatalogRequest request, {
    List<Product> sourceProducts = const [],
    CloneProgressCallback? onProgress,
  }) async {
    throw const CloneCatalogException(
      'La clonación de catálogos solo está disponible en el plan Corporativo.',
      code: 'CATALOG_CLONING_NOT_AVAILABLE',
    );
  }
}
