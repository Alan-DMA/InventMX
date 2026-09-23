import 'package:dio/dio.dart';

import '../../../core/network/dio_client.dart';
import '../../../core/storage/secure_storage.dart';
import '../domain/daily_snapshot.dart';
import '../domain/stock_alert.dart';
import '../domain/store_notification.dart';

// ---------------------------------------------------------------------------
// Contrato
// ---------------------------------------------------------------------------

/// Datos del Centro de mando (N-08) y del apartado de Notificaciones.
abstract class DashboardRepository {
  Future<DailySnapshot> getTodaySnapshot();

  Future<List<StoreNotification>> listNotifications();

  Future<void> markRead(String id);

  Future<void> markAllRead();
}

// ---------------------------------------------------------------------------
// Implementación Real contra FastAPI (`GET /api/v1/analytics/dashboard`)
// ---------------------------------------------------------------------------

class DashboardRepositoryImpl implements DashboardRepository {
  DashboardRepositoryImpl({
    required this.client,
    this.storage,
    this.ownerEmail,
  });

  final DioClient client;
  final SecureStorage? storage;

  /// Quién está en sesión. El provider lo observa, así que al cambiar de
  /// usuario se construye otro repositorio y los avisos leídos en memoria
  /// no se arrastran de una sesión a la siguiente (QA de Eduardo, Sep 23).
  final String? ownerEmail;
  final Set<String> _readNotificationIds = {};
  bool _readIdsLoaded = false;
  DailySnapshot? _lastSnapshot;

  static const String _kReadNotificationsKey = 'nexus_read_notification_ids';

  /// Clave con dueño: los avisos que marcó una persona no aparecen leídos
  /// para la siguiente que entre en el mismo teléfono (QA de Eduardo, Sep 23).
  String get _readKey =>
      SecureStorage.scopedKey(_kReadNotificationsKey, ownerEmail);

  // Carga los identificadores de notificaciones ya leídas por el usuario
  Future<void> _loadReadIds() async {
    if (_readIdsLoaded) return;
    try {
      if (storage != null) {
        final raw = await storage!.read(_readKey);
        if (raw != null && raw.trim().isNotEmpty) {
          _readNotificationIds.addAll(
            raw.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty),
          );
        }
      }
    } catch (_) {}
    _readIdsLoaded = true;
  }

  // Persiste en almacenamiento local los identificadores leídos
  Future<void> _saveReadIds() async {
    try {
      if (storage != null) {
        await storage!.write(
          _readKey,
          _readNotificationIds.join(','),
        );
      }
    } catch (_) {}
  }

  static dynamic _unwrap(dynamic body) =>
      body is Map && body.containsKey('data') ? body['data'] : body;

  /// Los `Decimal` del backend llegan como string con `response_model`.
  static double _num(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0.0;
  }

  @override
  Future<DailySnapshot> getTodaySnapshot() async {
    try {
      final response = await client.get(
        '/api/v1/analytics/dashboard',
        queryParameters: {'period': 'TODAY', 'compare_previous': true},
      );
      final raw = _unwrap(response.data);
      if (raw is! Map) {
        throw const DashboardException('Respuesta inválida recibida del servidor.');
      }
      var snapshot = DailySnapshot.fromJson(Map<String, dynamic>.from(raw));
      // "Por pagar a proveedores" es la deuda pendiente real (mismo resumen
      // que usa el hub de Compras), no las órdenes por recibir. Es una
      // lectura complementaria: si falla, la tarjeta queda en $0 sin tumbar
      // el Inicio.
      try {
        final payables = await client.get('/api/v1/accounts-payable/summary');
        final pr = _unwrap(payables.data);
        if (pr is Map) {
          snapshot = snapshot.withPayables(
            dueMxn: _num(pr['total_pending_mxn']),
            overdueCount: _num(pr['overdue_count']).round(),
          );
        }
      } on DioException {
        // Sin permiso o sin red: la tarjeta no miente, muestra $0.
      }
      _lastSnapshot = snapshot;
      return snapshot;
    } on DioException catch (e) {
      throw DashboardException(
        e.response?.statusCode == 401
            ? 'Sesión expirada. Inicie sesión nuevamente.'
            : 'No se pudo conectar con el servidor de Nexus. Revise su conexión.',
      );
    }
  }

  @override
  Future<List<StoreNotification>> listNotifications() async {
    await _loadReadIds();
    DailySnapshot? snapshot = _lastSnapshot;
    if (snapshot == null) {
      try {
        snapshot = await getTodaySnapshot();
      } catch (_) {
        return const [];
      }
    }

    final List<StoreNotification> notifications = [];

    // 1. Alertas de inventario crítico (productos agotados o con existencias bajas)
    for (final alert in snapshot.lowStockAlerts) {
      final notifId = 'stock-${alert.productId}';
      notifications.add(
        StoreNotification(
          id: notifId,
          kind: NotificationKind.lowStock,
          title: alert.isOutOfStock
              ? '${alert.productName} agotado'
              : '${alert.productName} por agotarse',
          body: alert.isOutOfStock
              ? 'Sin existencias en almacén. Se requiere surtir inventario.'
              : 'Quedan ${alert.availableStock} pzas (mínimo: ${alert.minStock}).',
          createdAt: DateTime.now().subtract(const Duration(minutes: 5)),
          isRead: _readNotificationIds.contains(notifId),
          productId: alert.productId,
        ),
      );
    }

    // 2. Alertas de órdenes de compra a proveedores (pendientes o vencidas)
    for (final po in snapshot.pendingPurchasesAlerts) {
      final notifId = 'po-${po.id}';
      notifications.add(
        StoreNotification(
          id: notifId,
          kind: NotificationKind.payableDue,
          title: po.isOverdue
              ? 'Orden de compra ${po.folio} vencida'
              : 'Orden de compra ${po.folio} pendiente',
          body: 'Proveedor: ${po.supplierName} · \$${po.totalMxn.toStringAsFixed(2)} MXN.',
          createdAt: DateTime.now().subtract(Duration(days: po.daysPending)),
          isRead: _readNotificationIds.contains(notifId),
        ),
      );
    }

    return notifications;
  }

  @override
  Future<void> markRead(String id) async {
    await _loadReadIds();
    _readNotificationIds.add(id);
    await _saveReadIds();
  }

  @override
  Future<void> markAllRead() async {
    await _loadReadIds();
    final current = await listNotifications();
    for (final n in current) {
      _readNotificationIds.add(n.id);
    }
    await _saveReadIds();
  }
}

