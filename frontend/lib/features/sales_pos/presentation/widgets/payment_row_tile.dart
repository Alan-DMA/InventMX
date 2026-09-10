import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../domain/payment_entry.dart';
import 'payment_modal.dart' show PaymentMethodIconX;

/// Fila de un método de pago ya agregado al cobro — Tarea 7.2.
///
/// Trazabilidad: Constitución Art. VII (7.2) · Doc. Maestro RF-14, SR-04 · HU-13 / CU-14
class PaymentRowTile extends StatelessWidget {
  const PaymentRowTile({
    super.key,
    required this.entry,
    required this.onRemove,
  });

  final PaymentEntry entry;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final subtitle = entry.referenceCode?.trim().isNotEmpty == true
        ? 'Folio: ${entry.referenceCode}'
        : (entry.method == PaymentMethodMxn.cashMxn
            ? 'Pago en efectivo'
            : 'Sin folio registrado');

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(entry.method.icon,
                size: 18, color: AppColors.onSurfaceMuted),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.method.label,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.onSurfaceMuted,
                  ),
                ),
              ],
            ),
          ),
          Text(
            '\$${entry.amountMxn.toStringAsFixed(2)}',
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.onSurface,
            ),
          ),
          IconButton(
            tooltip: 'Eliminar',
            icon: const Icon(Icons.delete_outline_rounded,
                size: 18, color: AppColors.onSurfaceMuted),
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}
