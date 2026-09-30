import 'package:dio/dio.dart';

import '../../../core/network/dio_client.dart';
import '../domain/subscription.dart';

/// Suscripción del comercio contra el backend real (modelo prepago, P9–P13).
///
/// Sólo lectura desde la app: el cobro será con Google Play (P13) y, hasta
/// integrarlo, la app no ofrece ninguna forma de pago. Lo que cambia la
/// suscripción (pagos manuales, cortesías, bloqueos) lo hace soporte desde el
/// panel de plataforma, y el Dueño lo ve en [getSupportActivity] (P8).
abstract class SaasRepository {
  /// GET /api/v1/subscription
  Future<Subscription> getSubscription();

  /// GET /api/v1/subscription/activity — sólo el Dueño (403 para empleados).
  Future<List<SupportActivity>> getSupportActivity();
}

class SaasException implements Exception {
  const SaasException(this.message);
  final String message;

  @override
  String toString() => message;
}

// ---------------------------------------------------------------------------
// Implementación real
// ---------------------------------------------------------------------------

class SaasRepositoryImpl implements SaasRepository {
  SaasRepositoryImpl({required this.client});

  final DioClient client;

  @override
  Future<Subscription> getSubscription() async {
    try {
      final res = await client.get('/api/v1/subscription');
      return Subscription.fromJson(res.data as Map);
    } on DioException catch (e) {
      throw _map(e, 'No pudimos cargar tu suscripción.');
    }
  }

  @override
  Future<List<SupportActivity>> getSupportActivity() async {
    try {
      final res = await client.get('/api/v1/subscription/activity');
      return (res.data as List? ?? const [])
          .whereType<Map>()
          .map(SupportActivity.fromJson)
          .toList();
    } on DioException catch (e) {
      throw _map(e, 'No pudimos cargar la actividad de soporte.');
    }
  }

  static SaasException _map(DioException e, String fallback) {
    if (e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout) {
      return const SaasException('Sin conexión con el servidor. Revisa tu red.');
    }
    return SaasException(fallback);
  }
}

// ---------------------------------------------------------------------------
// Mock — tests y demos (`--dart-define=SAAS_MOCK=true`)
// ---------------------------------------------------------------------------

/// Suscripción simulada. Por omisión: plan Comercio vigente 20 días más.
/// [daysUntilDue] negativo simula una suscripción vencida: dentro de los 10
/// días de gracia conserva acceso completo; después queda suspendida.
class SaasRepositoryMock implements SaasRepository {
  SaasRepositoryMock({
    this.currentEmail = 'demo@nexus.mx',
    this.latency = const Duration(milliseconds: 350),
    this.daysUntilDue = 20,
    this.plan = SaasPlanId.comercio,
    this.renewalChannel = RenewalChannel.none,
    this.manualStatus,
    this.abuseReason,
    List<SupportActivity>? activity,
    DateTime Function()? now,
  })  : now = now ?? DateTime.now,
        _activity = activity;

  final String currentEmail;
  final Duration latency;
  /// Mutable en tests: simula que soporte o un pago extendió la vigencia.
  int daysUntilDue;
  final SaasPlanId plan;
  final RenewalChannel renewalChannel;

  /// Fuerza un estado (p. ej. sólo lectura aplicado a mano desde el panel).
  final SubscriptionStatus? manualStatus;

  /// Suspendida por soporte (P17) con este motivo: HARD_LOCK con `ABUSE`.
  final String? abuseReason;
  final DateTime Function() now;
  final List<SupportActivity>? _activity;

  static const graceDays = 10;
  static const fees = {
    SaasPlanId.emprendedor: 199.0,
    SaasPlanId.comercio: 399.0,
    SaasPlanId.corporativo: 699.0,
  };
  static const limits = {
    SaasPlanId.emprendedor: 2,
    SaasPlanId.comercio: 5,
    SaasPlanId.corporativo: 15,
  };

  Future<T> _delay<T>(T value) => latency == Duration.zero
      ? Future.value(value)
      : Future.delayed(latency, () => value);

  @override
  Future<Subscription> getSubscription() {
    final today = now();
    final paidUntil = DateTime(today.year, today.month, today.day)
        .add(Duration(days: daysUntilDue, hours: 12));
    final graceUntil = paidUntil.add(const Duration(days: graceDays));
    final entitlement = today.isBefore(paidUntil)
        ? Entitlement.vigente
        : today.isBefore(graceUntil)
            ? Entitlement.gracia
            : Entitlement.vencida;
    final status = abuseReason != null
        ? SubscriptionStatus.hardLock
        : manualStatus ??
            (entitlement == Entitlement.vencida
                ? SubscriptionStatus.hardLock
                : SubscriptionStatus.active);
    return _delay(Subscription(
      tenantId: 't-sol',
      tenantName: 'Abarrotes Sol',
      plan: plan,
      status: status,
      monthlyFeeMxn: fees[plan]!,
      paidUntil: paidUntil,
      graceUntil: graceUntil,
      entitlement: entitlement,
      renewalChannel: renewalChannel,
      usersCount: 2,
      usersLimit: limits[plan]!,
      lockReason: abuseReason != null ? 'ABUSE' : (status.isLocked ? 'NONPAYMENT' : null),
      suspensionReason: abuseReason,
    ));
  }

  @override
  Future<List<SupportActivity>> getSupportActivity() {
    final today = now();
    return _delay(_activity ??
        [
          SupportActivity(
            occurredAt: today.subtract(const Duration(days: 12)),
            action: 'COURTESY_GRANTED',
            summary: 'Te dimos un mes sin costo.',
            reason: 'Compensación por la caída del servicio del 16 de septiembre.',
            by: 'Soporte Nexus · Eduardo',
          ),
        ]);
  }
}
