import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/dio_client.dart';
import '../../auth/data/auth_repository.dart';

// ---------------------------------------------------------------------------
// Modelos de dominio
// ---------------------------------------------------------------------------

/// Resultado del endpoint POST /api/v1/inventory/import/execute
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

/// Error por fila reportado por el backend
class ImportRowError {
  const ImportRowError({required this.row, required this.issue});
  final int row;
  final String issue;
}

/// Resultado del endpoint GET /api/v1/inventory/lookup-ean/{barcode}
class EanLookupResult {
  const EanLookupResult({
    required this.barcode,
    required this.name,
    required this.category,
    required this.source,
    this.confidenceScore,
    this.suggestedPriceMxn,
    this.suggestedCostMxn,
    this.imageUrl,
  });

  final String barcode;
  final String name;
  final String category;
  final String source;
  final double? confidenceScore;
  final double? suggestedPriceMxn;
  final double? suggestedCostMxn;
  final String? imageUrl;
}

/// Metadatos de previsualización extraídos del archivo antes de importar
class FilePreview {
  const FilePreview({
    required this.fileName,
    required this.headers,
    required this.previewRows,
    required this.totalRows,
  });

  final String fileName;
  final List<String> headers;
  final List<List<String>> previewRows;
  final int totalRows;
}

/// Excepción específica del módulo de importación
class ImportException implements Exception {
  const ImportException(this.message);
  final String message;

  @override
  String toString() => message;
}

// ---------------------------------------------------------------------------
// Contrato
// ---------------------------------------------------------------------------

abstract class ImportRepository {
  /// Previsualización de cabeceras y primeras 5 filas del archivo
  Future<FilePreview> previewFile(String filePath, {List<int>? fileBytes, String? fileName});

  /// Ejecución de la ingesta masiva con mapeo de columnas
  Future<ImportResult> importFile({
    required String filePath,
    required String colName,
    required String colPrice,
    required String colStock,
    List<int>? fileBytes,
    String? fileName,
  });

  /// Consulta al Catálogo Semilla Maestro GS1 México por código EAN
  Future<EanLookupResult?> lookupEan(String barcode);
}

// ---------------------------------------------------------------------------
// Implementación Real (Conexión Directa a la API FastAPI / PostgreSQL)
// ---------------------------------------------------------------------------

class ImportRepositoryImpl implements ImportRepository {
  ImportRepositoryImpl({required this.client});

  final DioClient client;

  @override
  Future<FilePreview> previewFile(String filePath, {List<int>? fileBytes, String? fileName}) async {
    try {
      final name = fileName ?? filePath.split('/').last.split('\\').last;
      final FormData formData;
      if (fileBytes != null && fileBytes.isNotEmpty) {
        formData = FormData.fromMap({
          'file': MultipartFile.fromBytes(fileBytes, filename: name),
        });
      } else {
        formData = FormData.fromMap({
          'file': await MultipartFile.fromFile(filePath, filename: name),
        });
      }

      final response = await client.post(
        '/api/v1/inventory/import/preview',
        data: formData,
      );

      final dynamic data = response.data;
      if (data == null || data is! Map) {
        throw const ImportException('Respuesta inválida del servidor al previsualizar archivo.');
      }

      final headers = (data['headers'] as List? ?? []).map((e) => e.toString()).toList();
      final rawPreviewRows = data['preview_rows'] as List? ?? [];
      final List<List<String>> previewRows = [];

      for (final row in rawPreviewRows) {
        if (row is Map) {
          final rowList = headers.map((h) => row[h]?.toString() ?? '').toList();
          previewRows.add(rowList);
        } else if (row is List) {
          previewRows.add(row.map((e) => e?.toString() ?? '').toList());
        }
      }

      return FilePreview(
        fileName: data['filename']?.toString() ?? name,
        headers: headers,
        previewRows: previewRows,
        totalRows: (data['total_rows'] as num? ?? 0).toInt(),
      );
    } on DioException catch (e) {
      throw _mapDioError(e);
    } catch (e) {
      if (e is ImportException) rethrow;
      throw ImportException('Error al previsualizar archivo: $e');
    }
  }

