import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../domain/cash_movement.dart';
import 'cash_movement_modal.dart' show CashMovementTypeIconX;

/// Fila de un movimiento de caja menor — usada en la lista de
/// `CashSessionScreen` (Subtarea 10.2.2) y en el desglose del ticket
/// Corte Z (`CashClosingTicketCard`, Subtarea 10.2.3).
class CashMovementTile extends StatelessWidget {
  const CashMovementTile({super.key, required this.movement});

  final CashMovement movement;

  @override
  Widget build(BuildContext context) {
    final sign = movement.type == CashMovementType.deposit ? '+' : '−';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: movement.type.color.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(movement.type.icon, size: 16, color: movement.type.color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  movement.description,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, color: AppColors.onSurface),
                ),
                Text(
                  _formatTime(movement.createdAt),
                  style: const TextStyle(fontSize: 11, color: AppColors.onSurfaceMuted),
                ),
              ],
            ),
          ),
          Text(
            '$sign\$${movement.amountMxn.toStringAsFixed(2)}',
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: movement.type.color,
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}
