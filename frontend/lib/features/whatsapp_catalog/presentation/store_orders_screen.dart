import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../domain/store_order.dart';
import '../domain/whatsapp_order.dart';
import 'catalog_theme.dart' show mxn;
import 'store_orders_provider.dart';
import 'widgets/order_status_chip.dart';

/// "Pedidos web" — lo que entró por la vitrina y falta atender (Activos:
/// nuevo + listo) y lo ya cerrado (Historial). La lista se actualiza sola
/// con el canal en vivo; el pull-to-refresh vuelve a pedir al servidor.
class StoreOrdersScreen extends ConsumerStatefulWidget {
  const StoreOrdersScreen({super.key, this.initialTab = 0});

  final int initialTab;

  /// `/ventas/pedidos?tab=historial` — a donde manda el aviso "Quedó en
  /// Historial" al cerrar un pedido.
  static const historyLocation = '${AppRoutes.storeOrders}?tab=historial';

  @override
  ConsumerState<StoreOrdersScreen> createState() => _StoreOrdersScreenState();
}

class _StoreOrdersScreenState extends ConsumerState<StoreOrdersScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs =
      TabController(length: 2, vsync: this, initialIndex: widget.initialTab);

  @override
  void initState() {
    super.initState();
    final requested = ref.read(storeOrdersTabRequestProvider);
    if (requested != null) {
      _tabs.index = requested;
      ref.read(storeOrdersTabRequestProvider.notifier).state = null;
    }
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final newCount = ref.watch(newOrdersCountProvider);
    // Al volver desde el detalle ("Ver" en un pedido cerrado) la pantalla ya
    // existe: la pestaña pedida llega por el provider, no por la URL.
    ref.listen<int?>(storeOrdersTabRequestProvider, (_, tab) {
      if (tab == null) return;
      if (_tabs.index != tab) _tabs.animateTo(tab);
      ref.read(storeOrdersTabRequestProvider.notifier).state = null;
    });
    return Scaffold(
      backgroundColor: AppColors.darkSlate,
      appBar: AppBar(
        backgroundColor: AppColors.darkSlate,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              size: 20, color: AppColors.onSurface),
          onPressed: () => context.pop(),
        ),
        title: const Text(
          'Pedidos web',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppColors.onSurface,
          ),
        ),
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: AppColors.emerald,
          labelColor: AppColors.onSurface,
          unselectedLabelColor: AppColors.onSurfaceMuted,
          labelStyle: const TextStyle(fontWeight: FontWeight.w700),
          tabs: [
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Activos'),
                  if (newCount > 0) ...[
                    const SizedBox(width: 6),
                    _CountBadge(count: newCount),
                  ],
                ],
              ),
            ),
            const Tab(text: 'Historial'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: const [_ActiveTab(), _HistoryTab()],
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) => Container(
        key: const Key('newOrdersBadge'),
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
        decoration: BoxDecoration(
          color: AppColors.skyBlue,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          '$count',
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: AppColors.darkSlate,
          ),
        ),
      );
}

class _ActiveTab extends ConsumerWidget {
  const _ActiveTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(storeOrdersProvider);
    return RefreshIndicator(
      color: AppColors.emerald,
      onRefresh: () => ref.read(storeOrdersProvider.notifier).refresh(),
      child: async.when(
        loading: () => const _Loading(),
        error: (e, _) => _ErrorState(
          onRetry: () => ref.read(storeOrdersProvider.notifier).refresh(),
        ),
        data: (list) => list.items.isEmpty
            ? const _EmptyState(
                icon: Icons.storefront_outlined,
                title: 'Nada pendiente',
                body:
                    'Los pedidos que lleguen por tu catálogo aparecen aquí al '
                    'instante, aunque no abras WhatsApp. Los ya entregados o '
                    'cancelados están en Historial.',
              )
            : _OrderList(orders: list.items, listKey: 'activeOrdersList'),
      ),
    );
  }
}

