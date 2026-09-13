// DTOs fuertemente tipados para Métricas de Inventario, Valuación y Rotación (RF-20)
// Cumplimiento estricto de .agents/AGENTS.md:
// 1. Moneda base en Pesos Mexicanos ($ MXN).
// 2. Prohibición de mapas crudos (Map<String, dynamic>) en capas de UI/Negocio.
// 3. Serialización y deserialización a prueba de nulos.
// 4. Comentarios exhaustivos línea por línea.

/// Valuación financiera de existencias en almacén en Pesos Mexicanos ($ MXN).
class InventoryValuationDto {
  /// Total de artículos/SKUs activos en el catálogo de productos.
  final int totalActiveSkus;
  /// Total de unidades físicas en inventario.
  final double totalUnitsInStock;
  /// Valoración total del inventario a precio de costo en $ MXN.
  final double totalInventoryCostMxn;
  /// Valoración total del inventario a precio de venta al público en $ MXN.
  final double totalInventoryRetailMxn;
  /// Utilidad bruta potencial en $ MXN (Retail - Cost).
  final double potentialGrossProfitMxn;

  /// Constructor inmutable de valuación de inventario.
  const InventoryValuationDto({
    required this.totalActiveSkus,
    required this.totalUnitsInStock,
    required this.totalInventoryCostMxn,
    required this.totalInventoryRetailMxn,
    required this.potentialGrossProfitMxn,
  });

  /// Deserialización segura desde JSON.
  factory InventoryValuationDto.fromJson(Map<String, dynamic> json) {
    return InventoryValuationDto(
      totalActiveSkus: json['total_active_skus'] as int? ?? 0,
      totalUnitsInStock: (json['total_units_in_stock'] as num?)?.toDouble() ?? 0.0,
      totalInventoryCostMxn: (json['total_inventory_cost_mxn'] as num?)?.toDouble() ?? 0.0,
      totalInventoryRetailMxn: (json['total_inventory_retail_mxn'] as num?)?.toDouble() ?? 0.0,
      potentialGrossProfitMxn: (json['potential_gross_profit_mxn'] as num?)?.toDouble() ?? 0.0,
    );
  }

  /// Serialización segura a JSON.
  Map<String, dynamic> toJson() {
    return {
      'total_active_skus': totalActiveSkus,
      'total_units_in_stock': totalUnitsInStock,
      'total_inventory_cost_mxn': totalInventoryCostMxn,
      'total_inventory_retail_mxn': totalInventoryRetailMxn,
      'potential_gross_profit_mxn': potentialGrossProfitMxn,
    };
  }
}

/// Métrica de producto más vendido en el periodo.
class TopSellingProductDto {
  /// Identificador único del producto.
  final String productId;
  /// Nombre comercial del producto.
  final String productName;
  /// Código SKU o de barras.
  final String sku;
  /// Unidades o piezas vendidas.
  final double unitsSold;
  /// Ingresos brutos generados en $ MXN.
  final double revenueMxn;
  /// Utilidad bruta generada en $ MXN.
  final double profitMxn;

  /// Constructor inmutable de producto top.
  const TopSellingProductDto({
    required this.productId,
    required this.productName,
    required this.sku,
    required this.unitsSold,
    required this.revenueMxn,
    required this.profitMxn,
  });

  /// Deserialización segura desde JSON.
  factory TopSellingProductDto.fromJson(Map<String, dynamic> json) {
    return TopSellingProductDto(
      productId: json['product_id'] as String? ?? '',
      productName: json['product_name'] as String? ?? 'Producto',
      sku: json['sku'] as String? ?? '',
      unitsSold: (json['units_sold'] as num?)?.toDouble() ?? 0.0,
      revenueMxn: (json['revenue_mxn'] as num?)?.toDouble() ?? 0.0,
      profitMxn: (json['profit_mxn'] as num?)?.toDouble() ?? 0.0,
    );
  }

  /// Serialización a JSON.
  Map<String, dynamic> toJson() {
    return {
      'product_id': productId,
      'product_name': productName,
      'sku': sku,
      'units_sold': unitsSold,
      'revenue_mxn': revenueMxn,
      'profit_mxn': profitMxn,
    };
  }
}

/// Producto en nivel crítico de existencias (bajo stock).
class CriticalStockProductDto {
  /// Identificador único del producto.
  final String productId;
  /// Nombre comercial del producto.
  final String productName;
  /// Código SKU o de barras.
  final String sku;
  /// Existencias físicas actuales.
  final double currentStock;
  /// Umbral mínimo de advertencia configurado.
  final double minStock;
  /// Bandera que indica si el stock está totalmente en cero o negativo.
  final bool isOutOfStock;

  /// Constructor inmutable de producto crítico.
  const CriticalStockProductDto({
    required this.productId,
    required this.productName,
    required this.sku,
    required this.currentStock,
    required this.minStock,
    required this.isOutOfStock,
  });

  /// Deserialización segura desde JSON.
  factory CriticalStockProductDto.fromJson(Map<String, dynamic> json) {
    return CriticalStockProductDto(
      productId: json['product_id'] as String? ?? '',
      productName: json['product_name'] as String? ?? 'Producto',
      sku: json['sku'] as String? ?? '',
      currentStock: (json['current_stock'] as num?)?.toDouble() ?? 0.0,
      minStock: (json['min_stock'] as num?)?.toDouble() ?? 0.0,
      isOutOfStock: json['is_out_of_stock'] as bool? ?? false,
    );
  }

  /// Serialización a JSON.
  Map<String, dynamic> toJson() {
    return {
      'product_id': productId,
      'product_name': productName,
      'sku': sku,
      'current_stock': currentStock,
      'min_stock': minStock,
      'is_out_of_stock': isOutOfStock,
    };
  }
}

/// DTO de respuesta para el Diagnóstico Consolidado de Inventario y Rotación (RF-20).
class InventoryHealthDto {
  /// Valuación total del inventario.
  final InventoryValuationDto valuation;
  /// Top de productos más vendidos.
  final List<TopSellingProductDto> topSellingProducts;
  /// Artículos en nivel crítico de reorden.
  final List<CriticalStockProductDto> criticalStockProducts;

  /// Constructor inmutable de diagnóstico de inventario.
  const InventoryHealthDto({
    required this.valuation,
    required this.topSellingProducts,
    required this.criticalStockProducts,
  });

  /// Deserialización segura desde JSON.
  factory InventoryHealthDto.fromJson(Map<String, dynamic> json) {
    return InventoryHealthDto(
      valuation: json['valuation'] != null
          ? InventoryValuationDto.fromJson(json['valuation'] as Map<String, dynamic>)
          : const InventoryValuationDto(
              totalActiveSkus: 0,
              totalUnitsInStock: 0.0,
              totalInventoryCostMxn: 0.0,
              totalInventoryRetailMxn: 0.0,
              potentialGrossProfitMxn: 0.0,
            ),
      topSellingProducts: (json['top_selling_products'] as List<dynamic>?)
              ?.map((e) => TopSellingProductDto.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      criticalStockProducts: (json['critical_stock_products'] as List<dynamic>?)
              ?.map((e) => CriticalStockProductDto.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  /// Serialización segura a JSON.
  Map<String, dynamic> toJson() {
    return {
      'valuation': valuation.toJson(),
      'top_selling_products': topSellingProducts.map((p) => p.toJson()).toList(),
      'critical_stock_products': criticalStockProducts.map((p) => p.toJson()).toList(),
    };
  }
}
