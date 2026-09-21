import 'dart:async';

import 'package:dio/dio.dart';

import '../../../core/network/dio_client.dart';
import '../domain/public_catalog.dart';
import '../domain/store_order.dart';
import '../domain/whatsapp_order.dart';
import 'whatsapp_catalog_repository_impl.dart';

/// Pedidos web del lado del tendero — endpoints autenticados de
/// `whatsapp_catalog` (plan del 20 sep 2026):
///
/// | Método         | Endpoint                                   |
/// |----------------|--------------------------------------------|
/// | `list`         | `GET   /catalog-orders?scope=&since=&limit=` |
/// | `get`          | `GET   /catalog-orders/{folio}` (marca visto) |
/// | `updateStatus` | `PATCH /catalog-orders/{folio}/status`     |
/// | `edit`         | `PUT   /catalog-orders/{folio}`            |
abstract class StoreOrdersRepository {
  /// `scope`: `active` (nuevo + listo), `history` (entregado + cancelado) o
  /// `all`. `since` trae sólo lo modificado después — para resincronizar
  /// tras una caída del socket sin perder nada.
  Future<StoreOrderList> list({
    String scope = 'active',
    DateTime? since,
    int limit = 50,
  });

  /// Abrir el pedido lo marca como visto en el servidor.
  Future<StoreOrder> get(String folio);

  /// Listo · Entregado · Cancelar (con motivo) · Reabrir · ligar venta.
  /// Lanza [OrderConflict] (409) si alguien más cambió el pedido.
  Future<StoreOrder> updateStatus(
    String folio, {
    required OrderStatus status,
    CancelReason? cancelReason,
    String? saleId,
    DateTime? expectedUpdatedAt,
  });

  /// Edición tras cambios por chat — conserva la versión anterior.
  Future<StoreOrder> edit(String folio, StoreOrderEdit edit);
}

// ---------------------------------------------------------------------------
// Implementación real
// ---------------------------------------------------------------------------

class StoreOrdersRepositoryImpl implements StoreOrdersRepository {
  StoreOrdersRepositoryImpl({required this.client});

  final DioClient client;

  static const _base = '/api/v1/catalog-orders';

  @override
  Future<StoreOrderList> list({
    String scope = 'active',
    DateTime? since,
    int limit = 50,
  }) async {
    try {
      final response = await client.get<dynamic>(
        _base,
        queryParameters: {
          'scope': scope,
          if (since != null) 'since': since.toUtc().toIso8601String(),
          'limit': limit,
        },
      );
      final data = WhatsappCatalogRepositoryImpl.asMap(response.data);
      return StoreOrderList(
        items: [
          for (final raw in data['items'] as List? ?? const [])
            storeOrderFromJson(WhatsappCatalogRepositoryImpl.asMap(raw)),
        ],
        total: _int(data['total']),
        newCount: _int(data['new_count']),
        activeCount: _int(data['active_count']),
      );
    } on DioException catch (e) {
      throw _failure(e);
    }
  }

  @override
  Future<StoreOrder> get(String folio) async {
    try {
      final response =
          await client.get<dynamic>('$_base/${Uri.encodeComponent(folio)}');
      return storeOrderFromJson(
          WhatsappCatalogRepositoryImpl.asMap(response.data));
    } on DioException catch (e) {
      throw _failure(e, folio: folio);
    }
  }

  @override
  Future<StoreOrder> updateStatus(
    String folio, {
    required OrderStatus status,
    CancelReason? cancelReason,
    String? saleId,
    DateTime? expectedUpdatedAt,
  }) async {
    try {
      final response = await client.patch<dynamic>(
        '$_base/${Uri.encodeComponent(folio)}/status',
        data: {
          'status': status.apiValue,
          if (cancelReason != null) 'cancel_reason': cancelReason.apiValue,
          if (saleId != null) 'sale_id': saleId,
          if (expectedUpdatedAt != null)
            'expected_updated_at':
                expectedUpdatedAt.toUtc().toIso8601String(),
        },
      );
      return storeOrderFromJson(
          WhatsappCatalogRepositoryImpl.asMap(response.data));
    } on DioException catch (e) {
      throw _failure(e, folio: folio);
    }
  }