  @override
  Future<ImportResult> importFile({
    required String filePath,
    required String colName,
    required String colPrice,
    required String colStock,
    List<int>? fileBytes,
    String? fileName,
  }) async {
    try {
      final name = fileName ?? filePath.split('/').last.split('\\').last;
      final mappingMap = <String, dynamic>{
        'col_name': colName,
        'col_price_mxn': colPrice,
      };
      if (colStock.isNotEmpty) {
        mappingMap['col_stock'] = colStock;
      }
      final mappingJson = jsonEncode(mappingMap);

      final FormData formData;
      if (fileBytes != null && fileBytes.isNotEmpty) {
        formData = FormData.fromMap({
          'file': MultipartFile.fromBytes(fileBytes, filename: name),
          'mapping': mappingJson,
        });
      } else {
        formData = FormData.fromMap({
          'file': await MultipartFile.fromFile(filePath, filename: name),
          'mapping': mappingJson,
        });
      }

      final response = await client.post(
        '/api/v1/inventory/import/execute',
        data: formData,
      );

      final dynamic data = response.data;
      if (data == null || data is! Map) {
        throw const ImportException('Respuesta inválida al ejecutar la importación.');
      }

      final totalRows = (data['total_rows'] as num? ?? 0).toInt();
      final imported = (data['imported_count'] as num? ?? 0).toInt();
      final updated = (data['updated_count'] as num? ?? 0).toInt();
      final errorCount = (data['error_count'] as num? ?? 0).toInt();
      final rawErrors = data['errors'] as List? ?? [];

      final errors = rawErrors.map((e) {
        if (e is Map) {
          return ImportRowError(
            row: (e['row_index'] as num? ?? 0).toInt(),
            issue: e['error_message']?.toString() ?? 'Error en la fila del archivo',
          );
        }
        return ImportRowError(row: 0, issue: e.toString());
      }).toList();

      return ImportResult(
        totalRows: totalRows,
        imported: imported,
        updated: updated,
        skipped: errorCount,
        errors: errors,
      );
    } on DioException catch (e) {
      throw _mapDioError(e);
    } catch (e) {
      if (e is ImportException) rethrow;
      throw ImportException('Error al importar archivo: $e');
    }
  }

  @override
  Future<EanLookupResult?> lookupEan(String barcode) async {
    try {
      final cleanBarcode = barcode.trim();
      final response = await client.get('/api/v1/inventory/lookup-ean/$cleanBarcode');
      final dynamic data = response.data;
      if (data == null || data is! Map) return null;

      final bool found = data['found'] == true;
      if (!found) return null;

      final dynamic prod = data['product'];
      if (prod == null || prod is! Map) return null;

      final rawPrice = prod['suggested_price_mxn'];
      final double? price = rawPrice is num ? rawPrice.toDouble() : (rawPrice != null ? double.tryParse(rawPrice.toString()) : null);

      final rawCost = prod['suggested_cost_mxn'];
      final double? cost = rawCost is num ? rawCost.toDouble() : (rawCost != null ? double.tryParse(rawCost.toString()) : null);

      return EanLookupResult(
        barcode: (prod['barcode'] ?? cleanBarcode).toString(),
        name: (prod['name'] ?? '').toString(),
        category: (prod['category_name'] ?? 'General').toString(),
        source: (prod['source'] ?? 'SEED_CATALOG').toString(),
        confidenceScore: (prod['confidence_score'] as num?)?.toDouble(),
        suggestedPriceMxn: price,
        suggestedCostMxn: cost,
        imageUrl: prod['image_url']?.toString(),
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      throw _mapDioError(e);
    } catch (_) {
      return null;
    }
  }

  Exception _mapDioError(DioException e) {
    if (e.response != null) {
      final data = e.response?.data;
      if (data is Map) {
        if (data['error'] is Map && data['error']['message'] != null) {
          return ImportException(data['error']['message'].toString());
        }
        if (data['detail'] != null) {
          return ImportException(data['detail'].toString());
        }
      }
    }
    return ImportException('Error de comunicación con el servicio de inventario: ${e.message ?? e.type.name}');
  }
}

// ---------------------------------------------------------------------------
// Mock — mantenido para tests unitarios
// ---------------------------------------------------------------------------

class ImportRepositoryMock implements ImportRepository {
  static const _fakeDelay = Duration(milliseconds: 100);

