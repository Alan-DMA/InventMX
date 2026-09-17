import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/dio_client.dart';
import '../../auth/data/auth_repository.dart';
import '../domain/inventory_movement.dart';
import '../domain/product.dart';
import 'inventory_mock_data.dart';

// ---------------------------------------------------------------------------
// Modelos auxiliares de respuesta
// ---------------------------------------------------------------------------

/// Respuesta paginada de productos de inventario
class PaginatedProducts {
  const PaginatedProducts({
    required this.items,
    required this.total,
    required this.page,
    required this.pageSize,
    required this.totalPages,
  });

  final List<Product> items;
  final int total;
  final int page;
  final int pageSize;
  final int totalPages;
}

/// Respuesta paginada de movimientos Kardex
class PaginatedMovements {
  const PaginatedMovements({
    required this.items,
    required this.total,
    required this.page,
    required this.pageSize,
    required this.totalPages,
  });

  final List<InventoryMovement> items;
  final int total;
  final int page;
  final int pageSize;
  final int totalPages;
}

// ---------------------------------------------------------------------------
// Excepción de dominio para Inventario
// ---------------------------------------------------------------------------

class InventoryException implements Exception {
  const InventoryException(this.message);
  final String message;

  @override
  String toString() => message;
}

// ---------------------------------------------------------------------------
// Contrato de Repositorio de Inventario
// ---------------------------------------------------------------------------

abstract class InventoryRepository {
  /// GET /api/v1/inventory/products
  Future<PaginatedProducts> getProducts({
    String? query,
    String? category,
    bool lowStock = false,
    int page = 1,
    int pageSize = 20,
  });

  /// GET /api/v1/inventory/products/{id}
  Future<Product> getProductById(String id);

  /// POST /api/v1/inventory/products
  Future<Product> createProduct({
    required String name,
    required double priceMxn,
    int stock = 0,
    String? category,
    String? barcode,
    double? costMxn,
    int? minStockAlert,
    String? imageUrl,
    String? supplierId,
  });

  /// PUT /api/v1/inventory/products/{id}
  Future<Product> updateProduct({
    required String productId,
    String? name,
    double? priceMxn,
    double? costMxn,
    String? category,
    String? barcode,
    int? minStockAlert,
    String? imageUrl,
    bool? isActive,
    String? supplierId,
  });

  /// GET /api/v1/suppliers
  Future<List<Map<String, dynamic>>> getSuppliers();

  /// POST /api/v1/inventory/upload-image
  Future<String> uploadProductImage({
    required List<int> fileBytes,
    required String fileName,
  });

  /// POST /api/v1/inventory/adjust-stock
  Future<void> adjustStock({
    required String productId,
    required String movementType,
    required int quantity,
    required String reason,
    String? warehouseId,
  });

  /// POST /api/v1/inventory/transfer-stock
  Future<void> transferStock({
    required String productId,
    required String fromWarehouseId,
    required String toWarehouseId,
    required int quantity,
    String? notes,
  });

  /// GET /api/v1/inventory/movements
  Future<PaginatedMovements> getMovements({
    required String productId,
    String? movementType,
    DateTime? dateFrom,
    DateTime? dateTo,
    int page = 1,
    int pageSize = 20,
  });
}

// ---------------------------------------------------------------------------
// Implementación Real (Conexión Directa a la API FastAPI / PostgreSQL)
// ---------------------------------------------------------------------------

class InventoryRepositoryImpl implements InventoryRepository {
  InventoryRepositoryImpl({required this.client});

  final DioClient client;
  String? _cachedDefaultWarehouseId;
  final Map<String, String> _categoryCache = {};

  /// Obtiene o consulta el almacén principal asignado al comercio
  Future<String> _getDefaultWarehouseId() async {
    if (_cachedDefaultWarehouseId != null) {
      return _cachedDefaultWarehouseId!;
    }
    try {
      final response = await client.get('/api/v1/inventory/warehouses');
      final data = response.data;
      if (data is List && data.isNotEmpty) {
        final first = data.first;
        if (first is Map && first['id'] != null) {
          _cachedDefaultWarehouseId = first['id'].toString();
          return _cachedDefaultWarehouseId!;
        }
      }
    } catch (_) {}
    return '00000000-0000-0000-0000-000000000000';
  }