  @override
  Future<StoreOrder> edit(String folio, StoreOrderEdit edit) async {
    try {
      final response = await client.put<dynamic>(
        '$_base/${Uri.encodeComponent(folio)}',
        data: {
          'items': [
            for (final line in edit.lines)
              {
                'product_id': line.product.id,
                'quantity': line.quantity,
                if (line.notes != null && line.notes!.trim().isNotEmpty)
                  'notes': line.notes!.trim(),
              },
          ],
          'delivery_method': edit.deliveryMethod.apiValue,
          if (edit.deliveryAddress != null)
            'delivery_address': edit.deliveryAddress,
          if (edit.orderNotes != null) 'order_notes': edit.orderNotes,
          if (edit.customerName != null) 'customer_name': edit.customerName,
          if (edit.customerPhone != null)
            'customer_phone': edit.customerPhone,
          if (edit.expectedUpdatedAt != null)
            'expected_updated_at':
                edit.expectedUpdatedAt!.toUtc().toIso8601String(),
        },
      );
      return storeOrderFromJson(
          WhatsappCatalogRepositoryImpl.asMap(response.data));
    } on DioException catch (e) {
      throw _failure(e, folio: folio);
    }
  }

  // ---------------------------------------------------------------------------
  // Serialización (compartida con el canal WebSocket)
  // ---------------------------------------------------------------------------

  static StoreOrder storeOrderFromJson(Map<String, dynamic> j) => StoreOrder(
        order: WhatsappCatalogRepositoryImpl.savedOrderFromJson(j),
        seenAt: _date(j['seen_at']),
        seenByName: _text(j['seen_by_name']),
        attendedByName: _text(j['attended_by_name']),
        editedByName: _text(j['edited_by_name']),
        saleId: _text(j['sale_id']),
        revisions: [
          for (final raw in j['revisions'] as List? ?? const [])
            _revisionFromJson(WhatsappCatalogRepositoryImpl.asMap(raw)),
        ],
        possibleDuplicateOf: _text(j['possible_duplicate_of']),
      );

  static OrderRevision _revisionFromJson(Map<String, dynamic> j) =>
      OrderRevision(
        at: _date(j['at']) ?? DateTime.now(),
        byName: _text(j['by_name']),
        deliveryMethod: DeliveryMethod.values.firstWhere(
          (m) => m.apiValue == j['delivery_method'],
          orElse: () => DeliveryMethod.pickup,
        ),
        deliveryAddress: _text(j['delivery_address']),
        orderNotes: _text(j['order_notes']),
        lines: [
          for (final raw in j['items'] as List? ?? const [])
            WhatsappCatalogRepositoryImpl.lineFromJson(
                WhatsappCatalogRepositoryImpl.asMap(raw)),
        ],
        subtotalMxn: _double(j['subtotal_mxn']),
        deliveryFeeMxn: _double(j['delivery_fee_mxn']),
        totalMxn: _double(j['total_mxn']),
      );

  static Exception _failure(DioException e, {String? folio}) {
    final status = e.response?.statusCode;
    final detail = _detail(e);
    switch (status) {
      case 409:
        return OrderConflict(detail.isEmpty
            ? 'Alguien más cambió este pedido. Se recarga con la versión actual.'
            : detail);
      case 404:
        return OrderNotFound(folio ?? '');
      case 400:
      case 422:
        return OrderActionRejected(
            detail.isEmpty ? 'No se pudo aplicar el cambio.' : detail);
      default:
        return const CatalogUnavailable();
    }
  }

