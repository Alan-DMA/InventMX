import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../account/presentation/data_scope_provider.dart';
import '../../management/domain/app_permission.dart';
import '../../management/presentation/management_provider.dart';
import '../../auth/presentation/login_provider.dart' show currentUserNameProvider;
import '../../auth/data/auth_repository.dart'
    show dioClientProvider, secureStorageProvider;
import '../../sales_pos/data/sales_repository.dart';
import '../../sales_pos/domain/sale_summary.dart';
import '../../saas_admin/presentation/saas_provider.dart' show clockProvider;
import '../../support/domain/support_models.dart';
import '../../support/presentation/support_provider.dart';
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
    // Cambiar de usuario reconstruye el repositorio: los avisos leídos son
    // de cada quien, en memoria y en disco (QA Sep 23).
    ownerEmail: ref.watch(currentUserNameProvider),
    resolveWarehouseScope: () async => ref.read(dataScopeProvider),
  ),
);

// ---------------------------------------------------------------------------
// Resumen del día
// ---------------------------------------------------------------------------

class DailySnapshotNotifier extends AsyncNotifier<DailySnapshot> {
  @override
  Future<DailySnapshot> build() {
    // Cifras del alcance elegido en la leyenda (Fase 2): al cambiarlo se
    // recalculan; la campana lo sigue porque observa este resumen.
    ref.watch(dataScopeProvider);
    return ref.watch(dashboardRepositoryProvider).getTodaySnapshot();
  }

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
  ///
  /// Puertas por rol (Fase A, A9): cada aviso aparece sólo si el rol tiene el
  /// permiso del dato que lo origina — y los pedidos ni se consultan sin
  /// `sales.view` (el servidor los rechazaría y el socket no debe abrirse).
  @override
  Future<List<StoreNotification>> build() async {
    final permissions = ref.watch(myPermissionsProvider);
    // Los avisos de stock salen del resumen del Inicio: se espera el vigente
    // y se recalculan cuando cambia (p. ej. al cambiar de almacén). Sin esto
    // la campana leía la foto anterior del repositorio (QA de Eduardo, Sep 27).
    try {
      await ref.watch(dailySnapshotProvider.future);
    } catch (_) {
      // Sin resumen, el repositorio intenta por su cuenta o devuelve vacío.
    }
    final base = await ref.watch(dashboardRepositoryProvider).listNotifications();
    final orders = permissions.contains(Permissions.salesView)
        ? ref.watch(storeOrdersProvider).valueOrNull
        : null;
    return filterByPermissions(
        mergeOrderNotifications(base, orders), permissions);
  }

  static const orderIdPrefix = 'order-';
  static const supportIdPrefix = 'support-';

  /// Permiso que hace visible cada tipo de aviso. Coincide con el destino al
  /// tocarlo: nadie recibe un aviso cuyo destino el router le rebotaría.
  /// `null` = no pide permiso: Soporte es de todos los roles (P25).
  static String? permissionFor(NotificationKind kind) => switch (kind) {
        NotificationKind.lowStock => Permissions.inventoryView,
        NotificationKind.payableDue => Permissions.purchasesView,
        NotificationKind.whatsappOrder => Permissions.salesView,
        NotificationKind.salesMilestone => Permissions.reportsViewBasic,
        NotificationKind.supportReply => null,
      };

  static List<StoreNotification> filterByPermissions(
    List<StoreNotification> items,
    Set<String> permissions,
  ) =>
      items
          .where((n) {
            final needed = permissionFor(n.kind);
            return needed == null || permissions.contains(needed);
          })
          .toList();

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

  /// Un aviso por caso con respuesta de soporte sin abrir. Se combina al
  /// mostrar y al contar (no dentro de `build`): que llegue una respuesta no
  /// recarga los demás avisos. Se "lee" al abrir el caso (el servidor limpia
  /// la marca), igual que un pedido al abrirlo.
  static List<StoreNotification> mergeSupportNotifications(
    List<StoreNotification> base,
    List<SupportCase>? replies,
  ) {
    if (replies == null || replies.isEmpty) return base;
    return [
      for (final c in replies) supportNotification(c),
      ...base.where((n) => n.kind != NotificationKind.supportReply),
    ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  static StoreNotification supportNotification(SupportCase c) =>
      StoreNotification(
        id: '$supportIdPrefix${c.id}',
        kind: NotificationKind.supportReply,
        title: 'Soporte respondió tu caso ${c.number}',
        body: c.topicTitle,
        createdAt: c.lastMessageAt,
        isRead: !c.unread,
        caseId: c.id,
      );

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
    // Los avisos de pedido y de soporte se leen al abrir el pedido o el caso.
    if (id.startsWith(orderIdPrefix) || id.startsWith(supportIdPrefix)) return;
    await _repo.markRead(id);
    await _reload();
  }

  Future<void> markAllRead() async {
    await _repo.markAllRead();
    await _reload();
  }

  Future<void> _reload() async {
    final permissions = ref.read(myPermissionsProvider);
    state = await AsyncValue.guard(() async => filterByPermissions(
          mergeOrderNotifications(
            await _repo.listNotifications(),
            permissions.contains(Permissions.salesView)
                ? ref.read(storeOrdersProvider).valueOrNull
                : null,
          ),
          permissions,
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
  // + respuestas de soporte sin abrir (todas cuentan: sólo se listan ésas)
  final replies = ref.watch(supportRepliesProvider).valueOrNull?.length ?? 0;
  return items.where((n) => !n.isRead).length + replies;
});

// ---------------------------------------------------------------------------
// Últimas ventas (Fase 3) — condensado del mismo repo que alimenta el Kardex
// ---------------------------------------------------------------------------

/// Las 3 ventas más recientes de hoy, para la vista condensada del Dashboard.
/// Usa `salesRepositoryProvider` directo (no `salesKardexProvider`, que es
/// `autoDispose` y está atado al ciclo de vida de la pantalla de Kardex).
final recentSalesProvider = FutureProvider<List<SaleSummary>>((ref) async {
  // Las ventas siguen el alcance de la leyenda (Fase 2).
  ref.watch(dataScopeProvider);
  final now = ref.watch(clockProvider)();
  final today = DateTime(now.year, now.month, now.day);
  final page = await ref.watch(salesRepositoryProvider).getSales(
        query: SalesQuery(dateFrom: today),
        page: 1,
        pageSize: 3,
      );
  return page.items;
});