  /// Resuelve el UUID de una categoría por nombre (creándola si no existe)
  Future<String?> _resolveCategoryId(String? categoryName) async {
    if (categoryName == null ||
        categoryName.trim().isEmpty ||
        categoryName.trim().toLowerCase() == 'todos') {
      return null;
    }

    final trimmed = categoryName.trim();
    // Si ya es un UUID válido de 36 caracteres con guiones
    if (RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')
        .hasMatch(trimmed)) {
      return trimmed;
    }

    if (_categoryCache.containsKey(trimmed.toLowerCase())) {
      return _categoryCache[trimmed.toLowerCase()];
    }

    try {
      // 1. Buscar en categorías existentes del tenant
      final response = await client.get('/api/v1/inventory/categories');
      final data = response.data;
      if (data is List) {
        for (final item in data) {
          if (item is Map && item['name'] != null && item['id'] != null) {
            final catName = item['name'].toString().trim().toLowerCase();
            final catId = item['id'].toString();
            _categoryCache[catName] = catId;
            if (catName == trimmed.toLowerCase()) {
              return catId;
            }
          }
        }
      }

      // 2. Si no existe, crear la categoría dinámicamente
      final createResp = await client.post(
        '/api/v1/inventory/categories',
        data: {'name': trimmed},
      );
      final createData = createResp.data;
      if (createData is Map && createData['id'] != null) {
        final newId = createData['id'].toString();
        _categoryCache[trimmed.toLowerCase()] = newId;
        return newId;
      }
    } catch (_) {}
    return null;
  }

  @override
  Future<PaginatedProducts> getProducts({
    String? query,
    String? category,
    bool lowStock = false,
    int page = 1,
    int pageSize = 20,
  }) async {
    try {
      final queryParams = <String, dynamic>{
        'skip': (page - 1) * pageSize,
        'limit': pageSize,
      };

      if (query != null && query.trim().isNotEmpty) {
        queryParams['q'] = query.trim();
      }
      if (lowStock) {
        queryParams['low_stock'] = true;
      }

      final response = await client.get(
        '/api/v1/inventory/products',
        queryParameters: queryParams,
      );

      final dynamic data = response.data;
      if (data is! List) {
        throw const InventoryException('Formato de respuesta de catálogo inválido.');
      }

      var items = data
          .map((json) => Product.fromJson(json as Map<dynamic, dynamic>))
          .toList();

      // Filtro local complementario de categoría
      if (category != null &&
          category.isNotEmpty &&
          category.toLowerCase() != 'todos') {
        items = items
            .where((p) =>
                p.category.toLowerCase() == category.toLowerCase())
            .toList();
      }

      final total = items.length;
      final totalPages = items.length < pageSize ? page : page + 1;

      return PaginatedProducts(
        items: items,
        total: total,
        page: page,
        pageSize: pageSize,
        totalPages: totalPages < 1 ? 1 : totalPages,
      );
    } on DioException catch (e) {
      throw _mapDioError(e);
    } catch (e) {
      if (e is InventoryException) rethrow;
      throw InventoryException('Error al cargar catálogo de productos: $e');
    }
  }

  @override
  Future<Product> getProductById(String id) async {
    try {
      final response = await client.get('/api/v1/inventory/products/$id');
      final dynamic data = response.data;
      if (data == null || data is! Map) {
        throw const InventoryException('Producto no encontrado.');
      }
      return Product.fromJson(data);
    } on DioException catch (e) {
      throw _mapDioError(e);
    } catch (e) {
      if (e is InventoryException) rethrow;
      throw InventoryException('Error al obtener detalle del producto: $e');
    }
  }

  @override
  Future<Product> createProduct({
    required String name,
    required double priceMxn,
    int stock = 0,
    String? category,
    String? barcode,
    double? costMxn,
    int? minStockAlert,
    String? imageUrl,
    String? supplierId,
  }) async {
    try {
      final categoryId = await _resolveCategoryId(category);
      final payload = <String, dynamic>{
        'name': name.trim(),
        'price_mxn': priceMxn,
        'price_usd': priceMxn,
        'initial_stock': stock,
        'stock_inicial': stock,
        if (costMxn != null) ...{
          'cost_mxn': costMxn,
          'cost_usd': costMxn,
        },
        if (barcode != null && barcode.trim().isNotEmpty) 'barcode': barcode.trim(),
        if (categoryId != null) 'category_id': categoryId,
        if (supplierId != null && supplierId.isNotEmpty) 'supplier_id': supplierId,
        if (minStockAlert != null) 'min_stock_alert': minStockAlert,
        if (imageUrl != null && imageUrl.trim().isNotEmpty) 'image_url': imageUrl.trim(),
      };

      final response = await client.post(
        '/api/v1/inventory/products',
        data: payload,
      );

      final dynamic data = response.data;
      if (data == null || data is! Map) {
        throw const InventoryException('Respuesta inválida al registrar producto.');
      }
      return Product.fromJson(data);
    } on DioException catch (e) {
      throw _mapDioError(e);
    } catch (e) {
      if (e is InventoryException) rethrow;
      throw InventoryException('Error al registrar producto: $e');
    }
  }

