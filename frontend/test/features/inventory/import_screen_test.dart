import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nexus_app/core/theme/app_theme.dart';
import 'package:nexus_app/features/inventory/data/import_repository.dart';
import 'package:nexus_app/features/inventory/data/inventory_repository.dart';
import 'package:nexus_app/features/inventory/presentation/import_screen.dart';
import 'package:nexus_app/features/inventory/presentation/inventory_provider.dart';
import 'package:nexus_app/features/inventory/presentation/widgets/column_mapper_row.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class MockImportRepository extends Mock implements ImportRepository {}

class MockInventoryRepository extends Mock implements InventoryRepository {}

class _FakeColumnMapping extends Fake implements ColumnMapping {}

// ---------------------------------------------------------------------------
// Fixtures — misma forma que devuelve `ImportRepositoryImpl` contra el
// backend real (`ImportPreviewResponse` / `ImportExecutionResponse`).
// ---------------------------------------------------------------------------

const _headers = ['DESCRIPCION', 'CODIGO_BARRAS', 'PRECIO_VENTA', 'EXISTENCIA'];

FilePreview _makePreview({
  int totalRows = 120,
  SuggestedMapping suggested = const SuggestedMapping(
    name: 'DESCRIPCION',
    price: 'PRECIO_VENTA',
    stock: 'EXISTENCIA',
    barcode: 'CODIGO_BARRAS',
  ),
}) =>
    FilePreview(
      fileName: 'productos.xlsx',
      headers: _headers,
      previewRows: const [
        ['Coca-Cola 600ml', '7501055300018', '18.00', '48'],
        ['Sabritas 45g', '7501000310957', '16.50', '30'],
        ['Bimbo Pan 680g', '7501030470492', '42.00', '15'],
        ['Lala Leche 1L', '7501007630019', '28.50', '20'],
        ['Maseca 1kg', '7501003130499', '35.00', '12'],
      ],
      totalRows: totalRows,
      suggestedMapping: suggested,
    );

const _successResult = ImportResult(
  totalRows: 120,
  imported: 115,
  skipped: 5,
  status: 'partial',
  errors: [
    ImportRowError(row: 23, issue: "Precio inválido o negativo: 'abc'"),
  ],
);

const _picked = (
  path: '/tmp/productos.xlsx',
  name: 'productos.xlsx',
  bytes: <int>[1, 2, 3],
);

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Widget _buildScreen({
  required MockImportRepository repo,
  MockInventoryRepository? inventoryRepo,
  PickedImportFile? picked = _picked,
}) {
  return ProviderScope(
    overrides: [
      importRepositoryProvider.overrideWithValue(repo),
      if (inventoryRepo != null)
        inventoryRepositoryProvider.overrideWithValue(inventoryRepo),
    ],
    child: MaterialApp(
      theme: AppTheme.dark,
      home: ImportScreen(filePicker: () async => picked),
    ),
  );
}

void _stubPreview(MockImportRepository repo, FilePreview preview) {
  when(() => repo.previewFile(
        any(),
        fileBytes: any(named: 'fileBytes'),
        fileName: any(named: 'fileName'),
      )).thenAnswer((_) async => preview);
}

void _stubImport(MockImportRepository repo, ImportResult result) {
  when(() => repo.importFile(
        filePath: any(named: 'filePath'),
        mapping: any(named: 'mapping'),
        fileBytes: any(named: 'fileBytes'),
        fileName: any(named: 'fileName'),
      )).thenAnswer((_) async => result);
}

void _stubGetProducts(MockInventoryRepository repo) {
  when(() => repo.getProducts(
        query: any(named: 'query'),
        category: any(named: 'category'),
        lowStock: any(named: 'lowStock'),
        page: any(named: 'page'),
        pageSize: any(named: 'pageSize'),
      )).thenAnswer((_) async => const PaginatedProducts(
        items: [],
        total: 0,
        page: 1,
        pageSize: 20,
        totalPages: 1,
      ));
}

/// Paso 0 → paso 1 (archivo elegido y previsualizado).
Future<void> _goToPreview(WidgetTester tester) async {
  await tester.tap(find.text('Toca para seleccionar un archivo'));
  await tester.pump();
  await tester.tap(find.widgetWithText(ElevatedButton, 'Previsualizar'));
  await tester.pumpAndSettle();
}

