import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../sales_pos/data/sales_repository.dart';
import '../../sales_pos/domain/sale_summary.dart';
import '../../saas_admin/presentation/saas_provider.dart' show clockProvider;
import '../data/dashboard_repository.dart';
import '../domain/daily_snapshot.dart';
import '../domain/store_notification.dart';

/// 100% mock en esta pasada (decisión de Eduardo, Sep 2026). El mapa de qué
/// endpoint sustituirá cada dato está en [DashboardRepository].
final dashboardRepositoryProvider = Provider<DashboardRepository>(
  (_) => DashboardRepositoryMock(),
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
  @override
  Future<List<StoreNotification>> build() =>
      ref.watch(dashboardRepositoryProvider).listNotifications();

  DashboardRepository get _repo => ref.read(dashboardRepositoryProvider);

  Future<void> markRead(String id) async {
    await _repo.markRead(id);
    await _reload();
  }

  Future<void> markAllRead() async {
    await _repo.markAllRead();
    await _reload();
  }

  Future<void> _reload() async {
    state = await AsyncValue.guard(_repo.listNotifications);
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