  static const _seedCatalog = <String, EanLookupResult>{
    '7501055300075': EanLookupResult(
      barcode: '7501055300075',
      name: 'Coca-Cola Original 600ml NR',
      category: 'Bebidas',
      source: 'SEED_CATALOG',
      suggestedPriceMxn: 18.5,
    ),
    '7501055300018': EanLookupResult(
      barcode: '7501055300018',
      name: 'Coca-Cola 600ml',
      category: 'Bebidas',
      source: 'SEED_CATALOG',
    ),
    '7501000310957': EanLookupResult(
      barcode: '7501000310957',
      name: 'Sabritas Original 45g',
      category: 'Botanas y Snacks',
      source: 'SEED_CATALOG',
    ),
    // Ampliación D15 (QA de Eduardo): 5 productos más del Top de abarrotes
    // México, mismos códigos que `CommunityCatalogRepositoryMock.seed` para
    // que POS y Góndola coincidan.
    '7501030424564': EanLookupResult(
      barcode: '7501030424564',
      name: 'Pan Blanco Bimbo Grande 680g',
      category: 'Panadería',
      source: 'SEED_CATALOG',
      suggestedPriceMxn: 47.0,
    ),
    '7501020512113': EanLookupResult(
      barcode: '7501020512113',
      name: 'Leche Lala Entera 1L Tetra Pak',
      category: 'Lácteos',
      source: 'SEED_CATALOG',
      suggestedPriceMxn: 28.5,
    ),
    '7501005101010': EanLookupResult(
      barcode: '7501005101010',
      name: 'Harina de Maíz Nixtamalizado Maseca 1kg',
      category: 'Abarrotes',
      source: 'SEED_CATALOG',
      suggestedPriceMxn: 21.0,
    ),
    '7501031322401': EanLookupResult(
      barcode: '7501031322401',
      name: 'Peñafiel Mineral con Gas 600ml',
      category: 'Bebidas',
      source: 'SEED_CATALOG',
      suggestedPriceMxn: 16.0,
    ),
    '7501011115668': EanLookupResult(
      barcode: '7501011115668',
      name: 'Sabritas Sal 45g',
      category: 'Botanas y Snacks',
      source: 'SEED_CATALOG',
      suggestedPriceMxn: 20.0,
    ),
  };

  @override
  Future<FilePreview> previewFile(String filePath, {List<int>? fileBytes, String? fileName}) async {
    await Future.delayed(_fakeDelay);
    final name = fileName ?? filePath.split('/').last.split('\\').last;
    return FilePreview(
      fileName: name,
      headers: const ['A', 'B', 'C', 'D'],
      previewRows: const [
        ['Coca-Cola 600ml', '7501055300018', '18.00', '48'],
        ['Sabritas Original 45g', '7501000310957', '16.50', '30'],
      ],
      totalRows: 2,
    );
  }

  @override
  Future<ImportResult> importFile({
    required String filePath,
    required String colName,
    required String colPrice,
    required String colStock,
    List<int>? fileBytes,
    String? fileName,
  }) async {
    await Future.delayed(_fakeDelay);
    return const ImportResult(
      totalRows: 10,
      imported: 10,
      updated: 0,
      skipped: 0,
      errors: [],
    );
  }

  @override
  Future<EanLookupResult?> lookupEan(String barcode) async {
    await Future.delayed(_fakeDelay);
    return _seedCatalog[barcode];
  }
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

final importRepositoryProvider = Provider<ImportRepository>(
  (ref) => ImportRepositoryImpl(
    client: ref.watch(dioClientProvider),
  ),
);
