import '../domain/daily_snapshot.dart';
import '../domain/stock_alert.dart';
import '../domain/store_notification.dart';

// ---------------------------------------------------------------------------
// Contrato
// ---------------------------------------------------------------------------

/// Datos del Centro de mando (N-08) y del apartado de Notificaciones.
///
/// **Mapa de integración con el backend** — cada dato de aquí tiene un dueño
/// futuro; hoy todos salen de [DashboardRepositoryMock]:
///
/// | Dato del snapshot        | Endpoint destino                              | Tarea |
/// |--------------------------|-----------------------------------------------|-------|
/// | Ventas de hoy y de ayer  | `GET /analytics/dashboard?period=today`       | 15.1.3 |
/// | Margen de hoy            | `GET /analytics/dashboard` (`profitability.gross_profit_mxn`) | 15.1.3 |
/// | Stock bajo / agotado (conteo y renglones) | `GET /inventory/products?low_stock=true` | 3.1 / 5.1 |
/// | Cuentas por pagar        | `GET /accounts-payable?overdue_only=true`     | 11.1 |
/// | Estado de caja           | `GET /cash/current-session`                   | 9.1 |
///
/// | Notificación             | Origen futuro                                  | Tarea |
/// |--------------------------|------------------------------------------------|-------|
/// | Stock por agotarse       | Regla sobre el stock + venta histórica          | 15.1 |
/// | Meta/comparativa de venta| `GET /analytics/sales-trends`                   | 15.1.3 |
/// | Pedido de la vitrina     | `GET /catalog/orders?status=pending`            | 13.1 |
/// | Cuenta por pagar próxima | `GET /accounts-payable` (vencimiento)           | 11.1 |
///
/// El buzón en sí (`GET /notifications`, `POST /notifications/{id}/read`)
/// **no existe todavía en ningún contrato** — queda propuesto para Alan. Si
/// no se construye, cada tarjeta se puede derivar en el cliente de los cuatro
/// endpoints de arriba; el modelo [StoreNotification] no cambia.
abstract class DashboardRepository {
  Future<DailySnapshot> getTodaySnapshot();

  Future<List<StoreNotification>> listNotifications();

  Future<void> markRead(String id);

  Future<void> markAllRead();
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
