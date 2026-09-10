import 'package:flutter_riverpod/flutter_riverpod.dart';

// ---------------------------------------------------------------------------
// Modelos de dominio
// ---------------------------------------------------------------------------

/// Resultado del endpoint POST /inventory/import.
class ImportResult {
  const ImportResult({
    required this.totalRows,
    required this.imported,
    required this.updated,
    required this.skipped,
    required this.errors,
  });

  final int totalRows;
  final int imported;
  final int updated;
  final int skipped;
  final List<ImportRowError> errors;

  bool get hasErrors => errors.isNotEmpty;
}

/// Error por fila reportado por el backend.
class ImportRowError {
  const ImportRowError({required this.row, required this.issue});
  final int row;
  final String issue;
}

/// Resultado del endpoint GET /inventory/lookup-ean/{barcode}.
/// Contiene los datos del catálogo semilla si el EAN existe.
class EanLookupResult {
  const EanLookupResult({
    required this.barcode,
    required this.name,
    required this.category,
    required this.source,
    this.confidenceScore,
  });

  final String barcode;
  final String name;
  final String category;

  /// 'SEED_CATALOG' | 'COMMUNITY'
  final String source;
  final double? confidenceScore;
}

/// Metadatos de previsualización extraídos del archivo antes de importar.
class FilePreview {
  const FilePreview({
    required this.fileName,
    required this.headers,
    required this.previewRows,
    required this.totalRows,
  });

  /// Nombre del archivo seleccionado.
  final String fileName;

  /// Cabeceras detectadas (columna A, B, C… o nombres si el archivo los tiene).
  final List<String> headers;

  /// Primeras 5 filas del archivo para previsualización.
  final List<List<String>> previewRows;

  /// Total de filas con datos (sin contar cabecera).
  final int totalRows;
}

// ---------------------------------------------------------------------------
// Contrato
// ---------------------------------------------------------------------------

abstract class ImportRepository {
  /// Simula la lectura y previsualización del archivo seleccionado.
  /// En producción parseará el xlsx/csv localmente antes de enviarlo.
  Future<FilePreview> previewFile(String filePath);

  /// POST /inventory/import
  /// Envía el archivo con el mapeo de columnas y devuelve el resultado.
  Future<ImportResult> importFile({
    required String filePath,
    required String colName,
    required String colPrice,
    required String colStock,
  });

  /// GET /inventory/lookup-ean/{barcode}
  /// Consulta el catálogo semilla por código EAN.
  /// Retorna null si el código no existe en ningún catálogo.
  Future<EanLookupResult?> lookupEan(String barcode);
}

// ---------------------------------------------------------------------------
// Mock — activo hasta que Alan complete Tarea 5.1 (backend importador)
// ---------------------------------------------------------------------------

class ImportRepositoryMock implements ImportRepository {
  static const _fakeDelay = Duration(milliseconds: 500);

  /// Catálogo semilla local — Top 10 abarrotes mexicanos para QA visual.
  static const _seedCatalog = <String, EanLookupResult>{
    '7501055300018': EanLookupResult(
      barcode: '7501055300018',
      name: 'Coca-Cola 600ml',
      category: 'Bebidas',
      source: 'SEED_CATALOG',
    ),
    '7501000310957': EanLookupResult(
      barcode: '7501000310957',
      name: 'Sabritas Original 45g',
      category: 'Botanas',
      source: 'SEED_CATALOG',
    ),
    '7501030470492': EanLookupResult(
      barcode: '7501030470492',
      name: 'Bimbo Pan Blanco 680g',
      category: 'Panadería',
      source: 'SEED_CATALOG',
    ),
    '7501007630019': EanLookupResult(
      barcode: '7501007630019',
      name: 'Lala Leche Entera 1L',
      category: 'Lácteos',
      source: 'SEED_CATALOG',
    ),
    '7501003130499': EanLookupResult(
      barcode: '7501003130499',
      name: 'Maseca Harina de Maíz 1kg',
      category: 'Abarrotes',
      source: 'SEED_CATALOG',
    ),
    '7501007630156': EanLookupResult(
      barcode: '7501007630156',
      name: 'Lala Crema 200ml',
      category: 'Lácteos',
      source: 'SEED_CATALOG',
    ),
    '7501055360715': EanLookupResult(
      barcode: '7501055360715',
      name: 'Pepsi 600ml',
      category: 'Bebidas',
      source: 'SEED_CATALOG',
    ),
    '7501030490230': EanLookupResult(
      barcode: '7501030490230',
      name: 'Marinela Gansito 1pz',
      category: 'Panadería',
      source: 'SEED_CATALOG',
    ),
    '7501000310049': EanLookupResult(
      barcode: '7501000310049',
      name: 'Ruffles Queso 45g',
      category: 'Botanas',
      source: 'SEED_CATALOG',
    ),
    '093155171251': EanLookupResult(
      barcode: '093155171251',
      name: 'skyrim ps4',
      category: 'Botanas',
      source: 'SEED_CATALOG',
    ),
    '7501003103009': EanLookupResult(
      barcode: '7501003103009',
      name: 'Minsa Harina de Maíz 1kg',
      category: 'Abarrotes',
      source: 'SEED_CATALOG',
    ),
  };

  @override
  Future<FilePreview> previewFile(String filePath) async {
    await Future.delayed(_fakeDelay);
    // Simula un archivo Excel típico de proveedor con 3 columnas y 12 filas
    final fileName = filePath.split('/').last.split('\\').last;
    return FilePreview(
      fileName: fileName,
      headers: ['A', 'B', 'C', 'D'],
      previewRows: const [
        ['Coca-Cola 600ml', '7501055300018', '18.00', '48'],
        ['Sabritas Original 45g', '7501000310957', '16.50', '30'],
        ['Bimbo Pan Blanco 680g', '7501030470492', '42.00', '15'],
        ['Lala Leche Entera 1L', '7501007630019', '28.50', '20'],
        ['Maseca Harina de Maíz 1kg', '7501003130499', '35.00', '12'],
      ],
      totalRows: 120,
    );
  }

  @override
  Future<ImportResult> importFile({
    required String filePath,
    required String colName,
    required String colPrice,
    required String colStock,
  }) async {
    await Future.delayed(const Duration(milliseconds: 1200));
    // Simula importación mayormente exitosa con algunos errores de fila
    return const ImportResult(
      totalRows: 120,
      imported: 115,
      updated: 0,
      skipped: 5,
      errors: [
        ImportRowError(row: 23, issue: "El precio '15.ABC' no es un número válido."),
        ImportRowError(row: 47, issue: "Nombre de producto vacío."),
        ImportRowError(row: 78, issue: "Stock negativo no permitido."),
        ImportRowError(row: 99, issue: "Código de barras duplicado."),
        ImportRowError(row: 112, issue: "Precio igual a 0 no permitido."),
      ],
    );
  }

  @override
  Future<EanLookupResult?> lookupEan(String barcode) async {
    // Sin delay artificial — debe sentirse instantáneo en el modo góndola
    await Future.delayed(const Duration(milliseconds: 80));
    return _seedCatalog[barcode];
  }
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

final importRepositoryProvider = Provider<ImportRepository>(
  (_) => ImportRepositoryMock(),
);
