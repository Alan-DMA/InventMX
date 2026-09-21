import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../domain/store_order.dart';
import '../../domain/whatsapp_order.dart';
import '../catalog_theme.dart' show mxn;
import '../store_orders_provider.dart';

/// Aviso en vivo de "pedido nuevo" — vive en el `DashboardShell`, así se ve
/// en cualquier tab sin que el tendero haga nada. Sonido corto + vibración
/// una sola vez por pedido; se va solo a los 12 s o al tocarlo. Sólo avisa
/// el evento `order.new`: cualquier otro aviso sería ruido (cat. 5 del
/// catálogo de anti-patrones).
///
/// Mantener este widget montado es lo que mantiene vivo el socket
/// (`storeOrdersProvider`) mientras la app está abierta.
class NewOrderBanner extends ConsumerStatefulWidget {
  const NewOrderBanner({super.key, this.autoDismiss = const Duration(seconds: 12)});

  final Duration autoDismiss;

  @override
  ConsumerState<NewOrderBanner> createState() => _NewOrderBannerState();
}

class _NewOrderBannerState extends ConsumerState<NewOrderBanner> {
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _dismiss() {
    _timer?.cancel();
    ref.read(incomingOrderProvider.notifier).state = null;
  }

  void _open(StoreOrder order) {
    final router = GoRouter.of(context);
    _dismiss();
    router.push(AppRoutes.storeOrderPath(order.folio));
  }

  @override
  Widget build(BuildContext context) {
    // Suscribirse aquí mantiene vivo el canal aunque nadie más lo mire.
    ref.watch(storeOrdersProvider);
    ref.listen<StoreOrder?>(incomingOrderProvider, (previous, next) {
      _timer?.cancel();
      if (next == null || next.folio == previous?.folio) return;
      SystemSound.play(SystemSoundType.alert);
      HapticFeedback.mediumImpact();
      _timer = Timer(widget.autoDismiss, () {
        if (mounted) _dismiss();
      });
    });

    final order = ref.watch(incomingOrderProvider);
    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      child: order == null
          ? const SizedBox(width: double.infinity)
          : _Banner(order: order, onOpen: () => _open(order), onDismiss: _dismiss),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.order,
    required this.onOpen,
    required this.onDismiss,
  });

  final StoreOrder order;
  final VoidCallback onOpen;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final saved = order.order;
    final delivery = saved.draft.deliveryMethod == DeliveryMethod.delivery;
    return Material(
      key: const Key('newOrderBanner'),
      color: AppColors.emerald,
      child: InkWell(
        onTap: onOpen,
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 6, 10),
            child: Row(
              children: [
                const Icon(Icons.shopping_bag_rounded,
                    color: AppColors.darkSlate, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Pedido nuevo · ${saved.draft.customerName}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: AppColors.darkSlate,
                        ),
                      ),
                      Text(
                        '${saved.itemCount} pzas · ${mxn(saved.totals.totalMxn)} · '
                        '${delivery ? 'a domicilio' : 'recoger'} · ${saved.folio}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.darkSlate.withValues(alpha: 0.8),
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  key: const Key('newOrderBannerOpen'),
                  onPressed: onOpen,
                  style: TextButton.styleFrom(
                      foregroundColor: AppColors.darkSlate),
                  child: const Text('Ver',
                      style: TextStyle(fontWeight: FontWeight.w800)),
                ),
                IconButton(
                  key: const Key('newOrderBannerDismiss'),
                  onPressed: onDismiss,
                  icon: const Icon(Icons.close_rounded,
                      color: AppColors.darkSlate, size: 20),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
