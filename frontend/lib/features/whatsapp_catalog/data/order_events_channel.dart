import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../domain/store_order.dart';
import 'store_orders_repository.dart';

/// Fábrica del socket — inyectable para probar la reconexión sin red.
typedef WebSocketConnector = WebSocketChannel Function(Uri uri);

/// Lee el token de acceso vigente (el `AuthInterceptor` lo renueva por HTTP;
/// aquí sólo se vuelve a leer al reconectar).
typedef AccessTokenReader = Future<String?> Function();

/// Canal en vivo de pedidos web (`WS /api/v1/ws/orders?token=`).
///
/// Convierte el socket en un `Stream<OrderEvent>` con reconexión automática
/// (espera exponencial 1 s → 30 s). Tras cada reconexión emite
/// [OrderEventType.reconnected] para que el provider pida al servidor lo que
/// cambió mientras tanto (`GET /catalog-orders?since=`): el socket es la
/// notificación, nunca la fuente de verdad.
///
/// El token viaja en la query porque los navegadores no mandan headers en
/// WebSocket; se lee de nuevo en cada intento por si se renovó.
class OrderEventsChannel {
  OrderEventsChannel({
    required this.apiBaseUrl,
    required this.readToken,
    WebSocketConnector? connector,
    this.initialBackoff = const Duration(seconds: 1),
    this.maxBackoff = const Duration(seconds: 30),
  }) : connect = connector ?? WebSocketChannel.connect;

  final String apiBaseUrl;
  final AccessTokenReader readToken;
  final WebSocketConnector connect;
  final Duration initialBackoff;
  final Duration maxBackoff;

  /// `http://host:8000` → `ws://host:8000/api/v1/ws/orders?token=…`.
  Uri socketUri(String token) {
    final base = Uri.parse(apiBaseUrl);
    return base.replace(
      scheme: base.scheme == 'https' ? 'wss' : 'ws',
      path: '${base.path.replaceAll(RegExp(r'/$'), '')}/api/v1/ws/orders',
      queryParameters: {'token': token},
    );
  }

  /// Un stream por suscripción; cancelar la suscripción cierra el socket.
  Stream<OrderEvent> events() => _Connection(this).stream;

  Duration backoff(int attempt) {
    final factor = 1 << (attempt - 1).clamp(0, 10);
    final ms = initialBackoff.inMilliseconds * factor;
    return Duration(milliseconds: ms.clamp(0, maxBackoff.inMilliseconds));
  }

  /// `{"type": "order.new", "order": {...}}` → [OrderEvent]. Lo que no se
  /// entiende se ignora: un mensaje raro no debe tirar el canal.
  static OrderEvent? parse(dynamic raw) {
    try {
      final data = raw is String ? jsonDecode(raw) : raw;
      if (data is! Map) return null;
      final type = data['type']?.toString();
      switch (type) {
        case 'hello':
          return const OrderEvent(OrderEventType.hello);
        case 'ping':
          return const OrderEvent(OrderEventType.ping);
        case 'order.new':
        case 'order.updated':
          final order = data['order'];
          if (order is! Map) return null;
          return OrderEvent(
            type == 'order.new'
                ? OrderEventType.newOrder
                : OrderEventType.updated,
            order: StoreOrdersRepositoryImpl.storeOrderFromJson(
              Map<String, dynamic>.from(order),
            ),
          );
        default:
          return null;
      }
    } catch (_) {
      return null;
    }
  }
}

/// Una suscripción viva: abre, escucha, reintenta, cierra.
class _Connection {
  _Connection(this.channel) {
    _controller = StreamController<OrderEvent>(
      onListen: _open,
      onCancel: _close,
    );
  }

  final OrderEventsChannel channel;
  late final StreamController<OrderEvent> _controller;

  WebSocketChannel? _socket;
  StreamSubscription<dynamic>? _sub;
  Timer? _retry;
  bool _closed = false;
  int _attempts = 0;

  Stream<OrderEvent> get stream => _controller.stream;

  Future<void> _open() async {
    if (_closed) return;
    final token = await channel.readToken();
    if (_closed) return;
    if (token == null || token.isEmpty) {
      // Sin sesión no hay a quién avisar; se vuelve a intentar por si entra.
      _retry = Timer(channel.maxBackoff, _open);
      return;
    }
    try {
      _socket = channel.connect(channel.socketUri(token));
      await _socket!.ready;
    } catch (_) {
      _scheduleRetry();
      return;
    }
    if (_closed) {
      await _socket?.sink.close();
      return;
    }
    if (_attempts > 0) _controller.add(const OrderEvent.reconnected());
    _attempts = 0;
    _sub = _socket!.stream.listen(
      (raw) {
        final event = OrderEventsChannel.parse(raw);
        if (event != null) _controller.add(event);
      },
      onError: (_) => _scheduleRetry(),
      onDone: _scheduleRetry,
      cancelOnError: true,
    );
  }

  void _scheduleRetry() {
    if (_closed) return;
    _attempts += 1;
    _retry?.cancel();
    _retry = Timer(channel.backoff(_attempts), () async {
      await _sub?.cancel();
      _sub = null;
      _socket = null;
      await _open();
    });
  }

  Future<void> _close() async {
    _closed = true;
    _retry?.cancel();
    await _sub?.cancel();
    await _socket?.sink.close();
  }
}
