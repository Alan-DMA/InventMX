import 'package:dio/dio.dart';

import '../../../core/network/dio_client.dart';

/// Acceso de soporte que concede el dueño (P2/P18, backend en la etapa 1:
/// `GET/POST/DELETE /api/v1/support-access`). Desde la etapa 4 la respuesta
/// trae además quién de soporte entró a ver la tienda con ese permiso (P38).
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

/// Una entrada de soporte a la tienda (etapa 4, P38): quién, cuándo, cuánto,
/// por qué y qué revisó. `active` = está viendo la tienda ahora.
class SupportVisit {
  const SupportVisit({
    required this.id,
    required this.by,
    required this.reason,
    this.active = false,
    this.openedAt,
    this.endedAt,
    this.minutes,
    this.sections = const [],
    this.endText,
  });

  final String id;
  final String by;
  final String reason;
  final bool active;
  final DateTime? openedAt;
  final DateTime? endedAt;
  final int? minutes;
  final List<String> sections;
  final String? endText;

  factory SupportVisit.fromJson(Map<dynamic, dynamic> json) => SupportVisit(
        id: (json['id'] ?? '').toString(),
        by: (json['by'] ?? 'Soporte Nexus').toString(),
        reason: (json['reason'] ?? '').toString(),
        active: json['active'] == true,
        openedAt: DateTime.tryParse('${json['opened_at']}')?.toLocal(),
        endedAt: DateTime.tryParse('${json['ended_at']}')?.toLocal(),
        minutes: (json['minutes'] as num?)?.toInt(),
        sections: (json['sections'] as List? ?? const []).map((e) => '$e').toList(),
        endText: json['end_text']?.toString(),
      );
}

class SupportAccessStatus {
  const SupportAccessStatus({this.active, this.history = const [], this.visits = const []});

  final AccessGrant? active;
  final List<AccessGrant> history;

  /// Las entradas de soporte, la más reciente primero.
  final List<SupportVisit> visits;

  /// Quien está viendo la tienda ahora mismo (puede haber más de uno).
  List<SupportVisit> get visitsNow => visits.where((v) => v.active).toList();

  factory SupportAccessStatus.fromJson(Map<dynamic, dynamic> json) => SupportAccessStatus(
        active: json['active'] is Map ? AccessGrant.fromJson(json['active'] as Map) : null,
        history: (json['history'] as List? ?? const []).whereType<Map>().map(AccessGrant.fromJson).toList(),
        visits: (json['sessions'] as List? ?? const []).whereType<Map>().map(SupportVisit.fromJson).toList(),
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

  /// Entradas de soporte simuladas (la más reciente primero). Retirar el
  /// permiso termina las que estén abiertas, como el servidor.
  final List<SupportVisit> visits = [];

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
    return SupportAccessStatus(
      active: history.where((g) => g.active).firstOrNull,
      history: history,
      visits: List.of(visits),
    );
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
    final now = _now();
    for (var i = 0; i < visits.length; i++) {
      final v = visits[i];
      if (v.active) {
        visits[i] = SupportVisit(
          id: v.id, by: v.by, reason: v.reason, openedAt: v.openedAt, endedAt: now,
          minutes: v.minutes, sections: v.sections, endText: 'Terminó tu permiso',
        );
      }
    }
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
