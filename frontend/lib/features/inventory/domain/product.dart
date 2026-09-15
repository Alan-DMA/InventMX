/// Modelo de dominio — Producto de Inventario
///
/// Anclado al schema `Product` de docs/api/components.yaml y backend ProductResponse.
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

  factory Product.fromJson(Map<dynamic, dynamic> json) {
    // Extracción tolerante y segura de existencias
    final rawStock = json['total_stock'] ?? json['stock'] ?? 0;
    final int stockVal = rawStock is num ? rawStock.toInt() : (int.tryParse(rawStock.toString()) ?? 0);

    final rawReserved = json['reserved_stock'] ?? 0;
    final int resStockVal = rawReserved is num ? rawReserved.toInt() : (int.tryParse(rawReserved.toString()) ?? 0);

    final rawAvail = json['available_stock'] ?? json['total_stock'] ?? json['stock'] ?? 0;
    final int availStockVal = rawAvail is num ? rawAvail.toInt() : (int.tryParse(rawAvail.toString()) ?? 0);

    // Umbral de stock mínimo
    int? minAlertVal;
    if (json['min_stock_alert'] != null) {
      final rawAlert = json['min_stock_alert'];
      minAlertVal = rawAlert is num ? rawAlert.toInt() : int.tryParse(rawAlert.toString());
    }

    // Extracción de warehouse_id directo o desde lista de stocks
    String? whId = json['warehouse_id']?.toString();
    if (whId == null && json['stocks'] is List && (json['stocks'] as List).isNotEmpty) {
      final firstStock = (json['stocks'] as List).first;
      if (firstStock is Map && firstStock['warehouse_id'] != null) {
        whId = firstStock['warehouse_id'].toString();
      }
    }

    // Precios y costos
    final rawPrice = json['price_mxn'] ?? 0;
    final double priceVal = rawPrice is num ? rawPrice.toDouble() : (double.tryParse(rawPrice.toString()) ?? 0.0);

    final rawCost = json['cost_mxn'] ?? 0;
    final double costVal = rawCost is num ? rawCost.toDouble() : (double.tryParse(rawCost.toString()) ?? 0.0);

    double? costUsd;
    if (json['cost_usd_import'] != null) {
      final rawUsd = json['cost_usd_import'];
      costUsd = rawUsd is num ? rawUsd.toDouble() : double.tryParse(rawUsd.toString());
    }

    // Fechas
    DateTime parsedDate;
    if (json['created_at'] != null) {
      parsedDate = DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now();
    } else {
      parsedDate = DateTime.now();
    }

    return Product(
      id: (json['id'] ?? '').toString(),
      sku: (json['sku'] ?? '').toString(),
      barcode: json['barcode']?.toString(),
      name: (json['name'] ?? '').toString(),
      category: (json['category_name'] ?? json['category'])?.toString() ?? 'General',
      priceMxn: priceVal,
      costMxn: costVal,
      costUsdImport: costUsd,
      stock: stockVal,
      reservedStock: resStockVal,
      availableStock: availStockVal,
      minStockAlert: minAlertVal,
      imageUrl: json['image_url']?.toString(),
      warehouseId: whId,
      isActive: json['is_active'] is bool ? json['is_active'] as bool : (json['is_active']?.toString() != 'false'),
      isOnCatalog: json['is_on_catalog'] is bool ? json['is_on_catalog'] as bool : (json['is_on_catalog']?.toString() == 'true'),
      createdAt: parsedDate,
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
