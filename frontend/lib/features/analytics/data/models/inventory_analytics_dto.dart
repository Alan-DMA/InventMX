// DTOs fuertemente tipados para Métricas de Inventario, Valuación y Rotación (RF-20)
// Cumplimiento estricto de .agents/AGENTS.md:
// 1. Moneda base en Pesos Mexicanos ($ MXN).
// 2. Prohibición de mapas crudos (Map<String, dynamic>) en capas de UI/Negocio.
// 3. Serialización y deserialización a prueba de nulos.
// 4. Comentarios exhaustivos línea por línea.

import 'json_number.dart';

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
  factory InventoryValuationDto.fromJson(Map<dynamic, dynamic> json) {
    return InventoryValuationDto(
      totalActiveSkus: toIntOrZero(json['total_active_skus']),
      totalUnitsInStock: toDoubleOrZero(json['total_units_in_stock']),
      totalInventoryCostMxn: toDoubleOrZero(json['total_inventory_cost_mxn']),
      totalInventoryRetailMxn: toDoubleOrZero(json['total_inventory_retail_mxn']),
      potentialGrossProfitMxn: toDoubleOrZero(json['potential_gross_profit_mxn']),
    );
  }

  /// Serialización segura a JSON.
  Map<dynamic, dynamic> toJson() {
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
  factory TopSellingProductDto.fromJson(Map<dynamic, dynamic> json) {
    return TopSellingProductDto(
      productId: json['product_id'] as String? ?? '',
      productName: json['product_name'] as String? ?? 'Producto',
      sku: json['sku'] as String? ?? '',
      unitsSold: toDoubleOrZero(json['units_sold']),
      revenueMxn: toDoubleOrZero(json['revenue_mxn']),
      profitMxn: toDoubleOrZero(json['profit_mxn']),
    );
  }

  /// Serialización a JSON.
  Map<dynamic, dynamic> toJson() {
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
  factory CriticalStockProductDto.fromJson(Map<dynamic, dynamic> json) {
    return CriticalStockProductDto(
      productId: json['product_id'] as String? ?? '',
      productName: json['product_name'] as String? ?? 'Producto',
      sku: json['sku'] as String? ?? '',
      currentStock: toDoubleOrZero(json['current_stock']),
      minStock: toDoubleOrZero(json['min_stock']),
      isOutOfStock: json['is_out_of_stock'] as bool? ?? false,
    );
  }

  /// Serialización a JSON.
  Map<dynamic, dynamic> toJson() {
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
  factory InventoryHealthDto.fromJson(Map<dynamic, dynamic> json) {
    return InventoryHealthDto(
      valuation: json['valuation'] != null
          ? InventoryValuationDto.fromJson(json['valuation'] as Map<dynamic, dynamic>)
          : const InventoryValuationDto(
              totalActiveSkus: 0,
              totalUnitsInStock: 0.0,
              totalInventoryCostMxn: 0.0,
              totalInventoryRetailMxn: 0.0,
              potentialGrossProfitMxn: 0.0,
            ),
      topSellingProducts: (json['top_selling_products'] as List<dynamic>?)
              ?.map((e) => TopSellingProductDto.fromJson(e as Map<dynamic, dynamic>))
              .toList() ??
          [],
      criticalStockProducts: (json['critical_stock_products'] as List<dynamic>?)
              ?.map((e) => CriticalStockProductDto.fromJson(e as Map<dynamic, dynamic>))
              .toList() ??
          [],
    );
  }

  /// Serialización segura a JSON.
  Map<dynamic, dynamic> toJson() {
    return {
      'valuation': valuation.toJson(),
      'top_selling_products': topSellingProducts.map((p) => p.toJson()).toList(),
      'critical_stock_products': criticalStockProducts.map((p) => p.toJson()).toList(),
    };
  }
}
