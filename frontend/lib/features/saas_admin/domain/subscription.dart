import 'package:equatable/equatable.dart';

/// Suscripción del comercio — modelo prepago (P9–P13, Sep 2026).
///
/// Contra el backend real (`GET /api/v1/subscription` y
/// `/api/v1/subscription/activity`). Se paga una suscripción, vale un mes;
/// al vencer hay 10 días de gracia **con acceso completo** (P10) y después se
/// suspende. Cobrar desde la app será con Google Play (P13): hasta integrarlo
/// la app **no ofrece ninguna forma de pago** (política de Google Play) y
/// `renewalChannel` llega como [RenewalChannel.none].

// ---------------------------------------------------------------------------
// Estado del comercio — Constitución Art. VI §6.3
// ---------------------------------------------------------------------------

enum SubscriptionStatus {
  active,
  softLock, // sólo lectura (hoy sólo por decisión manual del panel)
  hardLock; // suspendida: sólo ve su suscripción

  static SubscriptionStatus fromApi(String? raw) {
    switch (raw?.toUpperCase()) {
      case 'SOFT_LOCK':
        return SubscriptionStatus.softLock;
      case 'HARD_LOCK':
        return SubscriptionStatus.hardLock;
      default:
        return SubscriptionStatus.active;
    }
  }

  String get apiValue => switch (this) {
        SubscriptionStatus.active => 'ACTIVE',
        SubscriptionStatus.softLock => 'SOFT_LOCK',
        SubscriptionStatus.hardLock => 'HARD_LOCK',
      };

  String get label => switch (this) {
        SubscriptionStatus.active => 'Activa',
        SubscriptionStatus.softLock => 'Solo lectura',
        SubscriptionStatus.hardLock => 'Suspendida',
      };

  bool get isLocked => this != SubscriptionStatus.active;
}

/// Dónde está su vigencia respecto al día de hoy.
enum Entitlement {
  vigente, // antes de `paidUntil`
  gracia, // venció, pero conserva acceso completo hasta `graceUntil` (P10)
  vencida, // terminó la gracia
  sinFecha; // comercio anterior al modelo

  static Entitlement fromApi(String? raw) => switch (raw?.toUpperCase()) {
        'VIGENTE' => Entitlement.vigente,
        'GRACIA' => Entitlement.gracia,
        'VENCIDA' => Entitlement.vencida,
        _ => Entitlement.sinFecha,
      };
}

/// Cómo renueva desde la app. `none` hasta integrar Google Play (P13): se
/// cambia en el servidor (`SUBSCRIPTION_RENEWAL_CHANNEL`) sin publicar otra
/// versión de la pantalla.
enum RenewalChannel {
  none,
  googlePlay;

  static RenewalChannel fromApi(String? raw) =>
      raw?.toUpperCase() == 'GOOGLE_PLAY'
          ? RenewalChannel.googlePlay
          : RenewalChannel.none;
}

/// Planes — Constitución Art. VI §6.1.
enum SaasPlanId {
  emprendedor('Emprendedor'),
  comercio('Comercio'),
  corporativo('Corporativo');

  const SaasPlanId(this.label);
  final String label;

  static SaasPlanId fromApi(String? raw) => switch (raw?.toUpperCase()) {
        'COMERCIO' => SaasPlanId.comercio,
        'CORPORATIVO' => SaasPlanId.corporativo,
        _ => SaasPlanId.emprendedor,
      };
}

// ---------------------------------------------------------------------------
// Suscripción (GET /api/v1/subscription)
// ---------------------------------------------------------------------------

class Subscription extends Equatable {
  const Subscription({
    required this.tenantId,
    required this.tenantName,
    required this.plan,
    required this.status,
    required this.monthlyFeeMxn,
    this.paidUntil,
    this.graceUntil,
    this.entitlement = Entitlement.sinFecha,
    this.renewalChannel = RenewalChannel.none,
    this.usersCount = 0,
    this.usersLimit = 0,
    this.lockReason,
    this.suspensionReason,
  });

  final String tenantId;
  final String tenantName;
  final SaasPlanId plan;
  final SubscriptionStatus status;
  final double monthlyFeeMxn;

  /// Hasta cuándo está pagada; al día siguiente empieza la gracia.
  final DateTime? paidUntil;

  /// Último momento con acceso completo si no renueva.
  final DateTime? graceUntil;
  final Entitlement entitlement;
  final RenewalChannel renewalChannel;
  final int usersCount;
  final int usersLimit;

  /// Si está bloqueada, por qué: `NONPAYMENT` o `ABUSE` (Centro de soporte, P17).
  final String? lockReason;

  /// El motivo que escribió soporte al suspender por abuso (sólo lo recibe el dueño).
  final String? suspensionReason;

  /// Suspensión de soporte: renovar no la levanta, se aclara con soporte.
  bool get isAbuseSuspension => status.isLocked && lockReason == 'ABUSE';

  /// Hay canal para renovar **y** renovar serviría (no si la suspendió soporte).
  bool get canRenewInApp => renewalChannel != RenewalChannel.none && !isAbuseSuspension;

