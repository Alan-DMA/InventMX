import 'package:flutter/material.dart';
import '../../../../../../core/theme/app_colors.dart';
import '../../domain/product.dart';

/// Tile de producto para la lista de inventario.
///
/// Layout (referencia visual):
///   [ Thumbnail ] Nombre          [ Badge stock ]
///                 SKU · Barcode
///                 $ Precio MXN
///
/// Badge semáforo:
///   Sin stock  → error (rojo)
///   Stock bajo → warning (ámbar)
///   Normal     → emerald
class ProductListTile extends StatelessWidget {
  const ProductListTile({
    super.key,
    required this.product,
    required this.onTap,
  });

  final Product product;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            _buildThumbnail(),
            const SizedBox(width: 12),
            Expanded(child: _buildInfo(context)),
            const SizedBox(width: 8),
            _buildStockBadge(),
          ],
        ),
      ),
    );
  }

  // ── Thumbnail ──────────────────────────────────────────────────────────────

  Widget _buildThumbnail() {
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: product.imageUrl != null
          ? ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.network(
                product.imageUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _placeholderIcon(),
              ),
            )
          : _placeholderIcon(),
    );
  }

  Widget _placeholderIcon() {
    return const Icon(
      Icons.inventory_2_outlined,
      size: 24,
      color: AppColors.onSurfaceMuted,
    );
  }

  // ── Info central ────────────────────────────────────────────────────────────

  Widget _buildInfo(BuildContext context) {
    final isCombo = product.category == 'Combos';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Nombre + badge combo inline
        Row(
          children: [
            Flexible(
              child: Text(
                product.name,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.onSurface,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (isCombo) ...[
              const SizedBox(width: 6),
              _comboBadge(),
            ],
          ],
        ),
        const SizedBox(height: 2),
        // SKU
        Text(
          product.sku,
          style: const TextStyle(
            fontSize: 11,
            color: AppColors.onSurfaceMuted,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 4),
        // Precio
        Text(
          '\$${product.priceMxn.toStringAsFixed(2)}',
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: AppColors.emerald,
          ),
        ),
      ],
    );
  }

  Widget _comboBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.skyBlue.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AppColors.skyBlue.withValues(alpha: 0.4)),
      ),
      child: const Text(
        'COMBO',
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: AppColors.skyBlue,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  // ── Badge stock ─────────────────────────────────────────────────────────────

  Widget _buildStockBadge() {
    final status = product.stockStatus;
    final (color, text) = switch (status) {
      StockStatus.outOfStock => (AppColors.error, 'Sin stock'),
      StockStatus.lowStock =>
        (AppColors.warning, '${product.availableStock} pzs'),
      StockStatus.inStock =>
        (AppColors.emerald, '${product.availableStock} pzs'),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Skeleton — estado de carga con shimmer manual (sin dependencias externas)
// ---------------------------------------------------------------------------

class ProductListTileSkeleton extends StatefulWidget {
  const ProductListTileSkeleton({super.key});

  @override
  State<ProductListTileSkeleton> createState() =>
      _ProductListTileSkeletonState();
}

class _ProductListTileSkeletonState extends State<ProductListTileSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.4, end: 0.9).animate(_ctrl);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              // Thumbnail
              _box(52, 52, radius: 10),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _box(14, double.infinity),
                    const SizedBox(height: 6),
                    _box(11, 100),
                    const SizedBox(height: 6),
                    _box(15, 70),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _box(28, 64, radius: 20),
            ],
          ),
        );
      },
    );
  }

  Widget _box(double height, double width, {double radius = 6}) {
    return Container(
      height: height,
      width: width == double.infinity ? null : width,
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant.withValues(alpha: _anim.value),
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}
