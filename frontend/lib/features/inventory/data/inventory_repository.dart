import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/inventory_movement.dart';
import '../domain/product.dart';
import 'inventory_mock_data.dart';

// ---------------------------------------------------------------------------
// Modelos auxiliares de respuesta
// ---------------------------------------------------------------------------

/// Respuesta paginada — espejo de PaginationMeta del API.
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

// ---------------------------------------------------------------------------
// Contrato
// ---------------------------------------------------------------------------

/// Respuesta paginada de movimientos Kardex.
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
// Contrato
// ---------------------------------------------------------------------------

abstract class InventoryRepository {
  /// GET /inventory/products
  /// Parámetros alineados con docs/api/inventory.yaml
  Future<PaginatedProducts> getProducts({
    String? query,
    String? category,
    bool lowStock = false,
    int page = 1,
    int pageSize = 20,
  });

  /// GET /inventory/products/{id}
  Future<Product> getProductById(String id);

  /// POST /inventory/products
  Future<Product> createProduct({
    required String name,
    required double priceMxn,
    int stock = 0,
  });

  /// PATCH /inventory/products/{id}
  /// Actualización parcial — solo envía los campos que cambiaron.
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
  });

  /// POST /inventory/products/{id}/adjust-stock
  Future<void> adjustStock({
    required String productId,
    required String movementType,
    required int quantity,
    required String reason,
  });

  /// POST /inventory/products/{id}/transfer
  Future<void> transferStock({
    required String productId,
    required String fromWarehouseId,
    required String toWarehouseId,
    required int quantity,
    String? notes,
  });

  /// GET /inventory/products/{id}/movements
  /// Parámetros alineados con docs/api/inventory.yaml
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
// Mock — activo hasta que Alan complete Tarea 3.1 (backend inventario)
// ---------------------------------------------------------------------------

class InventoryRepositoryMock implements InventoryRepository {
  /// Simula latencia de red para QA visual de estados loading.
  static const _fakeDelay = Duration(milliseconds: 600);

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

    // Filtro fuzzy por texto — simula pg_trgm del backend
    if (query != null && query.isNotEmpty) {
      final q = query.toLowerCase();
      filtered = filtered
          .where((p) =>
              p.name.toLowerCase().contains(q) ||
              p.sku.toLowerCase().contains(q) ||
              (p.barcode?.contains(q) ?? false))
          .toList();
    }

    // Filtro por categoría exacta
    if (category != null && category.isNotEmpty) {
      filtered = filtered.where((p) => p.category == category).toList();
    }

    // Filtro stock bajo — simula ?low_stock=true
    if (lowStock) {
      filtered = filtered.where((p) {
        final threshold = p.minStockAlert;
        if (threshold == null) return false;
        return p.availableStock <= threshold;
      }).toList();
    }

    // Paginación
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
  }) async {
    await Future.delayed(_fakeDelay);

    // Genera un ID y SKU simulados — el backend real los autogenera
    final id = 'prod-${DateTime.now().millisecondsSinceEpoch}';
    final skuSuffix = id.substring(id.length - 5).toUpperCase();

    return Product(
      id: id,
      sku: 'NEX-$skuSuffix',
      name: name,
      category: 'General',
      priceMxn: priceMxn,
      costMxn: 0,
      stock: stock,
      reservedStock: 0,
      availableStock: stock,
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
  }) async {
    await Future.delayed(_fakeDelay);
    // El backend real aplica el PATCH y retorna el producto actualizado.
    // El mock busca el producto en la lista, aplica los cambios y lo retorna.
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
    );
  }

  @override
  Future<void> adjustStock({
    required String productId,
    required String movementType,
    required int quantity,
    required String reason,
  }) async {
    await Future.delayed(_fakeDelay);
    // El backend actualiza el stock y registra en Kardex.
    // El mock simula éxito silencioso — el provider actualiza el estado local.
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
    // Idem — mock simula éxito, el provider actualiza el estado local.
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

    // Genera movimientos mock representativos para QA visual
    final allMovements = _generateMockMovements(productId);

    // Filtra por tipo si se especificó
    var filtered = movementType != null
        ? allMovements
            .where((m) => m.movementType.apiCode == movementType)
            .toList()
        : allMovements;

    // Filtra por rango de fechas
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

  /// Genera una lista de 25 movimientos mock variados para QA visual.
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
      _mov('mv-11', productId, MovementType.purchaseIn, 20, 18, 38,
          now.subtract(const Duration(days: 10)),
          notes: 'OC-2026-000031'),
      _mov('mv-12', productId, MovementType.saleOut, -6, 24, 18,
          now.subtract(const Duration(days: 11))),
      _mov('mv-13', productId, MovementType.saleOut, -4, 28, 24,
          now.subtract(const Duration(days: 12))),
      _mov('mv-14', productId, MovementType.transferOut, -5, 33, 28,
          now.subtract(const Duration(days: 13)),
          notes: 'Reabastecimiento mostrador'),
      _mov('mv-15', productId, MovementType.purchaseIn, 15, 18, 33,
          now.subtract(const Duration(days: 14)),
          notes: 'OC-2026-000018'),
      _mov('mv-16', productId, MovementType.saleOut, -3, 21, 18,
          now.subtract(const Duration(days: 15))),
      _mov('mv-17', productId, MovementType.manualAdjustmentIn, 5, 16, 21,
          now.subtract(const Duration(days: 17)),
          notes: 'Conteo de ajuste semestral'),
      _mov('mv-18', productId, MovementType.waste, -1, 17, 16,
          now.subtract(const Duration(days: 18)),
          notes: 'Caja dañada'),
      _mov('mv-19', productId, MovementType.saleOut, -4, 21, 17,
          now.subtract(const Duration(days: 19))),
      _mov('mv-20', productId, MovementType.purchaseIn, 12, 9, 21,
          now.subtract(const Duration(days: 20)),
          notes: 'OC-2026-000008'),
      _mov('mv-21', productId, MovementType.saleOut, -3, 12, 9,
          now.subtract(const Duration(days: 22))),
      _mov('mv-22', productId, MovementType.transferIn, 6, 6, 12,
          now.subtract(const Duration(days: 23)),
          notes: 'Reingreso desde bodega'),
      _mov('mv-23', productId, MovementType.saleOut, -2, 8, 6,
          now.subtract(const Duration(days: 25))),
      _mov('mv-24', productId, MovementType.purchaseIn, 8, 0, 8,
          now.subtract(const Duration(days: 28)),
          notes: 'OC-2026-000001'),
      _mov('mv-25', productId, MovementType.initialStock, 0, 0, 0,
          now.subtract(const Duration(days: 30)),
          notes: 'Stock inicial al registrar el producto'),
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
// Provider
// ---------------------------------------------------------------------------

final inventoryRepositoryProvider = Provider<InventoryRepository>(
  (_) => InventoryRepositoryMock(),
);