class DashboardException implements Exception {
  const DashboardException(this.message);
  final String message;
  @override
  String toString() => message;
}

// ---------------------------------------------------------------------------
// Mock — determinista, para que la pantalla se vea igual en cada arranque
// ---------------------------------------------------------------------------

class DashboardRepositoryMock implements DashboardRepository {
  DashboardRepositoryMock({DateTime? now}) : _now = now ?? DateTime.now();

  /// Las fechas de la semilla son **relativas** a este momento: con fechas
  /// fijas, al probar en el teléfono los avisos aparecerían de hace meses.
  final DateTime _now;

  static const _fakeDelay = Duration(milliseconds: 400);

  late final List<StoreNotification> _notifications = _seedNotifications();

  @override
  Future<DailySnapshot> getTodaySnapshot() async {
    await Future.delayed(_fakeDelay);
    return const DailySnapshot(
      salesTodayMxn: 3184.50,
      salesTodayCount: 42,
      salesYesterdayMxn: 2790.00,
      marginTodayMxn: 891.70,
      lowStockCount: 6,
      outOfStockCount: 2,
      lowStockAlerts: [
        StockAlertItem(
          productId: 'prod-014',
          productName: 'Fabuloso 1 L',
          availableStock: 0,
          isOutOfStock: true,
        ),
        StockAlertItem(
          productId: 'prod-001',
          productName: 'Coca-Cola 600 ml',
          availableStock: 4,
          isOutOfStock: false,
        ),
        StockAlertItem(
          productId: 'prod-022',
          productName: 'Sabritas Original 45 g',
          availableStock: 3,
          isOutOfStock: false,
        ),
      ],
      payablesDueMxn: 3240.00,
      payablesOverdueCount: 1,
      isCashSessionOpen: true,
      cashExpectedMxn: 2465.50,
    );
  }

  @override
  Future<List<StoreNotification>> listNotifications() async {
    await Future.delayed(_fakeDelay);
    return List.unmodifiable(_notifications);
  }

  @override
  Future<void> markRead(String id) async {
    await Future.delayed(_fakeDelay);
    final index = _notifications.indexWhere((n) => n.id == id);
    if (index < 0) return;
    _notifications[index] = _notifications[index].copyWith(isRead: true);
  }

  @override
  Future<void> markAllRead() async {
    await Future.delayed(_fakeDelay);
    for (var i = 0; i < _notifications.length; i++) {
      _notifications[i] = _notifications[i].copyWith(isRead: true);
    }
  }

  List<StoreNotification> _seedNotifications() {
    final now = _now;
    return [
      StoreNotification(
        id: 'ntf-001',
        kind: NotificationKind.whatsappOrder,
        title: 'Pedido nuevo de Laura Jiménez',
        body: '3 artículos · \$184.50 · pide entrega a domicilio',
        createdAt: now.subtract(const Duration(minutes: 12)),
        isRead: false,
        customerPhone: '+525518324477',
        orderFolio: 'PD-2026-000318',
      ),
      StoreNotification(
        id: 'ntf-002',
        kind: NotificationKind.lowStock,
        title: 'Se está agotando Coca-Cola 600 ml',
        body: 'Te quedan 4 piezas y la semana pasada vendiste 38.',
        createdAt: now.subtract(const Duration(hours: 2)),
        isRead: false,
        productId: 'prod-001',
      ),
      StoreNotification(
        id: 'ntf-003',
        kind: NotificationKind.payableDue,
        title: 'Le debes a Distribuidora Bimbo Norte',
        body: '\$3,240.00 que vencieron ayer.',
        createdAt: now.subtract(const Duration(hours: 5)),
        isRead: false,
      ),
      StoreNotification(
        id: 'ntf-004',
        kind: NotificationKind.salesMilestone,
        title: 'Tu mejor septiembre hasta ahora',
        body: 'Llevas \$48,320 este mes: 18% más que en septiembre pasado.',
        createdAt: now.subtract(const Duration(days: 1)),
        isRead: true,
      ),
      StoreNotification(
        id: 'ntf-005',
        kind: NotificationKind.lowStock,
        title: 'Se agotó Fabuloso 1 L',
        body: 'Lleva 2 días en cero. Es de lo que más te piden los lunes.',
        createdAt: now.subtract(const Duration(days: 2)),
        isRead: true,
        productId: 'prod-014',
      ),
    ];
  }
}