  @override
  Future<Product> updateProduct({
    required String productId,
    String? name,
    double? priceMxn,
    double? costMxn,
    String? category,
    String? barcode,
    int? minStockAlert,
    String? imageUrl,
    bool? isActive,
    String? supplierId,
  }) async {
    try {
      final payload = <String, dynamic>{};
      if (name != null) payload['name'] = name.trim();
      if (priceMxn != null) {
        payload['price_mxn'] = priceMxn;
        payload['price_usd'] = priceMxn;
      }
      if (costMxn != null) {
        payload['cost_mxn'] = costMxn;
        payload['cost_usd'] = costMxn;
      }
      if (barcode != null) {
        payload['barcode'] = barcode.trim().isEmpty ? null : barcode.trim();
      }
      if (category != null) {
        final catId = await _resolveCategoryId(category);
        payload['category_id'] = catId;
      }
      if (supplierId != null) {
        payload['supplier_id'] = supplierId.isEmpty ? null : supplierId;
      }
      if (minStockAlert != null) payload['min_stock_alert'] = minStockAlert;
      if (imageUrl != null) payload['image_url'] = imageUrl;
      if (isActive != null) payload['is_active'] = isActive;

      final response = await client.put(
        '/api/v1/inventory/products/$productId',
        data: payload,
      );

      final dynamic data = response.data;
      if (data == null || data is! Map) {
        throw const InventoryException('Respuesta inválida al actualizar producto.');
      }
      return Product.fromJson(data);
    } on DioException catch (e) {
      throw _mapDioError(e);
    } catch (e) {
      if (e is InventoryException) rethrow;
      throw InventoryException('Error al actualizar producto: $e');
    }
  }

  @override
  Future<String> uploadProductImage({
    required List<int> fileBytes,
    required String fileName,
  }) async {
    try {
      final formData = FormData.fromMap({
        'file': MultipartFile.fromBytes(fileBytes, filename: fileName),
      });
      final response = await client.post(
        '/api/v1/inventory/upload-image',
        data: formData,
      );
      final data = response.data;
      if (data is Map && data['url'] != null) {
        return data['url'].toString();
      }
      throw const InventoryException('Respuesta inválida al subir la imagen.');
    } on DioException catch (e) {
      throw _mapDioError(e);
    } catch (e) {
      if (e is InventoryException) rethrow;
      throw InventoryException('Error al subir imagen: $e');
    }
  }

  @override
  Future<void> adjustStock({
    required String productId,
    required String movementType,
    required int quantity,
    required String reason,
    String? warehouseId,
  }) async {
    try {
      final targetWarehouseId = warehouseId ?? await _getDefaultWarehouseId();

      final isEntry = movementType == 'MANUAL_ADJUSTMENT_IN' ||
          movementType == 'ADJUSTMENT_IN' ||
          movementType == 'PURCHASE_ENTRY' ||
          movementType == 'PURCHASE_IN';
      final isWaste = movementType == 'WASTE' || movementType == 'WASTE_MERMA';

      final String backendMovementType;
      final int signedQuantity;

      if (isEntry) {
        backendMovementType = 'ADJUSTMENT_IN';
        signedQuantity = quantity.abs();
      } else if (isWaste) {
        backendMovementType = 'WASTE_MERMA';
        signedQuantity = -quantity.abs();
      } else {
        backendMovementType = 'ADJUSTMENT_OUT';
        signedQuantity = -quantity.abs();
      }

      final payload = {
        'product_id': productId,
        'warehouse_id': targetWarehouseId,
        'quantity': signedQuantity,
        'quantity_change': signedQuantity,
        'movement_type': backendMovementType,
        'notes': reason.trim(),
        'reason': reason.trim(),
      };

      await client.post(
        '/api/v1/inventory/adjust-stock',
        data: payload,
      );
    } on DioException catch (e) {
      throw _mapDioError(e);
    } catch (e) {
      if (e is InventoryException) rethrow;
      throw InventoryException('Error al aplicar ajuste de existencias: $e');
    }
  }