class _HistoryTab extends ConsumerWidget {
  const _HistoryTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(storeOrdersHistoryProvider);
    return RefreshIndicator(
      color: AppColors.emerald,
      onRefresh: () => ref.refresh(storeOrdersHistoryProvider.future),
      child: async.when(
        loading: () => const _Loading(),
        error: (e, _) => _ErrorState(
          onRetry: () => ref.invalidate(storeOrdersHistoryProvider),
        ),
        data: (list) => list.items.isEmpty
            ? const _EmptyState(
                icon: Icons.history_rounded,
                title: 'Sin historial todavía',
                body: 'Aquí quedan los pedidos entregados y cancelados.',
              )
            : _OrderList(orders: list.items, listKey: 'historyOrdersList'),
      ),
    );
  }
}

class _OrderList extends StatelessWidget {
  const _OrderList({required this.orders, required this.listKey});

  final List<StoreOrder> orders;
  final String listKey;

  @override
  Widget build(BuildContext context) => ListView.separated(
        key: PageStorageKey(listKey),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        itemCount: orders.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) => _OrderTile(order: orders[i]),
      );
}

/// Renglón: folio · cliente · cuánto lleva · total · entrega · estado.
/// El punto azul y el borde marcan lo que nadie ha abierto.
class _OrderTile extends StatelessWidget {
  const _OrderTile({required this.order});

  final StoreOrder order;

  @override
  Widget build(BuildContext context) {
    final saved = order.order;
    final unseen = !order.isSeen && saved.status == OrderStatus.newOrder;
    final delivery = saved.draft.deliveryMethod == DeliveryMethod.delivery;
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        key: Key('orderRow-${saved.folio}'),
        borderRadius: BorderRadius.circular(14),
        onTap: () => context.push(AppRoutes.storeOrderPath(saved.folio)),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: unseen
                  ? AppColors.skyBlue.withValues(alpha: 0.55)
                  : AppColors.border,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (unseen)
                    Container(
                      key: const Key('unseenDot'),
                      width: 8,
                      height: 8,
                      margin: const EdgeInsets.only(right: 8),
                      decoration: const BoxDecoration(
                        color: AppColors.skyBlue,
                        shape: BoxShape.circle,
                      ),
                    ),
                  Expanded(
                    child: Text(
                      saved.draft.customerName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: unseen ? FontWeight.w800 : FontWeight.w600,
                        color: AppColors.onSurface,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    mxn(saved.totals.totalMxn),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: AppColors.emerald,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  // Un solo texto con elipsis: en un teléfono angosto el
                  // chip de estado siempre queda visible a la derecha.
                  Expanded(
                    child: Text(
                      '${saved.folio} · ${timeAgo(saved.issuedAt)} · '
                      '${delivery ? 'Domicilio' : 'Recoger'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.onSurfaceMuted),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OrderStatusChip(status: saved.status, compact: true),
                ],
              ),
              if (order.possibleDuplicateOf != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.content_copy_rounded,
                        size: 13, color: AppColors.warning),
                    const SizedBox(width: 5),
                    Text(
                      'Posible duplicado de ${order.possibleDuplicateOf}',
                      key: const Key('duplicateTag'),
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AppColors.warning,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}


class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) => const Center(
        child: CircularProgressIndicator(color: AppColors.emerald),
      );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 80),
          Icon(icon, size: 44, color: AppColors.onSurfaceMuted),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              body,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                height: 1.4,
                color: AppColors.onSurfaceMuted,
              ),
            ),
          ),
        ],
      );
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 80),
          const Icon(Icons.wifi_off_rounded,
              size: 44, color: AppColors.onSurfaceMuted),
          const SizedBox(height: 14),
          const Text(
            'No pudimos cargar los pedidos',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Revisa tu conexión. Los pedidos no se pierden: están en el servidor.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: AppColors.onSurfaceMuted),
          ),
          const SizedBox(height: 16),
          Center(
            child: OutlinedButton(
              onPressed: onRetry,
              child: const Text('Reintentar'),
            ),
          ),
        ],
      );
}
