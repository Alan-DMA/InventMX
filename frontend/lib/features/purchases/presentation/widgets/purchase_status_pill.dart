import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../domain/purchase_order.dart';

/// Color con el que se lee cada estado de una orden en todo el módulo.
///
/// Un solo mapa para la tarjeta del listado y el detalle: dos vocabularios de
/// estado divergentes en la misma pantalla es de los errores que el usuario
/// nota aunque no sepa nombrarlo.
Color purchaseStatusColor(PurchaseOrderStatus status) => switch (status) {
      PurchaseOrderStatus.received => AppColors.success,
      PurchaseOrderStatus.partiallyReceived => AppColors.warning,
      PurchaseOrderStatus.sent => AppColors.info,
      PurchaseOrderStatus.confirmed => AppColors.info,
      PurchaseOrderStatus.draft => AppColors.onSurfaceMuted,
      PurchaseOrderStatus.cancelled => AppColors.error,
    };

/// Píldora de estado — punto de color + etiqueta, sobre un fondo teñido del
/// mismo color. Extraída de `PurchaseOrderCard` para que el detalle de la
/// orden muestre exactamente la misma señal que el listado del que se abrió.
class PurchaseStatusPill extends StatelessWidget {
  const PurchaseStatusPill({super.key, required this.status});

  final PurchaseOrderStatus status;

  @override
  Widget build(BuildContext context) {
    final color = purchaseStatusColor(status);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            status.label,
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w600, color: color),
          ),
        ],
      ),
    );
  }
}