  @override
  Future<void> transferStock({
    required String productId,
    required String fromWarehouseId,
    required String toWarehouseId,
    required int quantity,
    String? notes,
  }) async {
    try {
      final payload = {
        'product_id': productId,
        'from_warehouse_id': fromWarehouseId,
        'to_warehouse_id': toWarehouseId,
        'quantity': quantity.abs(),
        if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
      };

      await client.post(
        '/api/v1/inventory/transfer-stock',
        data: payload,
      );
    } on DioException catch (e) {
      throw _mapDioError(e);
    } catch (e) {
      if (e is InventoryException) rethrow;
      throw InventoryException('Error al transferir mercancía: $e');
    }
  }

  @override
  Future<PaginatedMovements> getMovements({
    required String productId,
    String? movementType,
    DateTime? dateFrom,
    DateTime? dateTo,
    int page = 1,
    int pageSize = 20,
  }) async {
    try {
      final queryParams = <String, dynamic>{
        'product_id': productId,
        'skip': (page - 1) * pageSize,
        'limit': pageSize,
      };

      if (movementType != null && movementType.isNotEmpty) {
        queryParams['movement_type'] = movementType;
        queryParams['type'] = movementType;
      }

      final response = await client.get(
        '/api/v1/inventory/movements',
        queryParameters: queryParams,
      );

      final dynamic data = response.data;
      if (data is! List) {
        throw const InventoryException('Respuesta de Kardex inválida.');
      }

      var items = data
          .map((json) =>
              InventoryMovement.fromJson(json as Map<dynamic, dynamic>))
          .toList();

      if (dateFrom != null) {
        items = items
            .where((m) => m.createdAt
                .isAfter(dateFrom.subtract(const Duration(seconds: 1))))
            .toList();
      }
      if (dateTo != null) {
        final endOfDay =
            DateTime(dateTo.year, dateTo.month, dateTo.day, 23, 59, 59);
        items = items.where((m) => m.createdAt.isBefore(endOfDay)).toList();
      }

      final total = items.length;
      final totalPages = items.length < pageSize ? page : page + 1;

      return PaginatedMovements(
        items: items,
        total: total,
        page: page,
        pageSize: pageSize,
        totalPages: totalPages < 1 ? 1 : totalPages,
      );
    } on DioException catch (e) {
      throw _mapDioError(e);
    } catch (e) {
      if (e is InventoryException) rethrow;
      throw InventoryException('Error al consultar movimientos en Kardex: $e');
    }
  }

  @override
  Future<List<Map<String, dynamic>>> getSuppliers() async {
    try {
      final response = await client.get('/api/v1/suppliers');
      final dynamic data = response.data;
      if (data is List) {
        return data
            .whereType<Map<dynamic, dynamic>>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
      return [];
    } on DioException catch (e) {
      throw _mapDioError(e);
    } catch (e) {
      if (e is InventoryException) rethrow;
      throw InventoryException('Error al consultar proveedores: $e');
    }
  }

  Exception _mapDioError(DioException e) {
    if (e.response != null) {
      final data = e.response?.data;
      if (data is Map) {
        if (data['error'] is Map && data['error']['message'] != null) {
          return InventoryException(data['error']['message'].toString());
        }
        if (data['detail'] != null) {
          return InventoryException(data['detail'].toString());
        }
      }
    }

    switch (e.response?.statusCode) {
      case 400:
        return const InventoryException('Datos de inventario inválidos.');
      case 401:
        return const InventoryException('Sesión expirada. Inicie sesión nuevamente.');
      case 403:
        return const InventoryException('No tiene permisos para gestionar inventario.');
      case 404:
        return const InventoryException('Recurso de inventario no encontrado.');
      case 409:
        return const InventoryException('Conflicto: SKU o código de barras duplicado.');
      case 422:
        return const InventoryException('Error de validación en los datos del producto.');
      case 500:
      case 502:
      case 503:
        return const InventoryException('Servidor no disponible. Intente más tarde.');
      default:
        if (e.type == DioExceptionType.connectionTimeout ||
            e.type == DioExceptionType.receiveTimeout ||
            e.type == DioExceptionType.connectionError) {
          return const InventoryException('Sin conexión con el servidor. Verifique su red.');
        }
        return InventoryException('Error de red: ${e.message ?? e.type.name}');
    }
  }
}

// ---------------------------------------------------------------------------
// Mock — mantenido para pruebas unitarias de UI y widget tests
// ---------------------------------------------------------------------------

class InventoryRepositoryMock implements InventoryRepository {
  static const _fakeDelay = Duration(milliseconds: 100);

