import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../purchases/presentation/widgets/phone_launcher.dart';
import '../../saas_admin/presentation/saas_provider.dart' show clockProvider;
import '../domain/store_notification.dart';
import 'dashboard_provider.dart';

/// Avisos del negocio — cosas que importan pero no urgen.
///
/// Apartado propio y no un banner encima de la operación: nada de esto debe
/// interrumpir un cobro. Se entra desde la campana de Inicio, que lleva el
/// contador de lo no leído.
class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifications = ref.watch(notificationsProvider);
    final unread = ref.watch(unreadNotificationsProvider);

    return Scaffold(
      backgroundColor: AppColors.darkSlate,
      appBar: AppBar(
        backgroundColor: AppColors.darkSlate,
        title: const Text('Avisos'),
        actions: [
          if (unread > 0)
            TextButton(
              key: const Key('notificationsMarkAll'),
              onPressed: () =>
                  ref.read(notificationsProvider.notifier).markAllRead(),
              child: const Text('Marcar leídos',
                  style: TextStyle(color: AppColors.skyBlue, fontSize: 13)),
            ),
        ],
      ),
      body: notifications.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.emerald)),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Text(
              e.toString().replaceFirst('Exception: ', ''),
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.onSurfaceMuted),
            ),
          ),
        ),
        data: (items) => items.isEmpty
            ? const _EmptyState()
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                itemCount: items.length,
                itemBuilder: (_, i) => _NotificationTile(item: items[i]),
              ),
      ),
    );
  }
}

class _NotificationTile extends ConsumerWidget {
  const _NotificationTile({required this.item});

  final StoreNotification item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(clockProvider)();

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: item.isRead ? AppColors.border : AppColors.skyBlue,
        ),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          key: Key('notification-${item.id}'),
          borderRadius: BorderRadius.circular(14),
          onTap: () => _open(context, ref),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _tint.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(_icon, size: 18, color: _tint),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              item.title,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: item.isRead
                                    ? FontWeight.w600
                                    : FontWeight.w700,
                                color: AppColors.onSurface,
                              ),
                            ),
                          ),
                          if (!item.isRead)
                            Container(
                              width: 8,
                              height: 8,
                              margin: const EdgeInsets.only(left: 8, top: 4),
                              decoration: const BoxDecoration(
                                color: AppColors.skyBlue,
                                shape: BoxShape.circle,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item.body,
                        style: const TextStyle(
                            fontSize: 12.5,
                            height: 1.3,
                            color: AppColors.onSurfaceMuted),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Text(
                            _relativeTime(item.createdAt, now),
                            style: const TextStyle(
                                fontSize: 11, color: AppColors.onSurfaceMuted),
                          ),
                          if (_actionLabel != null) ...[
                            const SizedBox(width: 10),
                            Text(
                              _actionLabel!,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: AppColors.skyBlue,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  IconData get _icon => switch (item.kind) {
        NotificationKind.lowStock => Icons.inventory_2_outlined,
        NotificationKind.salesMilestone => Icons.celebration_outlined,
        NotificationKind.whatsappOrder => Icons.chat_bubble_outline_rounded,
        NotificationKind.payableDue => Icons.receipt_long_outlined,
      };

  Color get _tint => switch (item.kind) {
        NotificationKind.lowStock => AppColors.warning,
        NotificationKind.salesMilestone => AppColors.emerald,
        NotificationKind.whatsappOrder => AppColors.skyBlue,
        NotificationKind.payableDue => AppColors.error,
      };

  String? get _actionLabel => switch (item.kind) {
        NotificationKind.lowStock => 'Ver producto',
        NotificationKind.salesMilestone => 'Ver reportes',
        NotificationKind.whatsappOrder => 'Ver el pedido',
        NotificationKind.payableDue => 'Ver cuentas',
      };

  /// Abrir un aviso lo marca leído y lleva a donde se resuelve.
  Future<void> _open(BuildContext context, WidgetRef ref) async {
    // El router se toma antes del `await` de marcar leído.
    final router = GoRouter.maybeOf(context);
    final messenger = ScaffoldMessenger.of(context);
    final launch = ref.read(urlLauncherProvider);
    final notifier = ref.read(notificationsProvider.notifier);

    if (!item.isRead) await notifier.markRead(item.id);

    switch (item.kind) {
      case NotificationKind.whatsappOrder:
        // Pedido real (20 sep 2026): se atiende en la app, no en el chat.
        final folio = item.orderFolio;
        if (folio != null) {
          router?.push(AppRoutes.storeOrderPath(folio));
          return;
        }
        final phone = item.customerPhone;
        if (phone == null) return;
        final ok = await launch(
          whatsAppUri(phone),
          mode: LaunchMode.externalApplication,
        );
        if (!ok) {
          messenger.showSnackBar(
            const SnackBar(
                content: Text('No se pudo abrir WhatsApp en este equipo.')),
          );
        }
      case NotificationKind.lowStock:
        final id = item.productId;
        if (id != null) router?.go(AppRoutes.productDetailPath(id));
      case NotificationKind.salesMilestone:
        router?.go(AppRoutes.reports);
      case NotificationKind.payableDue:
        router?.go(AppRoutes.purchases);
    }
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) => const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.notifications_none_rounded,
                  size: 48, color: AppColors.onSurfaceMuted),
              SizedBox(height: 16),
              Text(
                'Nada que revisar',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.onSurface,
                ),
              ),
              SizedBox(height: 8),
              Text(
                'Aquí te avisamos cuando algo se esté agotando, cuando entre '
                'un pedido o cuando toque pagarle a un proveedor.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: AppColors.onSurfaceMuted),
              ),
            ],
          ),
        ),
      );
}

/// "hace 12 min", "ayer", "hace 3 días".
String _relativeTime(DateTime moment, DateTime now) {
  final diff = now.difference(moment);
  if (diff.inMinutes < 1) return 'hace un momento';
  if (diff.inMinutes < 60) return 'hace ${diff.inMinutes} min';
  if (diff.inHours < 24) {
    return 'hace ${diff.inHours} ${diff.inHours == 1 ? 'hora' : 'horas'}';
  }
  if (diff.inDays == 1) return 'ayer';
  return 'hace ${diff.inDays} días';
}
