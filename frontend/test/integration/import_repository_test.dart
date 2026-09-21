import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_test/hive_test.dart';
import 'package:nexus_app/features/inventory/data/import_repository.dart';
import 'package:nexus_app/features/inventory/data/inventory_repository.dart';

import '_harness.dart';

/// Carga masiva (Tarea 5.2 ↔ 5.1, Sep 2026) — `ImportRepositoryImpl`
/// contra el contrato real del backend modular (`ImportPreviewResponse` /
/// `ColumnMapping` / `ImportExecutionResponse`). Hasta esta fecha el cliente
/// mandaba `col_name`/`col_price_mxn` y leía `preview_rows`, así que la
/// importación devolvía 422 en cada intento aunque las URLs fueran correctas.
void main() {
  late bool backendUp;

  setUpAll(() async {
    await setUpTestHive();
    backendUp = await isBackendUp();
  });

  tearDownAll(() async {
    await tearDownTestHive();
  });

  group('ImportRepositoryImpl — contra backend real', () {
    test('previewFile lee encabezados, filas de muestra, total y sugerencia',
        () async {
      if (!backendUp) {
        markTestSkipped('Backend no disponible en $integrationBaseUrl');
        return;
      }

      final session = await signInIntegrationTenant();
      final repo = ImportRepositoryImpl(client: session.client);

      const csv = 'Descripcion,Precio Venta,Existencias,Codigo de barras\n'
          'Coca-Cola 600ml,18.50,24,7501055300075\n'
          'Sabritas 45g,16.00,30,7501000310957\n';

      final preview = await repo.previewFile(
        'muestra.csv',
        fileBytes: utf8.encode(csv),
        fileName: 'muestra.csv',
      );

      expect(preview.headers,
          ['Descripcion', 'Precio Venta', 'Existencias', 'Codigo de barras']);
      expect(preview.totalRows, 2);
      expect(preview.previewRows.length, 2);
      expect(preview.previewRows.first,
          ['Coca-Cola 600ml', '18.50', '24', '7501055300075']);
      expect(preview.suggestedMapping.name, 'Descripcion');
      expect(preview.suggestedMapping.price, 'Precio Venta');
      expect(preview.suggestedMapping.stock, 'Existencias');
      expect(preview.suggestedMapping.barcode, 'Codigo de barras');
    });

    test('importFile da de alta, reporta omitidos y el producto aparece en inventario',
        () async {
      if (!backendUp) {
        markTestSkipped('Backend no disponible en $integrationBaseUrl');
        return;
      }

      final session = await signInIntegrationTenant();
      final repo = ImportRepositoryImpl(client: session.client);
      final inventory = InventoryRepositoryImpl(client: session.client);

      final suffix = DateTime.now().millisecondsSinceEpoch;
      final csv = 'Producto,Precio,Stock,Costo,Categoria\n'
          'Importado A $suffix,42.00,7,30.00,Integracion\n'
          'Importado B $suffix,abc,3,20.00,Integracion\n' // precio inválido
          'Importado C $suffix,15.50,,10.00,Integracion\n'; // sin stock → 0

      final result = await repo.importFile(
        filePath: 'lote.csv',
        mapping: const ColumnMapping(
          name: 'Producto',
          price: 'Precio',
          stock: 'Stock',
          cost: 'Costo',
          category: 'Categoria',
        ),
        fileBytes: utf8.encode(csv),
        fileName: 'lote.csv',
      );

      expect(result.totalRows, 3);
      expect(result.imported, 2);
      expect(result.skipped, 1);
      expect(result.status, 'partial');
      expect(result.errors.single.row, 3);
      expect(result.errors.single.issue, contains('Precio inválido'));

      final page = await inventory.getProducts(query: 'Importado A $suffix');
      final imported = page.items.single;
      expect(imported.priceMxn, 42.00);
      expect(imported.costMxn, 30.00);
      expect(imported.stock, 7);
      expect(imported.category, 'Integracion');

      final noStock =
          (await inventory.getProducts(query: 'Importado C $suffix')).items.single;
      expect(noStock.stock, 0);
    });

    test('importFile sin columna de stock entra con 0 piezas (stock opcional)',
        () async {
      if (!backendUp) {
        markTestSkipped('Backend no disponible en $integrationBaseUrl');
        return;
      }

      final session = await signInIntegrationTenant();
      final repo = ImportRepositoryImpl(client: session.client);
      final inventory = InventoryRepositoryImpl(client: session.client);

      final suffix = DateTime.now().millisecondsSinceEpoch;
      final csv = 'Nombre,Precio\nSolo precio $suffix,9.90\n';

      final result = await repo.importFile(
        filePath: 'sin_stock.csv',
        mapping: const ColumnMapping(name: 'Nombre', price: 'Precio'),
        fileBytes: utf8.encode(csv),
        fileName: 'sin_stock.csv',
      );

      expect(result.imported, 1);
      expect(result.skipped, 0);
      final product =
          (await inventory.getProducts(query: 'Solo precio $suffix')).items.single;
      expect(product.stock, 0);
    });

    test('un mapeo que apunta a una columna inexistente llega como ImportException legible',
        () async {
      if (!backendUp) {
        markTestSkipped('Backend no disponible en $integrationBaseUrl');
        return;
      }

      final session = await signInIntegrationTenant();
      final repo = ImportRepositoryImpl(client: session.client);

      await expectLater(
        repo.importFile(
          filePath: 'x.csv',
          mapping: const ColumnMapping(name: 'Nombre', price: 'NoExiste'),
          fileBytes: utf8.encode('Nombre,Precio\nA,1\n'),
          fileName: 'x.csv',
        ),
        throwsA(isA<ImportException>().having(
          (e) => e.message,
          'message',
          contains('NoExiste'),
        )),
      );
    });
  });
}
