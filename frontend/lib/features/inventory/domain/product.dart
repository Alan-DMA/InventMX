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
    this.supplierId,
    this.supplierName,
    this.suggestedMaxPriceMxn,
    this.suggestedMaxPriceSource,
    int? totalStock,
    this.stockByWarehouse = const {},
  }) : totalStock = totalStock ?? stock;

  // --- Identificación ---
  final String id;
  final String sku;
  final String? barcode;

  // --- Descripción ---
  final String name;
  final String category;

  // --- Proveedor ---
  final String? supplierId;
  final String? supplierName;

  // --- Precios en MXN (Constitución Art. I, 1.2.4) ---
  final double priceMxn;
  final double costMxn;
  final double? costUsdImport;

  /// Precio máximo sugerido en MXN — sólo viene poblado en el detalle
  /// (`GET /inventory/products/{id}`), nunca en el listado (decisión de
  /// Eduardo, Sep 2026: la elasticidad histórica es cara de calcular por
  /// producto, no se corre en cada carga de la lista).
  final double? suggestedMaxPriceMxn;

  /// 'historical' (elasticidad de la demanda) o 'margin_fallback' (margen
  /// máximo del comercio) — de dónde salió [suggestedMaxPriceMxn].
  final String? suggestedMaxPriceSource;

  // --- Stock ---
  /// Existencias del almacén de la consulta ([warehouseId]) — lo que se
  /// puede vender aquí (aislamiento por almacén, D23). Si la consulta fue de
  /// todos los almacenes, coincide con [totalStock].
  final int stock;

  /// Suma de todos los almacenes (`total_stock`, W2).
  final int totalStock;

  /// Desglose `warehouse_id → existencias` (`stocks[]` del backend).
  final Map<String, int> stockByWarehouse;
  final int reservedStock;
  final int availableStock;
  final int? minStockAlert;

  // --- Imagen y almacén ---
  final String? imageUrl;

  /// Almacén al que se refiere [stock]. El backend lo devuelve cuando la
  /// consulta tuvo alcance de almacén; si no, se toma el del primer renglón
  /// de `stocks[]` (comportamiento previo).
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

  /// Almacenes distintos de [warehouseId] que sí tienen existencias —
  /// alimenta el aviso "hay N en Bodega" cuando aquí hay cero (D24).
  Map<String, int> get stockElsewhere => {
        for (final entry in stockByWarehouse.entries)
          if (entry.key != warehouseId && entry.value > 0) entry.key: entry.value,
      };

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
    int parseInt(dynamic value, [int defaultValue = 0]) {
      if (value == null) return defaultValue;
      if (value is num) return value.round();
      final s = value.toString().trim().replaceAll(',', '.');
      final asDouble = double.tryParse(s);
      if (asDouble != null) return asDouble.round();
      return defaultValue;
    }

    int? parseNullableInt(dynamic value) {
      if (value == null) return null;
      if (value is num) return value.round();
      final s = value.toString().trim().replaceAll(',', '.');
      final asDouble = double.tryParse(s);
      return asDouble?.round();
    }

    double parseDouble(dynamic value, [double defaultValue = 0.0]) {
      if (value == null) return defaultValue;
      if (value is num) return value.toDouble();
      final s = value.toString().trim().replaceAll(',', '.');
      return double.tryParse(s) ?? defaultValue;
    }

    double? parseNullableDouble(dynamic value) {
      if (value == null) return null;
      if (value is num) return value.toDouble();
      final s = value.toString().trim().replaceAll(',', '.');
      return double.tryParse(s);
    }

    // Almacén de la consulta: sólo lo manda el backend cuando hubo alcance
    final String? scopeWarehouseId = json['warehouse_id']?.toString();
    final List stockRows = json['stocks'] is List ? json['stocks'] as List : const [];

    // Desglose por almacén
    final byWarehouse = <String, int>{};
    for (final row in stockRows) {
      if (row is Map && row['warehouse_id'] != null) {
        final key = row['warehouse_id'].toString();
        byWarehouse[key] = (byWarehouse[key] ?? 0) + parseInt(row['current_stock'], 0);
      }
    }

    // Extracción tolerante y segura de existencias: primero las del almacén
    // de la consulta (`warehouse_stock`), luego la suma (`total_stock`)
    final rawStock = json['warehouse_stock'] ??
        json['total_stock'] ??
        json['stock'] ??
        json['current_stock'] ??
        json['available_stock'] ??
        json['stock_available'];
    final int stockVal = parseInt(rawStock, 0);
    final int totalStockVal = json['total_stock'] != null
        ? parseInt(json['total_stock'], 0)
        : stockVal;

    int resStockVal = parseInt(json['reserved_stock'] ?? json['stock_reserved'], 0);
    if (resStockVal == 0 && stockRows.isNotEmpty) {
      for (final s in stockRows) {
        if (s is Map && s['reserved_stock'] != null) {
          // Con alcance, sólo lo apartado en ese almacén resta a lo vendible
          if (scopeWarehouseId != null &&
              s['warehouse_id']?.toString() != scopeWarehouseId) {
            continue;
          }
          resStockVal += parseInt(s['reserved_stock'], 0);
        }
      }
    }

    final rawAvail = json['available_stock'] ?? json['stock_available'];
    final int availStockVal = rawAvail != null
        ? parseInt(rawAvail, 0)
        : (stockVal - resStockVal).clamp(0, 999999999);

    // Umbral de stock mínimo
    final int? minAlertVal = parseNullableInt(json['min_stock_alert']);

    // Extracción de warehouse_id directo o desde lista de stocks
    String? whId = scopeWarehouseId;
    if (whId == null && stockRows.isNotEmpty) {
      final firstStock = stockRows.first;
      if (firstStock is Map && firstStock['warehouse_id'] != null) {
        whId = firstStock['warehouse_id'].toString();
      }
    }

    // Precios y costos
    final double priceVal = parseDouble(json['price_mxn'] ?? json['price_usd'], 0.0);
    final double costVal = parseDouble(json['cost_mxn'] ?? json['cost_usd'], 0.0);
    final double? costUsd = parseNullableDouble(json['cost_usd_import']);

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
      totalStock: totalStockVal,
      stockByWarehouse: byWarehouse,
      reservedStock: resStockVal,
      availableStock: availStockVal,
      minStockAlert: minAlertVal,
      imageUrl: json['image_url']?.toString(),
      warehouseId: whId,
      supplierId: json['supplier_id']?.toString(),
      supplierName: json['supplier_name']?.toString(),
      isActive: json['is_active'] is bool ? json['is_active'] as bool : (json['is_active']?.toString() != 'false'),
      isOnCatalog: json['is_on_catalog'] is bool ? json['is_on_catalog'] as bool : (json['is_on_catalog']?.toString() == 'true'),
      createdAt: parsedDate,
      suggestedMaxPriceMxn: parseNullableDouble(json['suggested_max_price_mxn']),
      suggestedMaxPriceSource: json['suggested_max_price_source']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'sku': sku,
        'barcode': barcode,
        'name': name,
        'category': category,
        'supplier_id': supplierId,
        'supplier_name': supplierName,
        'price_mxn': priceMxn,
        'cost_mxn': costMxn,
        'cost_usd_import': costUsdImport,
        'warehouse_stock': stock,
        'total_stock': totalStock,
        'stocks': [
          for (final entry in stockByWarehouse.entries)
            {'warehouse_id': entry.key, 'current_stock': entry.value},
        ],
        'reserved_stock': reservedStock,
        'available_stock': availableStock,
        'min_stock_alert': minStockAlert,
        'image_url': imageUrl,
        'warehouse_id': warehouseId,
        'is_active': isActive,
        'is_on_catalog': isOnCatalog,
        'created_at': createdAt.toIso8601String(),
        'suggested_max_price_mxn': suggestedMaxPriceMxn,
        'suggested_max_price_source': suggestedMaxPriceSource,
      };

  Product copyWith({
    String? id,
    String? sku,
    String? barcode,
    String? name,
    String? category,
    String? supplierId,
    String? supplierName,
    double? priceMxn,
    double? costMxn,
    double? costUsdImport,
    int? stock,
    int? totalStock,
    Map<String, int>? stockByWarehouse,
    int? reservedStock,
    int? availableStock,
    int? minStockAlert,
    String? imageUrl,
    String? warehouseId,
    bool? isActive,
    bool? isOnCatalog,
    DateTime? createdAt,
    double? suggestedMaxPriceMxn,
    String? suggestedMaxPriceSource,
  }) {
    return Product(
      id: id ?? this.id,
      sku: sku ?? this.sku,
      barcode: barcode ?? this.barcode,
      name: name ?? this.name,
      category: category ?? this.category,
      supplierId: supplierId ?? this.supplierId,
      supplierName: supplierName ?? this.supplierName,
      priceMxn: priceMxn ?? this.priceMxn,
      costMxn: costMxn ?? this.costMxn,
      costUsdImport: costUsdImport ?? this.costUsdImport,
      stock: stock ?? this.stock,
      totalStock: totalStock ?? this.totalStock,
      stockByWarehouse: stockByWarehouse ?? this.stockByWarehouse,
      reservedStock: reservedStock ?? this.reservedStock,
      availableStock: availableStock ?? this.availableStock,
      minStockAlert: minStockAlert ?? this.minStockAlert,
      imageUrl: imageUrl ?? this.imageUrl,
      warehouseId: warehouseId ?? this.warehouseId,
      isActive: isActive ?? this.isActive,
      isOnCatalog: isOnCatalog ?? this.isOnCatalog,
      createdAt: createdAt ?? this.createdAt,
      suggestedMaxPriceMxn: suggestedMaxPriceMxn ?? this.suggestedMaxPriceMxn,
      suggestedMaxPriceSource:
          suggestedMaxPriceSource ?? this.suggestedMaxPriceSource,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is Product && other.id == id);

  @override
  int get hashCode => id.hashCode;
}
