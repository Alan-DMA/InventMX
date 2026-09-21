import 'package:equatable/equatable.dart';

/// Un renglón de alerta de stock para el Centro de mando (Fase 3).
///
/// Autocontenido en el mock del Dashboard — no sale de `inventoryRepositoryProvider`
/// real (Inventario ya habla con el backend real y hoy devuelve stock en $0.00,
/// bug conocido documentado en la bitácora). Mismo patrón que ya usan los avisos
/// de stock bajo (`StoreNotification.productId`, ids `prod-001`/`prod-014`).
class StockAlertItem extends Equatable {
  const StockAlertItem({
    required this.productId,
    required this.productName,
    required this.availableStock,
    required this.isOutOfStock,
    this.minStock = 0,
    this.sku = '',
  });

  final String productId;
  final String productName;
  final int availableStock;
  final bool isOutOfStock;
  final int minStock;
  final String sku;

  /// Constructor a partir del payload JSON de backend (CriticalStockProductResponse).
  factory StockAlertItem.fromJson(Map<String, dynamic> json) {
    final current = _toInt(json['current_stock']);
    final min = _toInt(json['min_stock']);
    return StockAlertItem(
      productId: json['product_id']?.toString() ?? '',
      productName: json['product_name'] as String? ?? 'Producto',
      availableStock: current,
      isOutOfStock: json['is_out_of_stock'] as bool? ?? (current <= 0),
      minStock: min,
      sku: json['sku'] as String? ?? '',
    );
  }

  @override
  List<Object?> get props =>
      [productId, productName, availableStock, isOutOfStock, minStock, sku];
}

int _toInt(dynamic v, {int defaultValue = 0}) {
  if (v == null) return defaultValue;
  if (v is num) return v.toInt();
  final s = v.toString().trim();
  return int.tryParse(s) ?? double.tryParse(s)?.toInt() ?? defaultValue;
}