  @override
  Future<PaginatedProducts> getProducts({
    String? query,
    String? category,
    bool lowStock = false,
    int page = 1,
    int pageSize = 20,
  }) async {
    await Future.delayed(_fakeDelay);

    var filtered = List<Product>.from(mockProducts);

    if (query != null && query.isNotEmpty) {
      final q = query.toLowerCase();
      filtered = filtered
          .where((p) =>
              p.name.toLowerCase().contains(q) ||
              p.sku.toLowerCase().contains(q) ||
              (p.barcode?.contains(q) ?? false))
          .toList();
    }

    if (category != null && category.isNotEmpty && category != 'Todos') {
      filtered = filtered.where((p) => p.category == category).toList();
    }

    if (lowStock) {
      filtered = filtered.where((p) {
        final threshold = p.minStockAlert;
        if (threshold == null) return false;
        return p.availableStock <= threshold;
      }).toList();
    }

    final total = filtered.length;
    final totalPages = (total / pageSize).ceil().clamp(1, 9999);
    final start = ((page - 1) * pageSize).clamp(0, total);
    final end = (start + pageSize).clamp(0, total);
    final pageItems = filtered.sublist(start, end);

    return PaginatedProducts(
      items: pageItems,
      total: total,
      page: page,
      pageSize: pageSize,
      totalPages: totalPages,
    );
  }

  @override
  Future<Product> getProductById(String id) async {
    await Future.delayed(_fakeDelay);
    return mockProducts.firstWhere(
      (p) => p.id == id,
      orElse: () => throw Exception('Producto no encontrado: $id'),
    );
  }

  @override
  Future<Product> createProduct({
    required String name,
    required double priceMxn,
    int stock = 0,
    String? category,
    String? barcode,
    double? costMxn,
    int? minStockAlert,
    String? imageUrl,
    String? supplierId,
  }) async {
    await Future.delayed(_fakeDelay);

    final id = 'prod-${DateTime.now().millisecondsSinceEpoch}';
    final skuSuffix = id.substring(id.length - 5).toUpperCase();

    return Product(
      id: id,
      sku: 'NEX-$skuSuffix',
      barcode: barcode,
      name: name,
      category: category ?? 'General',
      priceMxn: priceMxn,
      costMxn: costMxn ?? 0,
      stock: stock,
      reservedStock: 0,
      availableStock: stock,
      minStockAlert: minStockAlert,
      imageUrl: imageUrl,
      supplierId: supplierId,
      supplierName: supplierId != null ? 'Proveedor Demo' : null,
      isActive: true,
      isOnCatalog: false,
      createdAt: DateTime.now(),
    );
  }

  @override
  Future<Product> updateProduct({
    required String productId,
    String? name,
    double? priceMxn,
    double? costMxn,
    String? category,
    String? barcode,
    int? minStockAlert,
    String? imageUrl,
    bool? isActive,
    String? supplierId,
  }) async {
    await Future.delayed(_fakeDelay);
    final original = mockProducts.firstWhere(
      (p) => p.id == productId,
      orElse: () => throw Exception('Producto no encontrado: $productId'),
    );
    return original.copyWith(
      name: name ?? original.name,
      priceMxn: priceMxn ?? original.priceMxn,
      costMxn: costMxn ?? original.costMxn,
      category: category ?? original.category,
      barcode: barcode ?? original.barcode,
      minStockAlert: minStockAlert ?? original.minStockAlert,
      imageUrl: imageUrl ?? original.imageUrl,
      isActive: isActive ?? original.isActive,
      supplierId: supplierId ?? original.supplierId,
    );
  }

  @override
  Future<String> uploadProductImage({
    required List<int> fileBytes,
    required String fileName,
  }) async {
    await Future.delayed(_fakeDelay);
    return '/uploads/images/mock_$fileName';
  }

  @override
  Future<void> adjustStock({
    required String productId,
    required String movementType,
    required int quantity,
    required String reason,
    String? warehouseId,
  }) async {
    await Future.delayed(_fakeDelay);
  }

  @override
  Future<void> transferStock({
    required String productId,
    required String fromWarehouseId,
    required String toWarehouseId,
    required int quantity,
    String? notes,
  }) async {
    await Future.delayed(_fakeDelay);
  }

