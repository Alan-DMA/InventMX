import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/data/auth_repository.dart'
    show dioClientProvider, secureStorageProvider;
import '../../sales_pos/data/sales_repository.dart';
import '../../sales_pos/domain/sale_summary.dart';
import '../../saas_admin/presentation/saas_provider.dart' show clockProvider;
import '../../whatsapp_catalog/domain/store_order.dart';
import '../../whatsapp_catalog/domain/whatsapp_order.dart';
import '../../whatsapp_catalog/presentation/store_orders_provider.dart';
import '../data/dashboard_repository.dart';
import '../domain/daily_snapshot.dart';
import '../domain/store_notification.dart';

/// Proveedor del repositorio del Centro de Mando.
/// Conectado en producción al endpoint real de analítica `GET /api/v1/analytics/dashboard`.
final dashboardRepositoryProvider = Provider<DashboardRepository>(
  (ref) => DashboardRepositoryImpl(
    client: ref.watch(dioClientProvider),
    storage: ref.watch(secureStorageProvider),
  ),
);

// ---------------------------------------------------------------------------
// Resumen del día
// ---------------------------------------------------------------------------

class DailySnapshotNotifier extends AsyncNotifier<DailySnapshot> {
  @override
  Future<DailySnapshot> build() =>
      ref.watch(dashboardRepositoryProvider).getTodaySnapshot();

  Future<void> refresh() async {
    state = await AsyncValue.guard(
      ref.read(dashboardRepositoryProvider).getTodaySnapshot,
    );
  }
}

final dailySnapshotProvider =
    AsyncNotifierProvider<DailySnapshotNotifier, DailySnapshot>(
  DailySnapshotNotifier.new,
);

// ---------------------------------------------------------------------------
// Notificaciones
// ---------------------------------------------------------------------------

class NotificationsNotifier extends AsyncNotifier<List<StoreNotification>> {
  /// Híbrido (20 sep 2026): los avisos de **pedido web** salen de los pedidos
  /// reales (`storeOrdersProvider`, en vivo por WebSocket); los demás siguen
  /// en mock hasta que exista su backend. Un pedido cuenta como aviso mientras
  /// está en Nuevo; "leído" = alguien ya lo abrió (`seen`).
  @override
  Future<List<StoreNotification>> build() async {
    final base = await ref.watch(dashboardRepositoryProvider).listNotifications();
    final orders = ref.watch(storeOrdersProvider).valueOrNull;
    return mergeOrderNotifications(base, orders);
  }

  static const orderIdPrefix = 'order-';

  static List<StoreNotification> mergeOrderNotifications(
    List<StoreNotification> base,
    StoreOrderList? orders,
  ) {
    final fromOrders = [
      for (final o in orders?.items ?? const <StoreOrder>[])
        if (o.status == OrderStatus.newOrder) orderNotification(o),
    ];
    final others =
        base.where((n) => n.kind != NotificationKind.whatsappOrder);
    return [...fromOrders, ...others]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  static StoreNotification orderNotification(StoreOrder o) {
    final saved = o.order;
    final delivery = saved.draft.deliveryMethod == DeliveryMethod.delivery;
    return StoreNotification(
      id: '$orderIdPrefix${saved.folio}',
      kind: NotificationKind.whatsappOrder,
      title: 'Pedido nuevo de ${saved.draft.customerName}',
      body: '${saved.itemCount} pzas · \$${saved.totals.totalMxn.toStringAsFixed(2)} · '
          '${delivery ? 'a domicilio' : 'recoger en tienda'} · ${saved.folio}',
      createdAt: saved.issuedAt,
      isRead: o.isSeen,
      customerPhone: saved.draft.customerPhone,
      orderFolio: saved.folio,
    );
  }

  DashboardRepository get _repo => ref.read(dashboardRepositoryProvider);

  Future<void> markRead(String id) async {
    // Los avisos de pedido se marcan al abrir el pedido (seen), no aquí.
    if (id.startsWith(orderIdPrefix)) return;
    await _repo.markRead(id);
    await _reload();
  }

  Future<void> markAllRead() async {
    await _repo.markAllRead();
    await _reload();
  }

  Future<void> _reload() async {
    state = await AsyncValue.guard(() async => mergeOrderNotifications(
          await _repo.listNotifications(),
          ref.read(storeOrdersProvider).valueOrNull,
        ));
  }
}

final notificationsProvider =
    AsyncNotifierProvider<NotificationsNotifier, List<StoreNotification>>(
  NotificationsNotifier.new,
);

/// Lo que va en el contador de la campana. `0` mientras carga: no se anuncia
/// un número que todavía no se sabe.
final unreadNotificationsProvider = Provider<int>((ref) {
  final items = ref.watch(notificationsProvider).valueOrNull;
  if (items == null) return 0;
  return items.where((n) => !n.isRead).length;
});

// ---------------------------------------------------------------------------
// Últimas ventas (Fase 3) — condensado del mismo repo que alimenta el Kardex
// ---------------------------------------------------------------------------

/// Las 3 ventas más recientes de hoy, para la vista condensada del Dashboard.
/// Usa `salesRepositoryProvider` directo (no `salesKardexProvider`, que es
/// `autoDispose` y está atado al ciclo de vida de la pantalla de Kardex).
final recentSalesProvider = FutureProvider<List<SaleSummary>>((ref) async {
  final now = ref.watch(clockProvider)();
  final today = DateTime(now.year, now.month, now.day);
  final page = await ref.watch(salesRepositoryProvider).getSales(
        query: SalesQuery(dateFrom: today),
        page: 1,
        pageSize: 3,
      );
  return page.items;
});
