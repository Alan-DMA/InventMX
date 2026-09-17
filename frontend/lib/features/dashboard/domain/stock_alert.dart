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
  });

  final String productId;
  final String productName;
  final int availableStock;
  final bool isOutOfStock;

  @override
  List<Object?> get props =>
      [productId, productName, availableStock, isOutOfStock];
}
