import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nexus_app/core/theme/app_theme.dart';
import 'package:nexus_app/features/inventory/data/import_repository.dart';
import 'package:nexus_app/features/inventory/data/inventory_repository.dart';
import 'package:nexus_app/features/inventory/domain/product.dart';
import 'package:nexus_app/features/inventory/presentation/widgets/barcode_search_modal.dart';

class MockInventoryRepository extends Mock implements InventoryRepository {}

class MockImportRepository extends Mock implements ImportRepository {}

Product _makeProduct({
  String id = 'prod-101',
  String barcode = '7501055300075',
  String name = 'Coca-Cola Original 600ml',
  double priceMxn = 18.50,
  int stock = 24,
}) {
  return Product(
    id: id,
    sku: 'NEX-B0001',
    barcode: barcode,
    name: name,
    category: 'Bebidas',
    priceMxn: priceMxn,
    costMxn: 12.0,
    stock: stock,
    reservedStock: 0,
    availableStock: stock,
    minStockAlert: 5,
    isActive: true,
    isOnCatalog: true,
    createdAt: DateTime(2026, 9, 1),
  );
}

Widget _buildTestWidget({
  required InventoryRepository inventoryRepo,
  required ImportRepository importRepo,
}) {
  return ProviderScope(
    overrides: [
      inventoryRepositoryProvider.overrideWithValue(inventoryRepo),
      importRepositoryProvider.overrideWithValue(importRepo),
    ],
    child: MaterialApp(
      theme: AppTheme.dark,
      home: const BarcodeSearchModal(),
    ),
  );
}

void main() {
  late MockInventoryRepository mockInventoryRepo;
  late MockImportRepository mockImportRepo;

  setUp(() {
    mockInventoryRepo = MockInventoryRepository();
    mockImportRepo = MockImportRepository();
  });

  testWidgets('muestra interfaz inicial con entrada manual de codigo', (tester) async {
    await tester.pumpWidget(_buildTestWidget(
      inventoryRepo: mockInventoryRepo,
      importRepo: mockImportRepo,
    ));
    await tester.pump();

    expect(find.text('Escanear Código de Barras'), findsOneWidget);
    expect(find.text('Apunta al código de barras o ingrésalo manualmente:'), findsOneWidget);
    expect(find.text('Buscar'), findsOneWidget);
  });

  testWidgets('muestra tarjeta EN TU INVENTARIO si el producto existe localmente', (tester) async {
    final existingProduct = _makeProduct(
      barcode: '7501055300075',
      name: 'Coca-Cola Original 600ml',
      priceMxn: 18.50,
      stock: 24,
    );

    when(() => mockInventoryRepo.getProducts(
          query: any(named: 'query'),
          category: any(named: 'category'),
          lowStock: any(named: 'lowStock'),
          page: any(named: 'page'),
          pageSize: any(named: 'pageSize'),
        )).thenAnswer((_) async => PaginatedProducts(
          items: [existingProduct],
          total: 1,
          page: 1,
          pageSize: 50,
          totalPages: 1,
        ));

    await tester.pumpWidget(_buildTestWidget(
      inventoryRepo: mockInventoryRepo,
      importRepo: mockImportRepo,
    ));
    await tester.pump();

    await tester.enterText(find.byType(TextField), '7501055300075');
    await tester.pump();
    await tester.tap(find.text('Buscar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('EN TU INVENTARIO'), findsOneWidget);
    expect(find.text('Coca-Cola Original 600ml'), findsOneWidget);
    expect(find.text(r'$18.50 MXN'), findsOneWidget);
    expect(find.text('24 pzs disponibles'), findsOneWidget);
    expect(find.text('Ver Ficha'), findsOneWidget);
    expect(find.text('Filtrar'), findsOneWidget);
  });

  testWidgets('muestra tarjeta CATALOGO SEMILLA GS1 MEXICO si no existe localmente pero si en GS1', (tester) async {
    when(() => mockInventoryRepo.getProducts(
          query: any(named: 'query'),
          category: any(named: 'category'),
          lowStock: any(named: 'lowStock'),
          page: any(named: 'page'),
          pageSize: any(named: 'pageSize'),
        )).thenAnswer((_) async => const PaginatedProducts(
          items: [],
          total: 0,
          page: 1,
          pageSize: 50,
          totalPages: 0,
        ));

    when(() => mockImportRepo.lookupEan('7501000123456')).thenAnswer((_) async => const EanLookupResult(
          barcode: '7501000123456',
          name: 'Galletas Marias Gamesa 170g',
          category: 'Abarrotes',
          source: 'SEED_CATALOG',
          suggestedPriceMxn: 16.50,
        ));

    await tester.pumpWidget(_buildTestWidget(
      inventoryRepo: mockInventoryRepo,
      importRepo: mockImportRepo,
    ));
    await tester.pump();

    await tester.enterText(find.byType(TextField), '7501000123456');
    await tester.pump();
    await tester.tap(find.text('Buscar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('CATÁLOGO SEMILLA GS1 MÉXICO'), findsOneWidget);
    expect(find.text('Galletas Marias Gamesa 170g'), findsOneWidget);
    expect(find.text('Abarrotes'), findsOneWidget);
    expect(find.text(r'Sugerido: $16.50 MXN'), findsOneWidget);
    expect(find.text('Registrar en mi Inventario'), findsOneWidget);
  });

  testWidgets('muestra PRODUCTO NO REGISTRADO si no existe en ninguna fuente', (tester) async {
    when(() => mockInventoryRepo.getProducts(
          query: any(named: 'query'),
          category: any(named: 'category'),
          lowStock: any(named: 'lowStock'),
          page: any(named: 'page'),
          pageSize: any(named: 'pageSize'),
        )).thenAnswer((_) async => const PaginatedProducts(
          items: [],
          total: 0,
          page: 1,
          pageSize: 50,
          totalPages: 0,
        ));

    when(() => mockImportRepo.lookupEan('9999999999999')).thenAnswer((_) async => null);

    await tester.pumpWidget(_buildTestWidget(
      inventoryRepo: mockInventoryRepo,
      importRepo: mockImportRepo,
    ));
    await tester.pump();

    await tester.enterText(find.byType(TextField), '9999999999999');
    await tester.pump();
    await tester.tap(find.text('Buscar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('PRODUCTO NO REGISTRADO'), findsOneWidget);
    expect(find.text('Registrar Nuevo Producto'), findsOneWidget);
  });
}