  @override
  Future<PaginatedMovements> getMovements({
    required String productId,
    String? movementType,
    DateTime? dateFrom,
    DateTime? dateTo,
    int page = 1,
    int pageSize = 20,
  }) async {
    await Future.delayed(_fakeDelay);

    final allMovements = _generateMockMovements(productId);

    var filtered = movementType != null
        ? allMovements
            .where((m) => m.movementType.apiCode == movementType)
            .toList()
        : allMovements;

    if (dateFrom != null) {
      filtered = filtered
          .where((m) => m.createdAt.isAfter(
                dateFrom.subtract(const Duration(seconds: 1)),
              ))
          .toList();
    }
    if (dateTo != null) {
      final endOfDay =
          DateTime(dateTo.year, dateTo.month, dateTo.day, 23, 59, 59);
      filtered = filtered.where((m) => m.createdAt.isBefore(endOfDay)).toList();
    }

    final total = filtered.length;
    final totalPages = (total / pageSize).ceil().clamp(1, 9999);
    final start = ((page - 1) * pageSize).clamp(0, total);
    final end = (start + pageSize).clamp(0, total);

    return PaginatedMovements(
      items: filtered.sublist(start, end),
      total: total,
      page: page,
      pageSize: pageSize,
      totalPages: totalPages,
    );
  }

  @override
  Future<List<Map<String, dynamic>>> getSuppliers() async {
    await Future.delayed(_fakeDelay);
    return [
      {'id': 'supp-1', 'name': 'Coca-Cola FEMSA México'},
      {'id': 'supp-2', 'name': 'Grupo Bimbo S.A.B.'},
      {'id': 'supp-3', 'name': 'Sabritas / PepsiCo Alimentos'},
      {'id': 'supp-4', 'name': 'Lala Operaciones México'},
    ];
  }

  List<InventoryMovement> _generateMockMovements(String productId) {
    final now = DateTime.now();
    return [
      _mov('mv-01', productId, MovementType.saleOut, -3, 60, 57,
          now.subtract(const Duration(hours: 2)),
          notes: 'Folio NV-2026-001547'),
      _mov('mv-02', productId, MovementType.manualAdjustmentIn, 12, 48, 60,
          now.subtract(const Duration(days: 1)),
          notes: 'Conteo físico mensual'),
      _mov('mv-03', productId, MovementType.transferOut, -10, 58, 48,
          now.subtract(const Duration(days: 2)),
          notes: 'Bodega → Mostrador'),
      _mov('mv-04', productId, MovementType.purchaseIn, 24, 34, 58,
          now.subtract(const Duration(days: 3)),
          notes: 'OC-2026-000045'),
      _mov('mv-05', productId, MovementType.saleOut, -5, 39, 34,
          now.subtract(const Duration(days: 3)),
          notes: 'Folio NV-2026-001532'),
      _mov('mv-06', productId, MovementType.waste, -2, 41, 39,
          now.subtract(const Duration(days: 4)),
          notes: 'Producto vencido'),
      _mov('mv-07', productId, MovementType.transferIn, 8, 33, 41,
          now.subtract(const Duration(days: 5)),
          notes: 'Mostrador → Bodega'),
      _mov('mv-08', productId, MovementType.saleOut, -4, 37, 33,
          now.subtract(const Duration(days: 6))),
      _mov('mv-09', productId, MovementType.customerReturn, 2, 35, 37,
          now.subtract(const Duration(days: 7)),
          notes: 'Devolución — producto en buen estado'),
      _mov('mv-10', productId, MovementType.manualAdjustmentOut, -3, 38, 35,
          now.subtract(const Duration(days: 8)),
          notes: 'Corrección de inventario'),
    ];
  }

  InventoryMovement _mov(
    String id,
    String productId,
    MovementType type,
    int quantity,
    int stockBefore,
    int stockAfter,
    DateTime createdAt, {
    String? notes,
  }) {
    return InventoryMovement(
      id: id,
      productId: productId,
      warehouseId: 'wh-001',
      movementType: type,
      quantity: quantity,
      stockBefore: stockBefore,
      stockAfter: stockAfter,
      unitCostMxn: 0,
      createdAt: createdAt,
      notes: notes,
    );
  }
}

// ---------------------------------------------------------------------------
// Provider conectado al Repositorio Real de Inventario
// ---------------------------------------------------------------------------

final inventoryRepositoryProvider = Provider<InventoryRepository>(
  (ref) => InventoryRepositoryImpl(
    client: ref.watch(dioClientProvider),
  ),
);
