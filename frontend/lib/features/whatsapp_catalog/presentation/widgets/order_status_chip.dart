import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../domain/whatsapp_order.dart';

/// Color del estado en la app del tendero (tema oscuro).
Color orderStatusColor(OrderStatus status) => switch (status) {
      OrderStatus.newOrder => AppColors.skyBlue,
      OrderStatus.ready => AppColors.emerald,
      OrderStatus.delivered => AppColors.onSurfaceMuted,
      OrderStatus.cancelled => AppColors.error,
    };

IconData orderStatusIcon(OrderStatus status) => switch (status) {
      OrderStatus.newOrder => Icons.fiber_new_rounded,
      OrderStatus.ready => Icons.check_circle_outline_rounded,
      OrderStatus.delivered => Icons.done_all_rounded,
      OrderStatus.cancelled => Icons.cancel_outlined,
    };

/// Píldora "Nuevo · Listo · Entregado · Cancelado".
class OrderStatusChip extends StatelessWidget {
  const OrderStatusChip({super.key, required this.status, this.compact = false});

  final OrderStatus status;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final color = orderStatusColor(status);
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: compact ? 8 : 10, vertical: compact ? 2 : 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(orderStatusIcon(status), size: compact ? 13 : 15, color: color),
          const SizedBox(width: 4),
          Text(
            status.label,
            style: TextStyle(
              fontSize: compact ? 11 : 12,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// "hace 3 min", "hace 2 h", "ayer", "12 sep". Para saber cuánto lleva
/// esperando un pedido sin tener que leer la hora.
String timeAgo(DateTime when, {DateTime? now}) {
  final ref = now ?? DateTime.now();
  final diff = ref.difference(when);
  if (diff.inSeconds < 45) return 'ahora';
  if (diff.inMinutes < 60) return 'hace ${diff.inMinutes} min';
  if (diff.inHours < 24) return 'hace ${diff.inHours} h';
  if (diff.inDays == 1) return 'ayer';
  if (diff.inDays < 7) return 'hace ${diff.inDays} días';
  const months = [
    'ene', 'feb', 'mar', 'abr', 'may', 'jun',
    'jul', 'ago', 'sep', 'oct', 'nov', 'dic',
  ];
  return '${when.day} ${months[when.month - 1]}';
}

String hourMinute(DateTime when) =>
    '${when.hour.toString().padLeft(2, '0')}:${when.minute.toString().padLeft(2, '0')}';
