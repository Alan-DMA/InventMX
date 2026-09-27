import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/theme/app_colors.dart';
import 'package:nexus_app/core/widgets/product_image_widget.dart';
import '../../domain/cart_item.dart';
import '../cart_provider.dart';

/// Fila de un ítem del carrito en el POS.
///
/// Layout:
///   [Thumbnail] | Nombre + precio unitario esmeralda | [−] [xN] [+] [🗑]
///
/// El botón − nunca baja de 1. Para eliminar el ítem se usa el ícono papelera.
/// El botón + se apaga al llegar a las existencias de mi almacén ("máx. N");
/// si el renglón pide de más (pedido web cargado), queda en rojo hasta que se
/// ajuste — no se cobra así (decisiones de Eduardo, Sep 26).
class CartItemTile extends ConsumerWidget {
  const CartItemTile({super.key, required this.item});

  final CartItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(cartProvider.notifier);
    final exceeds = item.exceedsStock;

    return Container(
      key: Key('cartItem-${item.id}'),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: exceeds
            ? AppColors.error.withValues(alpha: 0.08)
            : AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: exceeds
              ? AppColors.error.withValues(alpha: 0.6)
              : AppColors.border,
        ),
      ),
      child: Row(
        children: [
          // ── Thumbnail ──────────────────────────────────────────────────
          _Thumbnail(imageUrl: item.imageUrl, isOnTheFly: item.isOnTheFly),
          const SizedBox(width: 12),

          // ── Nombre + precio unitario ───────────────────────────────────
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.onSurface,
                    height: 1.2,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Text(
                  '\$${item.unitPriceMxn.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.emerald,
                  ),
                ),
                if (exceeds)
                  Text(
                    item.maxQuantity! <= 0
                        ? 'Sin existencias aquí · quítalo'
                        : 'Solo hay ${item.maxQuantity} · ajusta',
                    key: const Key('cartItemStockConflict'),
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.error,
                    ),
                  )
                else if (item.atStockLimit)
                  Text(
                    'máx. ${item.maxQuantity}',
                    key: const Key('cartItemStockLimit'),
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.onSurfaceMuted,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),

          // ── Controles cantidad (mínimo 1) ──────────────────────────────
          _QtyControls(
            qty: item.quantity,
            onDecrement: () => notifier.decrement(item.id),
            canIncrement: !item.atStockLimit,
            onIncrement: () {
              final notice = notifier.increment(item.id);
              if (notice != null) {
                ScaffoldMessenger.of(context)
                  ..hideCurrentSnackBar()
                  ..showSnackBar(SnackBar(content: Text(notice)));
              }
            },
          ),
          const SizedBox(width: 6),

          // ── Botón eliminar ─────────────────────────────────────────────
          GestureDetector(
            onTap: () => notifier.removeItem(item.id),
            behavior: HitTestBehavior.opaque,
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: AppColors.error.withValues(alpha: 0.3),
                ),
              ),
              child: Icon(
                Icons.delete_outline_rounded,
                size: 16,
                color: AppColors.error.withValues(alpha: 0.8),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Thumbnail
// ---------------------------------------------------------------------------

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.imageUrl, required this.isOnTheFly});

  final String? imageUrl;
  final bool isOnTheFly;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: ProductImageWidget(
        imageUrl: imageUrl,
        width: 52,
        height: 52,
        fit: BoxFit.cover,
        placeholder: _placeholder(),
      ),
    );
  }

  Widget _placeholder() {
    return Center(
      child: Icon(
        isOnTheFly
            ? Icons.add_shopping_cart_rounded
            : Icons.inventory_2_outlined,
        size: 24,
        color: AppColors.onSurfaceMuted.withValues(alpha: 0.45),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Controles de cantidad
// ---------------------------------------------------------------------------

class _QtyControls extends StatelessWidget {
  const _QtyControls({
    required this.qty,
    required this.onDecrement,
    required this.onIncrement,
    this.canIncrement = true,
  });

  final int qty;
  final VoidCallback onDecrement;
  final VoidCallback onIncrement;
  final bool canIncrement;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Botón − (deshabilitado visualmente cuando qty == 1)
        _ControlBtn(
          icon: Icons.remove_rounded,
          onTap: qty > 1 ? onDecrement : null,
          color: qty > 1
              ? AppColors.onSurfaceMuted
              : AppColors.onSurfaceMuted.withValues(alpha: 0.25),
        ),
        // Cantidad
        Container(
          constraints: const BoxConstraints(minWidth: 32),
          alignment: Alignment.center,
          child: Text(
            'x$qty',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.onSurface,
            ),
          ),
        ),
        // Botón +
        _ControlBtn(
          key: const Key('cartItemIncrement'),
          icon: Icons.add_rounded,
          onTap: canIncrement ? onIncrement : null,
          color: canIncrement
              ? AppColors.onSurfaceMuted
              : AppColors.onSurfaceMuted.withValues(alpha: 0.25),
        ),
      ],
    );
  }
}

class _ControlBtn extends StatelessWidget {
  const _ControlBtn({
    super.key,
    required this.icon,
    required this.onTap,
    required this.color,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border),
        ),
        child: Icon(icon, size: 16, color: color),
      ),
    );
  }
}