  factory Subscription.fromJson(Map<dynamic, dynamic> json) {
    final usage = (json['usage_stats'] as Map?) ?? const {};
    return Subscription(
      tenantId: (json['id'] ?? '').toString(),
      tenantName: (json['tenant_name'] ?? '').toString(),
      plan: SaasPlanId.fromApi(json['plan']?.toString()),
      status: SubscriptionStatus.fromApi(json['status']?.toString()),
      monthlyFeeMxn: _toDouble(json['monthly_fee_mxn']),
      paidUntil: _toDate(json['paid_until']),
      graceUntil: _toDate(json['grace_until']),
      entitlement: Entitlement.fromApi(json['entitlement']?.toString()),
      renewalChannel: RenewalChannel.fromApi(json['renewal_channel']?.toString()),
      usersCount: (usage['users_count'] as num?)?.toInt() ?? 0,
      usersLimit: (usage['users_limit'] as num?)?.toInt() ?? 0,
      lockReason: json['lock_reason']?.toString(),
      suspensionReason: json['suspension_reason']?.toString(),
    );
  }

  /// Días que faltan para el vencimiento (negativo = ya venció).
  int? daysUntilDue(DateTime now) =>
      paidUntil == null ? null : _dayDiff(now, paidUntil!);

  /// Días de gracia que le quedan (sólo tiene sentido en [Entitlement.gracia]).
  int? daysOfGraceLeft(DateTime now) =>
      graceUntil == null ? null : _dayDiff(now, graceUntil!);

  @override
  List<Object?> get props => [
        tenantId,
        plan,
        status,
        monthlyFeeMxn,
        paidUntil,
        graceUntil,
        entitlement,
        renewalChannel,
        usersCount,
        usersLimit,
        lockReason,
        suspensionReason,
      ];
}

// ---------------------------------------------------------------------------
// Actividad de soporte (GET /api/v1/subscription/activity) — P8
// ---------------------------------------------------------------------------

/// Lo que soporte Nexus (o el ciclo automático) cambió en su suscripción, con
/// el motivo tal cual se escribió: transparencia hacia el Dueño.
class SupportActivity extends Equatable {
  const SupportActivity({
    required this.occurredAt,
    required this.action,
    required this.summary,
    required this.by,
    this.reason,
  });

  final DateTime occurredAt;
  final String action;
  final String summary;
  final String by;
  final String? reason;

  factory SupportActivity.fromJson(Map<dynamic, dynamic> json) =>
      SupportActivity(
        occurredAt: _toDate(json['occurred_at']) ?? DateTime.now(),
        action: (json['action'] ?? '').toString(),
        summary: (json['summary'] ?? '').toString(),
        by: (json['by'] ?? 'Soporte Nexus').toString(),
        reason: json['reason']?.toString(),
      );

  @override
  List<Object?> get props => [occurredAt, action, summary, by, reason];
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

double _toDouble(dynamic value) {
  if (value == null) return 0;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString()) ?? 0;
}

DateTime? _toDate(dynamic value) =>
    value == null ? null : DateTime.tryParse(value.toString())?.toLocal();

int _dayDiff(DateTime from, DateTime to) =>
    DateTime(to.year, to.month, to.day)
        .difference(DateTime(from.year, from.month, from.day))
        .inDays;

/// Suma meses calendario conservando el día (recortado al último del mes).
/// Espejo de `add_one_month` del backend.
DateTime addMonths(DateTime d, int months) {
  final monthIndex = d.month - 1 + months;
  final year = d.year + (monthIndex / 12).floor();
  final month = monthIndex % 12 + 1;
  final lastDay = DateTime(year, month + 1, 0).day;
  return DateTime(year, month, d.day > lastDay ? lastDay : d.day, d.hour,
      d.minute, d.second);
}

/// "$399.00" — formato MXN de dos decimales con separador de miles.
String mxn(double value) {
  // Negativos como "−$279.50" (signo antes del símbolo), no "$-279.50":
  // aparecen en "Tu dinero hoy" cuando se debe más de lo que se tiene.
  final negative = value < 0;
  final fixed = value.abs().toStringAsFixed(2);
  final parts = fixed.split('.');
  final intPart = parts[0].replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+$)'),
    (m) => '${m[1]},',
  );
  return '${negative ? '−' : ''}\$$intPart.${parts[1]}';
}

const _months = [
  'ene',
  'feb',
  'mar',
  'abr',
  'may',
  'jun',
  'jul',
  'ago',
  'sep',
  'oct',
  'nov',
  'dic',
];

/// "30 sep" — fecha corta en español, sin dependencia de `intl`.
String shortDate(DateTime d) => '${d.day} ${_months[d.month - 1]}';

/// "30 sep 2026".
String longDate(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';

/// "Sep 2026" — etiqueta de un periodo.
String periodLabel(DateTime d) {
  final m = _months[d.month - 1];
  return '${m[0].toUpperCase()}${m.substring(1)} ${d.year}';
}
