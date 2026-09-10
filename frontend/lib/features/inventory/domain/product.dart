/// Modelo de dominio — Producto de Inventario
///
/// Anclado al schema `Product` de docs/api/components.yaml.
/// Constitución Art. I (1.2.4): todos los montos en MXN.
library;

// ---------------------------------------------------------------------------
// Enum de estado de stock — determina el semáforo visual en la lista
// ---------------------------------------------------------------------------

enum StockStatus {
  /// available_stock == 0
  outOfStock,

  /// available_stock > 0 && available_stock <= min_stock_alert
  lowStock,

  /// available_stock > min_stock_alert (o min_stock_alert es null)
  inStock,
}

// ---------------------------------------------------------------------------
// Modelo principal
// ---------------------------------------------------------------------------

class Product {
  const Product({
    required this.id,
    required this.sku,
    required this.name,
    required this.category,
    required this.priceMxn,
    required this.costMxn,
    required this.stock,
    required this.reservedStock,
    required this.availableStock,
    required this.isActive,
    required this.isOnCatalog,
    required this.createdAt,
    this.barcode,
    this.minStockAlert,
    this.imageUrl,
    this.warehouseId,
    this.costUsdImport,
  });

  // --- Identificación ---
  final String id;
  final String sku;
  final String? barcode;

  // --- Descripción ---
  final String name;
  final String category;

  // --- Precios en MXN (Constitución Art. I, 1.2.4) ---
  final double priceMxn;
  final double costMxn;
  final double? costUsdImport;

  // --- Stock ---
  final int stock;
  final int reservedStock;
  final int availableStock;
  final int? minStockAlert;

  // --- Imagen y almacén ---
  final String? imageUrl;
  final String? warehouseId;

  // --- Flags ---
  final bool isActive;
  final bool isOnCatalog;

  // --- Auditoría ---
  final DateTime createdAt;

  // ---------------------------------------------------------------------------
  // Lógica de dominio
  // ---------------------------------------------------------------------------

  /// Semáforo de stock calculado en el cliente.
  /// El backend ya devuelve `available_stock`, el cliente solo clasifica.
  StockStatus get stockStatus {
    if (availableStock <= 0) return StockStatus.outOfStock;
    final threshold = minStockAlert;
    if (threshold != null && availableStock <= threshold) {
      return StockStatus.lowStock;
    }
    return StockStatus.inStock;
  }

  /// Margen de ganancia en porcentaje.
  /// Retorna null si cost_mxn es 0 (costo no registrado)
  /// o si price_mxn es 0 (evita división por cero).
  double? get profitMargin {
    if (priceMxn <= 0 || costMxn <= 0) return null;
    return ((priceMxn - costMxn) / priceMxn) * 100;
  }

  // ---------------------------------------------------------------------------
  // Serialización — alineada con el schema API (snake_case → camelCase)
  // ---------------------------------------------------------------------------

  factory Product.fromJson(Map<String, dynamic> json) {
    return Product(
      id: json['id'] as String,
      sku: json['sku'] as String,
      barcode: json['barcode'] as String?,
      name: json['name'] as String,
      category: (json['category'] as String?) ?? 'General',
      priceMxn: (json['price_mxn'] as num).toDouble(),
      costMxn: (json['cost_mxn'] as num? ?? 0).toDouble(),
      costUsdImport: (json['cost_usd_import'] as num?)?.toDouble(),
      stock: (json['stock'] as int?) ?? 0,
      reservedStock: (json['reserved_stock'] as int?) ?? 0,
      availableStock: (json['available_stock'] as int?) ?? 0,
      minStockAlert: json['min_stock_alert'] as int?,
      imageUrl: json['image_url'] as String?,
      warehouseId: json['warehouse_id'] as String?,
      isActive: (json['is_active'] as bool?) ?? true,
      isOnCatalog: (json['is_on_catalog'] as bool?) ?? false,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'sku': sku,
        'barcode': barcode,
        'name': name,
        'category': category,
        'price_mxn': priceMxn,
        'cost_mxn': costMxn,
        'cost_usd_import': costUsdImport,
        'stock': stock,
        'reserved_stock': reservedStock,
        'available_stock': availableStock,
        'min_stock_alert': minStockAlert,
        'image_url': imageUrl,
        'warehouse_id': warehouseId,
        'is_active': isActive,
        'is_on_catalog': isOnCatalog,
        'created_at': createdAt.toIso8601String(),
      };

  Product copyWith({
    String? id,
    String? sku,
    String? barcode,
    String? name,
    String? category,
    double? priceMxn,
    double? costMxn,
    double? costUsdImport,
    int? stock,
    int? reservedStock,
    int? availableStock,
    int? minStockAlert,
    String? imageUrl,
    String? warehouseId,
    bool? isActive,
    bool? isOnCatalog,
    DateTime? createdAt,
  }) {
    return Product(
      id: id ?? this.id,
      sku: sku ?? this.sku,
      barcode: barcode ?? this.barcode,
      name: name ?? this.name,
      category: category ?? this.category,
      priceMxn: priceMxn ?? this.priceMxn,
      costMxn: costMxn ?? this.costMxn,
      costUsdImport: costUsdImport ?? this.costUsdImport,
      stock: stock ?? this.stock,
      reservedStock: reservedStock ?? this.reservedStock,
      availableStock: availableStock ?? this.availableStock,
      minStockAlert: minStockAlert ?? this.minStockAlert,
      imageUrl: imageUrl ?? this.imageUrl,
      warehouseId: warehouseId ?? this.warehouseId,
      isActive: isActive ?? this.isActive,
      isOnCatalog: isOnCatalog ?? this.isOnCatalog,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is Product && other.id == id);

  @override
  int get hashCode => id.hashCode;
}
