import 'package:flutter/material.dart';
import '../../../../../../core/theme/app_colors.dart';
import '../../domain/product.dart';

/// Tarjeta de stock para la ficha de detalle.
///
/// Variantes:
///   [StockCardVariant.available]  — stock disponible con semáforo StockStatus
///   [StockCardVariant.reserved]   — stock reservado (warning si > 0, muted si == 0)
///
/// Referencia visual: dos tarjetas en fila con ícono, label, cantidad y subtexto.
enum StockCardVariant { available, reserved }

class StockCard extends StatelessWidget {
  const StockCard({
    super.key,
    required this.product,
    required this.variant,
  });

  final Product product;
  final StockCardVariant variant;

  @override
  Widget build(BuildContext context) {
    final isAvailable = variant == StockCardVariant.available;

    final int quantity;
    final String label;
    final String subtitle;
    final Color color;
    final IconData icon;

    if (isAvailable) {
      quantity = product.availableStock;
      label = 'DISPONIBLE';
      subtitle = _availableSubtitle(product);
      color = _availableColor(product.stockStatus);
      icon = Icons.inventory_rounded;
    } else {
      quantity = product.reservedStock;
      label = 'RESERVADO';
      subtitle = 'Pedidos pendientes';
      color = quantity > 0 ? AppColors.warning : AppColors.onSurfaceMuted;
      icon = Icons.lock_clock_rounded;
    }

    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: color.withValues(alpha: 0.25),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Label + ícono
            Row(
              children: [
                Icon(icon, size: 14, color: color),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: color,
                    letterSpacing: 0.8,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Cantidad
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  '$quantity',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w700,
                    color: color,
                    height: 1,
                  ),
                ),
                const SizedBox(width: 3),
                Text(
                  'pzs',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: color.withValues(alpha: 0.8),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            // Subtexto
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 11,
                color: color.withValues(alpha: 0.7),
                height: 1.3,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Color _availableColor(StockStatus status) => switch (status) {
        StockStatus.outOfStock => AppColors.error,
        StockStatus.lowStock => AppColors.warning,
        StockStatus.inStock => AppColors.emerald,
      };

  String _availableSubtitle(Product p) {
    final threshold = p.minStockAlert;
    return switch (p.stockStatus) {
      StockStatus.outOfStock => 'Sin stock disponible',
      StockStatus.lowStock => 'Stock bajo (mín. ${threshold ?? 0} pzs)',
      StockStatus.inStock => 'En anaquel o piso',
    };
  }
}
