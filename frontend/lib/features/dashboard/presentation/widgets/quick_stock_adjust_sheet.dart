import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../inventory/domain/product.dart';
import '../../../inventory/presentation/inventory_provider.dart';
import '../../../inventory/presentation/widgets/adjust_stock_modal.dart';

/// Acción rápida "Ajustar stock" del Centro de mando (Fase 3).
///
/// Busca contra los productos ya cargados en `inventoryProvider` (mismo
/// patrón que `ProductSearchResults` del POS: filtro local, sin llamada
/// extra) y al elegir uno abre directo `showAdjustStockModal`, sin pasar
/// primero por la ficha del producto.
Future<void> showQuickStockAdjustSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const QuickStockAdjustSheet(),
  );
}

class QuickStockAdjustSheet extends ConsumerStatefulWidget {
  const QuickStockAdjustSheet({super.key});

  @override
  ConsumerState<QuickStockAdjustSheet> createState() =>
      _QuickStockAdjustSheetState();
}

class _QuickStockAdjustSheetState extends ConsumerState<QuickStockAdjustSheet> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(inventoryProvider);
    final q = _query.toLowerCase().trim();

    final results = q.isEmpty
        ? state.products
        : state.products
            .where((p) =>
                p.name.toLowerCase().contains(q) ||
                p.sku.toLowerCase().contains(q) ||
                (p.barcode?.contains(q) ?? false))
            .toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, scrollController) => Container(
        decoration: const BoxDecoration(
          color: AppColors.darkSlate,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  const Text(
                    'Ajustar stock',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: AppColors.onSurface,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    key: const Key('quickAdjustClose'),
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded,
                        color: AppColors.onSurfaceMuted),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextField(
                key: const Key('quickAdjustSearchField'),
                controller: _searchCtrl,
                autofocus: true,
                onChanged: (v) => setState(() => _query = v),
                style: const TextStyle(color: AppColors.onSurface),
                decoration: InputDecoration(
                  hintText: 'Busca por nombre, SKU o código',
                  hintStyle:
                      const TextStyle(color: AppColors.onSurfaceMuted),
                  prefixIcon: const Icon(Icons.search_rounded,
                      color: AppColors.onSurfaceMuted),
                  filled: true,
                  fillColor: AppColors.surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: state.isLoading && state.products.isEmpty
                  ? const Center(
                      child: CircularProgressIndicator(
                          color: AppColors.emerald),
                    )
                  : results.isEmpty
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: Text(
                              'No encontramos ningún producto con eso.',
                              textAlign: TextAlign.center,
                              style:
                                  TextStyle(color: AppColors.onSurfaceMuted),
                            ),
                          ),
                        )
                      : ListView.builder(
                          controller: scrollController,
                          padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                          itemCount: results.length,
                          itemBuilder: (context, i) =>
                              _ProductRow(product: results[i]),
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProductRow extends StatelessWidget {
  const _ProductRow({required this.product});

  final Product product;

  @override
  Widget build(BuildContext context) {
    final status = product.stockStatus;
    final tint = switch (status) {
      StockStatus.outOfStock => AppColors.error,
      StockStatus.lowStock => AppColors.warning,
      StockStatus.inStock => AppColors.onSurfaceMuted,
    };

    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: Key('quickAdjustProduct-${product.id}'),
        borderRadius: BorderRadius.circular(12),
        onTap: () async {
          Navigator.of(context).pop();
          await showAdjustStockModal(context, product);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.name,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      product.category,
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.onSurfaceMuted),
                    ),
                  ],
                ),
              ),
              Text(
                status == StockStatus.outOfStock
                    ? 'Agotado'
                    : '${product.availableStock} en stock',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: tint,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