  static String _detail(DioException e) {
    final data = e.response?.data;
    if (data is Map) {
      final detail = data['detail'];
      if (detail is String) return detail;
      if (detail is List) {
        return detail
            .map((d) => d is Map ? (d['msg'] ?? d).toString() : d.toString())
            .join('. ');
      }
    }
    return '';
  }

  static String? _text(dynamic v) {
    if (v == null) return null;
    final s = v.toString().trim();
    return s.isEmpty ? null : s;
  }

  static DateTime? _date(dynamic v) =>
      v == null ? null : DateTime.tryParse(v.toString())?.toLocal();

  static double _double(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0;
  }

  static int _int(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.round();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }
}

// ---------------------------------------------------------------------------
// Mock — widget tests y demos; emite eventos por `events` para simular el WS
// ---------------------------------------------------------------------------

class StoreOrdersRepositoryMock implements StoreOrdersRepository {
  StoreOrdersRepositoryMock({
    List<StoreOrder>? orders,
    this.latency = const Duration(milliseconds: 150),
    DateTime Function()? now,
    this.userName = 'Eduardo',
  })  : now = now ?? DateTime.now,
        _orders = {for (final o in orders ?? const <StoreOrder>[]) o.folio: o};

  final Duration latency;
  final DateTime Function() now;
  final String userName;
  final Map<String, StoreOrder> _orders;

  final _events = StreamController<OrderEvent>.broadcast();

  /// Eventos que el mock emite cuando algo cambia — el provider los consume
  /// igual que los del WebSocket real.
  Stream<OrderEvent> get events => _events.stream;

  List<StoreOrder> get all => _orders.values.toList();

  /// Simula un pedido nuevo que entra por la vitrina.
  void receive(StoreOrder order) {
    _orders[order.folio] = order;
    _events.add(OrderEvent(OrderEventType.newOrder, order: order));
  }

  void dispose() => _events.close();

  /// Sin latencia no se crea `Timer` alguno: en `testWidgets` un timer real
  /// pendiente al cerrar el test lo hace fallar.
  Future<void> _wait() =>
      latency == Duration.zero ? Future.value() : Future<void>.delayed(latency);

  @override
  Future<StoreOrderList> list({
    String scope = 'active',
    DateTime? since,
    int limit = 50,
  }) async {
    await _wait();
    var items = _orders.values.where((o) => switch (scope) {
          'active' => o.status.isActive,
          'history' => o.status.isClosed,
          _ => true,
        });
    if (since != null) {
      items = items.where(
          (o) => o.order.updatedAt != null && o.order.updatedAt!.isAfter(since));
    }
    final sorted = items.toList()
      ..sort((a, b) => b.order.issuedAt.compareTo(a.order.issuedAt));
    return StoreOrderList(
      items: sorted.take(limit).toList(),
      total: sorted.length,
      newCount: _orders.values
          .where((o) => o.status == OrderStatus.newOrder && !o.isSeen)
          .length,
      activeCount: _orders.values.where((o) => o.status.isActive).length,
    );
  }

  @override
  Future<StoreOrder> get(String folio) async {
    await _wait();
    final order = _orders[folio];
    if (order == null) throw OrderNotFound(folio);
    if (order.isSeen) return order;
    final seen = order.copyWith(
      seenAt: now(),
      seenByName: userName,
      order: order.order.copyWith(updatedAt: now()),
    );
    _orders[folio] = seen;
    _events.add(OrderEvent(OrderEventType.updated, order: seen));
    return seen;
  }