/// Paso 0 → paso 2 (mapeo).
Future<void> _goToMapping(WidgetTester tester) async {
  await _goToPreview(tester);
  await tester.tap(find.widgetWithText(ElevatedButton, 'Configurar mapeo'));
  await tester.pumpAndSettle();
}

/// La etiqueta del campo va en un `RichText` (para el asterisco), así que
/// se busca por la propiedad del widget y no por texto.
Finder _rowOf(String fieldLabel) => find.byWidgetPredicate(
      (w) => w is ColumnMapperRow && w.fieldLabel == fieldLabel,
    );

String? _selectedOf(WidgetTester tester, String fieldLabel) =>
    tester.widget<ColumnMapperRow>(_rowOf(fieldLabel)).selectedColumn;

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late MockImportRepository repo;

  setUpAll(() {
    registerFallbackValue('');
    registerFallbackValue(_FakeColumnMapping());
  });

  setUp(() {
    repo = MockImportRepository();
  });

  // ── CA-01: paso 0 ────────────────────────────────────────────────────────
  testWidgets('paso 0 muestra la zona de selección de archivo', (tester) async {
    await tester.pumpWidget(_buildScreen(repo: repo));
    await tester.pump();

    expect(find.text('Selecciona tu archivo'), findsOneWidget);
    expect(find.text('Toca para seleccionar un archivo'), findsOneWidget);
  });

  testWidgets('sin archivo seleccionado "Previsualizar" está deshabilitado',
      (tester) async {
    await tester.pumpWidget(_buildScreen(repo: repo, picked: null));
    await tester.pump();

    final btn = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Previsualizar'),
    );
    expect(btn.onPressed, isNull);
  });

  // ── CA-02: previsualización ─────────────────────────────────────────────
  testWidgets('la previsualización muestra las filas y el total del backend',
      (tester) async {
    _stubPreview(repo, _makePreview());
    await tester.pumpWidget(_buildScreen(repo: repo));
    await _goToPreview(tester);

    expect(find.text('Coca-Cola 600ml'), findsOneWidget);
    expect(find.text('Maseca 1kg'), findsOneWidget);
    expect(find.textContaining('120'), findsWidgets);
    verify(() => repo.previewFile(
          '/tmp/productos.xlsx',
          fileBytes: [1, 2, 3],
          fileName: 'productos.xlsx',
        )).called(1);
  });

  testWidgets('el error del backend al previsualizar se muestra tal cual',
      (tester) async {
    when(() => repo.previewFile(
          any(),
          fileBytes: any(named: 'fileBytes'),
          fileName: any(named: 'fileName'),
        )).thenThrow(const ImportException(
        'Formato no soportado. Solo se admiten archivos Excel (.xlsx) o CSV (.csv).'));
    await tester.pumpWidget(_buildScreen(repo: repo));
    await _goToPreview(tester);

    expect(find.textContaining('Formato no soportado'), findsOneWidget);
    expect(find.text('Selecciona tu archivo'), findsOneWidget); // sigue en paso 0
  });

  // ── CA-03: mapeo pre-llenado con la sugerencia del backend ──────────────
  testWidgets('el mapeo se pre-llena con suggested_mapping y abre las opcionales',
      (tester) async {
    _stubPreview(repo, _makePreview());
    await tester.pumpWidget(_buildScreen(repo: repo));
    await _goToMapping(tester);

    expect(_selectedOf(tester, 'Nombre del producto'), 'DESCRIPCION');
    expect(_selectedOf(tester, 'Precio de venta (MXN)'), 'PRECIO_VENTA');
    expect(_selectedOf(tester, 'Stock inicial'), 'EXISTENCIA');
    // La sugerencia trajo código de barras → el bloque opcional se abre solo
    expect(find.text('Más columnas (opcional)'), findsOneWidget);
    expect(find.text('1 mapeada'), findsOneWidget);
    expect(_selectedOf(tester, 'Código de barras'), 'CODIGO_BARRAS');
    expect(_selectedOf(tester, 'Costo de compra (MXN)'), isNull);
    expect(_selectedOf(tester, 'Categoría'), isNull);
  });

  testWidgets('sin sugerencia cae al mapeo posicional y las opcionales quedan cerradas',
      (tester) async {
    _stubPreview(repo, _makePreview(suggested: const SuggestedMapping()));
    await tester.pumpWidget(_buildScreen(repo: repo));
    await _goToMapping(tester);

    expect(_selectedOf(tester, 'Nombre del producto'), 'DESCRIPCION');
    expect(_selectedOf(tester, 'Precio de venta (MXN)'), 'PRECIO_VENTA');
    expect(_selectedOf(tester, 'Stock inicial'), 'EXISTENCIA');
    expect(find.text('Más columnas (opcional)'), findsOneWidget);
    expect(_rowOf('Código de barras'),
        findsNothing);

    await tester.tap(find.text('Más columnas (opcional)'));
    await tester.pumpAndSettle();
    expect(_rowOf('Código de barras'),
        findsOneWidget);
    expect(_rowOf('Categoría'), findsOneWidget);
  });

  testWidgets('el SKU nunca se ofrece como columna a mapear', (tester) async {
    _stubPreview(repo, _makePreview());
    await tester.pumpWidget(_buildScreen(repo: repo));
    await _goToMapping(tester);

    expect(_rowOf('SKU'), findsNothing);
  });

  // ── CA-04: importación manda el ColumnMapping real y muestra el resumen ─
  testWidgets('importar manda el mapeo con claves del backend y muestra el resultado',
      (tester) async {
    _stubPreview(repo, _makePreview());
    _stubImport(repo, _successResult);
    await tester.pumpWidget(_buildScreen(repo: repo));
    await _goToMapping(tester);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Importar 120 productos'));
    await tester.pumpAndSettle();

    final captured = verify(() => repo.importFile(
          filePath: '/tmp/productos.xlsx',
          mapping: captureAny(named: 'mapping'),
          fileBytes: [1, 2, 3],
          fileName: 'productos.xlsx',
        )).captured.single as ColumnMapping;
    expect(captured.toJson(), {
      'name_column': 'DESCRIPCION',
      'price_column': 'PRECIO_VENTA',
      'stock_column': 'EXISTENCIA',
      'barcode_column': 'CODIGO_BARRAS',
    });

    expect(find.text('¡Importación completada!'), findsOneWidget);
    expect(find.text('115'), findsOneWidget);
    expect(find.text('Importados'), findsOneWidget);
    expect(find.text('5'), findsOneWidget);
    expect(find.text('Omitidos'), findsOneWidget);
    expect(find.text('Fila 23'), findsOneWidget);
    expect(find.textContaining('Precio inválido'), findsOneWidget);
  });

  testWidgets('tras importar se invalida inventoryProvider (lista fresca)',
      (tester) async {
    final inventoryRepo = MockInventoryRepository();
    _stubGetProducts(inventoryRepo);
    _stubPreview(repo, _makePreview());
    _stubImport(repo, _successResult);

    await tester.pumpWidget(
      _buildScreen(repo: repo, inventoryRepo: inventoryRepo),
    );
    // Simula que Inventario ya estaba abierto detrás del wizard.
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ImportScreen)),
    );
    container.read(inventoryProvider);
    await tester.pumpAndSettle();
    verify(() => inventoryRepo.getProducts(
          query: any(named: 'query'),
          category: any(named: 'category'),
          lowStock: any(named: 'lowStock'),
          page: any(named: 'page'),
          pageSize: any(named: 'pageSize'),
        )).called(1);

    await _goToMapping(tester);
    await tester.tap(find.widgetWithText(ElevatedButton, 'Importar 120 productos'));
    await tester.pumpAndSettle();

    container.read(inventoryProvider);
    await tester.pumpAndSettle();
    verify(() => inventoryRepo.getProducts(
          query: any(named: 'query'),
          category: any(named: 'category'),
          lowStock: any(named: 'lowStock'),
          page: any(named: 'page'),
          pageSize: any(named: 'pageSize'),
        )).called(1);
  });

  // ── CA-05: error de importación muestra banner sin salir del mapeo ──────
  testWidgets('el error del backend al importar se muestra y el wizard sigue en mapeo',
      (tester) async {
    _stubPreview(repo, _makePreview());
    when(() => repo.importFile(
          filePath: any(named: 'filePath'),
          mapping: any(named: 'mapping'),
          fileBytes: any(named: 'fileBytes'),
          fileName: any(named: 'fileName'),
        )).thenThrow(const ImportException(
        "La columna de Precio 'PRECIO_VENTA' no existe en el archivo."));
    await tester.pumpWidget(_buildScreen(repo: repo));
    await _goToMapping(tester);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Importar 120 productos'));
    await tester.pumpAndSettle();

    expect(find.textContaining('no existe en el archivo'), findsOneWidget);
    expect(find.text('Mapeo de columnas'), findsOneWidget);
  });
}
