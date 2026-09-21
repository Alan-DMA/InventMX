import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../auth/data/auth_repository.dart';
import '../data/order_events_channel.dart';
import '../data/store_orders_repository.dart';
import '../domain/store_order.dart';
import '../domain/whatsapp_order.dart';

// ---------------------------------------------------------------------------
// Infraestructura
// ---------------------------------------------------------------------------

final storeOrdersRepositoryProvider = Provider<StoreOrdersRepository>(
  (ref) => StoreOrdersRepositoryImpl(client: ref.watch(dioClientProvider)),
);

/// Eventos en vivo del backend. Los tests lo sustituyen por
/// `StoreOrdersRepositoryMock.events`.
final orderEventsProvider = Provider<Stream<OrderEvent>>((ref) {
  final storage = ref.watch(secureStorageProvider);
  return OrderEventsChannel(
    apiBaseUrl: getEffectiveApiBaseUrl(),
    readToken: storage.readAccessToken,
  ).events();
});

// ---------------------------------------------------------------------------
// Pedidos activos (nuevo + listo) — la lista viva del tendero
// ---------------------------------------------------------------------------

/// Pedidos activos con el badge del servidor. Escucha el canal en vivo:
/// `order.new` entra al frente y dispara el banner; `order.updated`
/// reemplaza o saca de la lista; `reconnected` vuelve a pedir al servidor
/// lo que cambió (`since`) para no perder nada mientras el socket estuvo caído.
final storeOrdersProvider =
    AsyncNotifierProvider<StoreOrdersNotifier, StoreOrderList>(
  StoreOrdersNotifier.new,
);

class StoreOrdersNotifier extends AsyncNotifier<StoreOrderList> {
  StreamSubscription<OrderEvent>? _events;
  DateTime? _lastSync;

  StoreOrdersRepository get _repo => ref.read(storeOrdersRepositoryProvider);

  @override
  Future<StoreOrderList> build() async {
    _events?.cancel();
    _events = ref.read(orderEventsProvider).listen(_onEvent);
    ref.onDispose(() => _events?.cancel());
    return _load();
  }

  Future<StoreOrderList> _load() async {
    final list = await _repo.list(scope: 'active');
    _lastSync = DateTime.now();
    return list;
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(_load);
  }

  // ── Eventos del socket ────────────────────────────────────────────────────

  void _onEvent(OrderEvent event) {
    switch (event.type) {
      case OrderEventType.newOrder:
        final order = event.order;
        if (order == null) return;
        _merge(order);
        ref.read(incomingOrderProvider.notifier).state = order;
      case OrderEventType.updated:
        final order = event.order;
        if (order == null) return;
        _merge(order);
        ref.invalidate(storeOrderDetailProvider(order.folio));
        ref.invalidate(storeOrdersHistoryProvider);
      case OrderEventType.reconnected:
        _resync();
      case OrderEventType.hello:
      case OrderEventType.ping:
        break;
    }
  }

  /// Tras reconectar: lo modificado desde la última sincronización se
  /// mezcla; si no hay marca, se recarga todo.
  Future<void> _resync() async {
    final since = _lastSync;
    if (since == null) return refresh();
    try {
      final delta = await _repo.list(scope: 'all', since: since);
      for (final order in delta.items) {
        _merge(order, counts: delta);
      }
      _lastSync = DateTime.now();
    } catch (_) {
      await refresh();
    }
  }

  /// Inserta/reemplaza el pedido en la lista activa; los cerrados salen.
  /// Los conteos se recalculan de lo que hay en memoria hasta la siguiente
  /// carga del servidor (que siempre manda).
  void _merge(StoreOrder order, {StoreOrderList? counts}) {
    final current = state.valueOrNull ?? const StoreOrderList();
    final items = [...current.items]
      ..removeWhere((o) => o.folio == order.folio);
    if (order.status.isActive) {
      items.insert(0, order);
      items.sort((a, b) => b.order.issuedAt.compareTo(a.order.issuedAt));
    }
    state = AsyncData(StoreOrderList(
      items: items,
      total: items.length,
      newCount: counts?.newCount ??
          items
              .where((o) => o.status == OrderStatus.newOrder && !o.isSeen)
              .length,
      activeCount: counts?.activeCount ?? items.length,
    ));
  }