  @override
  Future<StoreOrder> updateStatus(
    String folio, {
    required OrderStatus status,
    CancelReason? cancelReason,
    String? saleId,
    DateTime? expectedUpdatedAt,
  }) async {
    await _wait();
    final current = _orders[folio];
    if (current == null) throw OrderNotFound(folio);
    _checkVersion(current, expectedUpdatedAt);
    if (status == OrderStatus.cancelled && cancelReason == null) {
      throw const OrderActionRejected('Indica el motivo de la cancelación.');
    }
    if (status == OrderStatus.delivered &&
        saleId == null &&
        current.saleId == null) {
      throw const OrderActionRejected(
          'Para entregar un pedido hay que cobrarlo en caja: la venta descuenta el inventario.');
    }
    if (current.status.isClosed && status != OrderStatus.newOrder && status != current.status) {
      throw OrderActionRejected(
          'No se puede pasar un pedido de ${current.status.label} a ${status.label}.');
    }
    if (current.status == OrderStatus.delivered &&
        current.saleId != null &&
        status != current.status) {
      throw const OrderActionRejected(
          'Este pedido ya se cobró en caja. Si hay que devolverlo, hazlo desde la venta.');
    }
    final updated = current.copyWith(
      order: current.order.copyWith(
        status: status,
        statusChangedAt: now(),
        cancelReason: () =>
            status == OrderStatus.cancelled ? cancelReason : null,
        updatedAt: now(),
      ),
      attendedByName: userName,
      seenAt: current.seenAt ?? now(),
      seenByName: current.seenByName ?? userName,
      saleId: saleId == null ? null : () => saleId,
    );
    _orders[folio] = updated;
    _events.add(OrderEvent(OrderEventType.updated, order: updated));
    return updated;
  }

  @override
  Future<StoreOrder> edit(String folio, StoreOrderEdit edit) async {
    await _wait();
    final current = _orders[folio];
    if (current == null) throw OrderNotFound(folio);
    _checkVersion(current, edit.expectedUpdatedAt);
    if (!current.canEdit) {
      throw const OrderActionRejected(
          'Sólo se puede editar un pedido que sigue activo. Reábrelo primero.');
    }
    final previous = current.order;
    final revision = OrderRevision(
      at: now(),
      byName: userName,
      deliveryMethod: previous.draft.deliveryMethod,
      deliveryAddress: previous.draft.deliveryAddress,
      orderNotes: previous.draft.orderNotes,
      lines: previous.draft.lines,
      subtotalMxn: previous.totals.subtotalMxn,
      deliveryFeeMxn: previous.totals.deliveryFeeMxn,
      totalMxn: previous.totals.totalMxn,
    );
    final subtotal =
        edit.lines.fold<double>(0, (sum, l) => sum + l.subtotalMxn);
    final fee = edit.deliveryMethod == DeliveryMethod.delivery
        ? previous.totals.deliveryFeeMxn
        : 0.0;
    final total = subtotal + fee;
    final tendered = previous.draft.cashTenderedMxn;
    final draft = WhatsAppOrderDraft(
      customerName: edit.customerName ?? previous.draft.customerName,
      customerPhone: edit.customerPhone ?? previous.draft.customerPhone,
      deliveryMethod: edit.deliveryMethod,
      deliveryAddress: edit.deliveryAddress,
      paymentMethod: previous.draft.paymentMethod,
      cashTenderedMxn: tendered,
      orderNotes: edit.orderNotes,
      lines: edit.lines,
    );
    final updated = current.copyWith(
      order: previous.copyWith(
        draft: draft,
        totals: WhatsAppOrderBuild(
          waLink: previous.totals.waLink,
          formattedText: previous.totals.formattedText,
          subtotalMxn: subtotal,
          deliveryFeeMxn: fee,
          totalMxn: total,
          changeMxn: tendered != null && tendered >= total ? tendered - total : null,
          itemCount: edit.lines.length,
        ),
        storeEditedAt: now(),
        updatedAt: now(),
      ),
      editedByName: userName,
      attendedByName: userName,
      revisions: [...current.revisions, revision],
    );
    _orders[folio] = updated;
    _events.add(OrderEvent(OrderEventType.updated, order: updated));
    return updated;
  }

  void _checkVersion(StoreOrder current, DateTime? expected) {
    final actual = current.order.updatedAt;
    if (expected == null || actual == null) return;
    if (actual != expected) {
      throw const OrderConflict(
          'Alguien más cambió este pedido. Se recarga con la versión actual.');
    }
  }
}
