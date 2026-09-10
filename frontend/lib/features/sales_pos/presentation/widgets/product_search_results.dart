import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../inventory/domain/product.dart';
import '../../../inventory/presentation/inventory_provider.dart';
import '../cart_provider.dart';

/// Panel desplegable de resultados de búsqueda del POS.
///
/// Filtra la lista ya cargada en inventoryProvider (sin llamada extra
/// al backend) con búsqueda fuzzy local case-insensitive.
/// Se muestra cuando searchQuery.isNotEmpty y se cierra al añadir un producto.
class ProductSearchResults extends ConsumerWidget {
  const ProductSearchResults({
    super.key,
    required this.query,
    required this.onProductAdded,
  });

  final String query;

  /// Callback que se ejecuta tras añadir un producto al carrito.
  /// La pantalla lo usa para limpiar la búsqueda y cerrar el panel.
  final VoidCallback onProductAdded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (query.trim().isEmpty) return const SizedBox.shrink();

    final allProducts = ref.watch(inventoryProvider).products;
    final q = query.toLowerCase().trim();

    final results = allProducts
        .where((p) {
          return p.name.toLowerCase().contains(q) ||
              p.sku.toLowerCase().contains(q) ||
              (p.barcode?.contains(q) ?? false);
        })
        .take(6)
        .toList();

    if (results.isEmpty) {
      return _NoResultsHint(query: query);
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: results.asMap().entries.map((entry) {
            final isLast = entry.key == results.length - 1;
            return _ResultRow(
              product: entry.value,
              isLast: isLast,
              onAdd: () {
                ref.read(cartProvider.notifier).addProduct(entry.value);
                onProductAdded();
              },
            );
          }).toList(),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Fila de resultado
// ---------------------------------------------------------------------------

class _ResultRow extends StatelessWidget {
  const _ResultRow({
    required this.product,
    required this.isLast,
    required this.onAdd,
  });

  final Product product;
  final bool isLast;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onAdd,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          border: isLast
              ? null
              : const Border(
                  bottom: BorderSide(color: AppColors.border),
                ),
        ),
        child: Row(
          children: [
            // Thumbnail pequeño
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(8),
              ),
              child: product.imageUrl != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        product.imageUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _icon(),
                      ),
                    )
                  : _icon(),
            ),
            const SizedBox(width: 12),

            // Nombre + SKU
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.name,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: AppColors.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    product.sku,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.onSurfaceMuted,
                    ),
                  ),
                ],
              ),
            ),

            // Precio + botón +
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '\$${product.priceMxn.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.emerald,
                  ),
                ),
                const SizedBox(height: 2),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.emerald.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: AppColors.emerald.withValues(alpha: 0.3),
                    ),
                  ),
                  child: const Text(
                    '+ Añadir',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: AppColors.emerald,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _icon() => Center(
        child: Icon(
          Icons.inventory_2_outlined,
          size: 18,
          color: AppColors.onSurfaceMuted.withValues(alpha: 0.4),
        ),
      );
}

// ---------------------------------------------------------------------------
// Sin resultados
// ---------------------------------------------------------------------------

class _NoResultsHint extends StatelessWidget {
  const _NoResultsHint({required this.query});
  final String query;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Icon(
            Icons.search_off_rounded,
            size: 18,
            color: AppColors.onSurfaceMuted.withValues(alpha: 0.5),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Sin resultados para "$query"',
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.onSurfaceMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