  // ── Acciones ──────────────────────────────────────────────────────────────

  /// Listo · Entregado · Cancelar · Reabrir · ligar venta. Ante 409 se
  /// recarga el pedido y se propaga para que la pantalla lo diga.
  Future<StoreOrder> setStatus(
    String folio,
    OrderStatus status, {
    CancelReason? cancelReason,
    String? saleId,
    DateTime? expectedUpdatedAt,
  }) async {
    try {
      final updated = await _repo.updateStatus(
        folio,
        status: status,
        cancelReason: cancelReason,
        saleId: saleId,
        expectedUpdatedAt: expectedUpdatedAt,
      );
      _afterChange(updated);
      return updated;
    } on OrderConflict {
      ref.invalidate(storeOrderDetailProvider(folio));
      await refresh();
      rethrow;
    }
  }

  Future<StoreOrder> edit(String folio, StoreOrderEdit edit) async {
    try {
      final updated = await _repo.edit(folio, edit);
      _afterChange(updated);
      return updated;
    } on OrderConflict {
      ref.invalidate(storeOrderDetailProvider(folio));
      await refresh();
      rethrow;
    }
  }

  /// "Cobrar en caja" terminó: la venta queda ligada y el pedido entregado.
  /// Nunca falla hacia afuera — la venta ya se hizo; si esto no llega, el
  /// tendero lo marca a mano.
  Future<void> linkSale(String folio, String saleId) async {
    try {
      final updated = await _repo.updateStatus(
        folio,
        status: OrderStatus.delivered,
        saleId: saleId,
      );
      _afterChange(updated);
    } catch (_) {
      await refresh();
    }
  }

  void _afterChange(StoreOrder updated) {
    _merge(updated);
    ref.invalidate(storeOrderDetailProvider(updated.folio));
    ref.invalidate(storeOrdersHistoryProvider);
  }
}

/// Badge de "Pedidos web": nuevos sin ver, siempre del servidor.
final newOrdersCountProvider = Provider<int>(
  (ref) => ref.watch(storeOrdersProvider).valueOrNull?.newCount ?? 0,
);

/// Nuevos + listos (tarjeta de Inicio).
final activeOrdersCountProvider = Provider<int>(
  (ref) => ref.watch(storeOrdersProvider).valueOrNull?.activeCount ?? 0,
);

/// El último pedido que entró por el socket — el banner lo muestra y lo
/// limpia al descartarlo o abrirlo.
final incomingOrderProvider = StateProvider<StoreOrder?>((_) => null);

// ---------------------------------------------------------------------------
// Historial y detalle
// ---------------------------------------------------------------------------

final storeOrdersHistoryProvider =
    FutureProvider.autoDispose<StoreOrderList>(
  (ref) => ref.watch(storeOrdersRepositoryProvider).list(scope: 'history'),
);

/// Detalle por folio. Abrirlo marca el pedido como visto en el servidor;
/// el evento `order.updated` que eso genera actualiza la lista y el badge.
final storeOrderDetailProvider =
    FutureProvider.autoDispose.family<StoreOrder, String>(
  (ref, folio) => ref.watch(storeOrdersRepositoryProvider).get(folio),
);

/// Pestaña que debe mostrar "Pedidos web" la próxima vez que se muestre
/// (0 = Activos, 1 = Historial). GoRouter reutiliza la pantalla padre al
/// volver desde el detalle y no la reconstruye por un cambio de query, así
/// que el detalle pide la pestaña por aquí antes de navegar.
final storeOrdersTabRequestProvider = StateProvider<int?>((_) => null);
