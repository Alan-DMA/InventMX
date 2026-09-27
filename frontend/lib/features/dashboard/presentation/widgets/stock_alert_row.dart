import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../domain/stock_alert.dart';

/// Renglón de una alerta de stock bajo — Inicio y "Alertas de stock".
///
/// La alerta es de un producto **en un almacén** (D38): con [showWarehouse]
/// dice cuál, que es lo que importa cuando se ven todos los almacenes.
class StockAlertRow extends StatelessWidget {
  const StockAlertRow({
    super.key,
    required this.alert,
    required this.onTap,
    this.showWarehouse = false,
  });

  final StockAlertItem alert;
  final VoidCallback onTap;
  final bool showWarehouse;

  @override
  Widget build(BuildContext context) {
    final tint = alert.isOutOfStock ? AppColors.error : AppColors.warning;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: Key('homeAlertRow-${alert.alertKey}'),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              Icon(
                alert.isOutOfStock
                    ? Icons.remove_shopping_cart_outlined
                    : Icons.inventory_2_outlined,
                size: 16,
                color: tint,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      alert.productName,
                      style: const TextStyle(
                          fontSize: 13.5, color: AppColors.onSurface),
                    ),
                    if (showWarehouse && alert.warehouseName != null)
                      Text(
                        alert.warehouseName!,
                        key: Key('homeAlertWarehouse-${alert.alertKey}'),
                        style: const TextStyle(
                            fontSize: 11.5, color: AppColors.skyBlue),
                      ),
                  ],
                ),
              ),
              Text(
                alert.isOutOfStock
                    ? 'Agotado'
                    : 'Quedan ${alert.availableStock}',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: tint,
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right_rounded,
                  size: 18, color: AppColors.onSurfaceMuted),
            ],
          ),
        ),
      ),
    );
  }
}
