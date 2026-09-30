import 'package:dio/dio.dart';

import '../../../core/network/dio_client.dart';

/// Acceso de soporte que concede el dueño (P2/P18, backend en la etapa 1:
/// `GET/POST/DELETE /api/v1/support-access`). Hasta la etapa 4 (suplantación
/// de sólo lectura) conceder no tiene efecto: la pantalla existe pero no se
/// ofrece en el menú (P26, [kSupportAccessVisible]).
class AccessGrant {
  const AccessGrant({required this.id, required this.createdAt, required this.expiresAt, this.revokedAt, this.active = false});

  final String id;
  final DateTime createdAt;
  final DateTime expiresAt;
  final DateTime? revokedAt;
  final bool active;

  factory AccessGrant.fromJson(Map<dynamic, dynamic> json) => AccessGrant(
        id: (json['id'] ?? '').toString(),
        createdAt: DateTime.tryParse('${json['created_at']}')?.toLocal() ?? DateTime.now(),
        expiresAt: DateTime.tryParse('${json['expires_at']}')?.toLocal() ?? DateTime.now(),
        revokedAt: DateTime.tryParse('${json['revoked_at']}')?.toLocal(),
        active: json['active'] == true,
      );
}

class SupportAccessStatus {
  const SupportAccessStatus({this.active, this.history = const []});

  final AccessGrant? active;
  final List<AccessGrant> history;

  factory SupportAccessStatus.fromJson(Map<dynamic, dynamic> json) => SupportAccessStatus(
        active: json['active'] is Map ? AccessGrant.fromJson(json['active'] as Map) : null,
        history: (json['history'] as List? ?? const []).whereType<Map>().map(AccessGrant.fromJson).toList(),
      );
}

class SupportAccessException implements Exception {
  const SupportAccessException(this.message);
  final String message;

  @override
  String toString() => message;
}

abstract class SupportAccessRepository {
  Future<SupportAccessStatus> status();

  /// 1, 24 o 72 horas; reemplaza a una concesión vigente.
  Future<SupportAccessStatus> grant(int hours);
  Future<SupportAccessStatus> revoke();
}

class SupportAccessRepositoryImpl implements SupportAccessRepository {
  SupportAccessRepositoryImpl({required this.client});
  final DioClient client;

  static const _path = '/api/v1/support-access';

  @override
  Future<SupportAccessStatus> status() => _run(() => client.get(_path));

  @override
  Future<SupportAccessStatus> grant(int hours) => _run(() => client.post(_path, data: {'hours': hours}));

  @override
  Future<SupportAccessStatus> revoke() => _run(() => client.delete(_path));

  Future<SupportAccessStatus> _run(Future<Response<dynamic>> Function() call) async {
    try {
      final res = await call();
      return SupportAccessStatus.fromJson(res.data as Map);
    } on DioException catch (e) {
      if (e.type == DioExceptionType.connectionError || e.type == DioExceptionType.connectionTimeout) {
        throw const SupportAccessException('Sin conexión con el servidor. Revisa tu red.');
      }
      throw const SupportAccessException('No pudimos actualizar el acceso de soporte. Intenta de nuevo.');
    }
  }
}

class SupportAccessRepositoryMock implements SupportAccessRepository {
  SupportAccessRepositoryMock({this.latency = const Duration(milliseconds: 200), DateTime Function()? now})
      : _now = now ?? DateTime.now;

  final Duration latency;
  final DateTime Function() _now;
  final List<AccessGrant> _grants = [];

  SupportAccessStatus _status() {
    final now = _now();
    final history = _grants.reversed
        .map((g) => AccessGrant(
              id: g.id,
              createdAt: g.createdAt,
              expiresAt: g.expiresAt,
              revokedAt: g.revokedAt,
              active: g.revokedAt == null && now.isBefore(g.expiresAt),
            ))
        .toList();
    return SupportAccessStatus(active: history.where((g) => g.active).firstOrNull, history: history);
  }

  @override
  Future<SupportAccessStatus> status() async {
    await Future.delayed(latency);
    return _status();
  }

  @override
  Future<SupportAccessStatus> grant(int hours) async {
    await Future.delayed(latency);
    _revokeActive();
    final now = _now();
    _grants.add(AccessGrant(id: 'g${_grants.length + 1}', createdAt: now, expiresAt: now.add(Duration(hours: hours))));
    return _status();
  }

  @override
  Future<SupportAccessStatus> revoke() async {
    await Future.delayed(latency);
    _revokeActive();
    return _status();
  }

  void _revokeActive() {
    final now = _now();
    for (var i = 0; i < _grants.length; i++) {
      final g = _grants[i];
      if (g.revokedAt == null && now.isBefore(g.expiresAt)) {
        _grants[i] = AccessGrant(id: g.id, createdAt: g.createdAt, expiresAt: g.expiresAt, revokedAt: now);
      }
    }
  }
}
