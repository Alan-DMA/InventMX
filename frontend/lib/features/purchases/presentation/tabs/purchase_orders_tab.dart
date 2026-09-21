import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import '../../domain/purchase_order.dart';
import '../purchase_order_detail_screen.dart';
import '../purchases_provider.dart';
import '../widgets/purchase_filter_sheet.dart';
import '../widgets/purchase_order_card.dart';
import '../widgets/purchase_search_bar.dart';
import '../widgets/purchase_status_chip_bar.dart';
import '../widgets/receive_purchase_modal.dart';

/// Tab "Compras" del hub — Subtarea 11.2.1, Figma nodo `1:50`.
class PurchaseOrdersTab extends ConsumerWidget {
  const PurchaseOrdersTab({super.key});

  Future<void> _openFilters(BuildContext context, WidgetRef ref, PurchaseOrdersState state) async {
    final result = await showPurchaseFilterSheet(
      context,
      initialFrom: state.dateFrom,
      initialTo: state.dateTo,
    );
    if (result == null) return;
    ref.read(purchaseOrdersProvider.notifier).setDateRange(from: result.dateFrom, to: result.dateTo);
  }

  Future<void> _receive(BuildContext context, PurchaseOrder order) async {
    if (order.status == PurchaseOrderStatus.received) return;
    await showReceivePurchaseModal(context, order);
  }

  /// Se empuja sobre el navegador de la pestaña (no el raíz) para que la barra
  /// de tabs siga visible: desde el detalle es normal querer saltar a
  /// "Por pagar". Mismo criterio que el wizard de cierre de caja.
  void _openDetail(BuildContext context, PurchaseOrder order) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PurchaseOrderDetailScreen(order: order),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(purchaseOrdersProvider);
    final hasDateFilter = state.dateFrom != null || state.dateTo != null;

    return Column(
      children: [
        // Barra de búsqueda fija sobre los chips — ajuste de QA de Eduardo:
        // en el tab Compras la búsqueda es persistente (no el ícono
        // expandible que sigue usándose en Proveedores/Por pagar).
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
          child: PurchaseSearchBar(
            onChanged: (q) => ref.read(purchaseOrdersProvider.notifier).setSearch(q),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: PurchaseStatusChipBar(
                    state: state,
                    onSelected: (f) => ref.read(purchaseOrdersProvider.notifier).setChipFilter(f),
                  ),
                ),
              ),
              Stack(
                children: [
                  IconButton(
                    onPressed: () => _openFilters(context, ref, state),
                    tooltip: 'Abrir filtros',
                    icon: const Icon(Icons.tune_rounded, color: AppColors.onSurfaceMuted),
                  ),
                  if (hasDateFilter)
                    Positioned(
                      right: 8,
                      top: 8,
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(color: AppColors.skyBlue, shape: BoxShape.circle),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        if (state.hasError) _ErrorBanner(error: state.error!, onRetry: () => ref.read(purchaseOrdersProvider.notifier).retry()),
        Expanded(child: _buildBody(context, ref, state)),
      ],
    );
  }

  Widget _buildBody(BuildContext context, WidgetRef ref, PurchaseOrdersState state) {
    if (state.isLoading && state.orders.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: AppColors.emerald));
    }

    final visible = state.visibleOrders;
    if (visible.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.shopping_bag_outlined, size: 56, color: AppColors.onSurfaceMuted),
              const SizedBox(height: 16),
              Text(
                state.search.isNotEmpty ? 'Sin resultados para "${state.search}"' : 'Sin órdenes de compra en este filtro',
                style: const TextStyle(fontSize: 15, color: AppColors.onSurfaceMuted),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
      itemCount: visible.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, i) {
        final order = visible[i];
        return PurchaseOrderCard(
          order: order,
          onTap: () => _openDetail(context, order),
          onReceive: () => _receive(context, order),
        );
      },
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.error, required this.onRetry});

  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.wifi_off_rounded, size: 18, color: AppColors.error),
          const SizedBox(width: 10),
          const Expanded(child: Text('Error de conexión. Revisa tu red.', style: TextStyle(fontSize: 13, color: AppColors.error))),
          TextButton(onPressed: onRetry, child: const Text('Reintentar')),
        ],
      ),
    );
  }
}
