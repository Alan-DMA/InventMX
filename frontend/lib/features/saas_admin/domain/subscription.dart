import 'package:equatable/equatable.dart';

/// Dominio de la suscripción SaaS — Tarea 14.2.
///
/// Modelado contra el backend real (`/api/v1/saas`, tablas legacy `plans`,
/// `subscription_invoices`, `subscription_payment_validations`), no contra
/// `docs/api/saas.yaml`. Los estados llegan en español; los parsers son
/// tolerantes con la variante en inglés del yaml por si Alan la adopta.

// ---------------------------------------------------------------------------
// Estado del comercio — Constitución Art. VI §6.3
// ---------------------------------------------------------------------------

enum SubscriptionStatus {
  active,
  softLock, // días 1-10 de morosidad: solo lectura
  hardLock; // día 11+: bloqueo total

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
        SubscriptionStatus.hardLock => 'Bloqueada',
      };

  bool get isLocked => this != SubscriptionStatus.active;
}

// ---------------------------------------------------------------------------
// Planes — Constitución Art. VI §6.1 ($199 / $399 / $699 MXN)
// ---------------------------------------------------------------------------

class SaasPlan extends Equatable {
  const SaasPlan({
    required this.id,
    required this.name,
    required this.priceMxn,
    required this.maxUsers,
    required this.maxWarehouses,
  });

  final String id;
  final String name;
  final double priceMxn;
  final int maxUsers;
  final int maxWarehouses;

  factory SaasPlan.fromJson(Map<dynamic, dynamic> json) => SaasPlan(
        id: json['id'].toString(),
        name: (json['name'] ?? '').toString(),
        priceMxn: _toDouble(json['price'] ?? json['price_mxn']),
        maxUsers: (json['max_users'] as num?)?.toInt() ?? 0,
        maxWarehouses: (json['max_warehouses'] as num?)?.toInt() ?? 0,
      );

  /// Línea de beneficios por plan (Constitución §6.1). Se resuelve por nombre
  /// porque el backend solo guarda nombre, precio y límites.
  String get highlights {
    switch (name.toLowerCase()) {
      case 'emprendedor':
        return 'Inventario, ventas y compras · 1 almacén';
      case 'comercio':
        return 'Todo Emprendedor + caja, catálogo WhatsApp, multi-almacén';
      case 'corporativo':
        return 'Todos los módulos + analítica avanzada y multi-sucursal';
      default:
        return '';
    }
  }

  @override
  List<Object?> get props => [id, name, priceMxn, maxUsers, maxWarehouses];
}

// ---------------------------------------------------------------------------
// Facturas de suscripción
// ---------------------------------------------------------------------------

enum InvoiceStatus {
  pendiente,
  pagada,
  cancelada;

  static InvoiceStatus fromApi(String? raw) {
    switch (raw?.toUpperCase()) {
      case 'PAGADA':
      case 'PAID':
        return InvoiceStatus.pagada;
      case 'CANCELADA':
      case 'CANCELLED':
      case 'EXPIRED':
        return InvoiceStatus.cancelada;
      default:
        return InvoiceStatus.pendiente;
    }
  }

  String get label => switch (this) {
        InvoiceStatus.pendiente => 'Pendiente',
        InvoiceStatus.pagada => 'Pagada',
        InvoiceStatus.cancelada => 'Cancelada',
      };
}

class SubscriptionInvoice extends Equatable {
  const SubscriptionInvoice({
    required this.id,
    required this.planId,
    required this.planName,
    required this.amountMxn,
    required this.dueDate,
    required this.status,
    this.createdAt,
  });

  final String id;
  final String planId;
  final String? planName;
  final double amountMxn;
  final DateTime dueDate;
  final InvoiceStatus status;
  final DateTime? createdAt;

  factory SubscriptionInvoice.fromJson(Map<dynamic, dynamic> json) =>
      SubscriptionInvoice(
        id: json['id'].toString(),
        planId: (json['plan_id'] ?? '').toString(),
        planName: json['plan_name']?.toString(),
        amountMxn: _toDouble(json['amount'] ?? json['amount_mxn']),
        dueDate: DateTime.parse(json['due_date'].toString()),
        status: InvoiceStatus.fromApi(json['status']?.toString()),
        createdAt: json['created_at'] == null
            ? null
            : DateTime.tryParse(json['created_at'].toString()),
      );

  /// El periodo que cubre la factura: el mes que termina en `dueDate`.
  DateTime get periodStart => addMonths(dueDate, -1);

  @override
  List<Object?> get props => [id, planId, amountMxn, dueDate, status];
}

// ---------------------------------------------------------------------------
// Aviso de pago manual ("Ya pagué") — Constitución Art. V §5.2
// ---------------------------------------------------------------------------

enum SaasPaymentMethod {
  spei,
  oxxo,
  efectivo;

  static SaasPaymentMethod fromApi(String? raw) {
    switch (raw?.toUpperCase()) {
      case 'OXXO':
      case 'OXXO_PAY':
        return SaasPaymentMethod.oxxo;
      case 'EFECTIVO':
      case 'CASH_MANUAL':
        return SaasPaymentMethod.efectivo;
      default:
        return SaasPaymentMethod.spei;
    }
  }

  String get apiValue => name.toUpperCase();

  String get label => switch (this) {
        SaasPaymentMethod.spei => 'Transferencia SPEI',
        SaasPaymentMethod.oxxo => 'Pago en OXXO',
        SaasPaymentMethod.efectivo => 'Efectivo',
      };
}

enum ValidationStatus {
  pendiente,
  aprobada,
  rechazada;

  static ValidationStatus fromApi(String? raw) {
    switch (raw?.toUpperCase()) {
      case 'APROBADA':
      case 'APPROVED':
        return ValidationStatus.aprobada;
      case 'RECHAZADA':
      case 'REJECTED':
        return ValidationStatus.rechazada;
      default:
        return ValidationStatus.pendiente;
    }
  }

  String get label => switch (this) {
        ValidationStatus.pendiente => 'En revisión',
        ValidationStatus.aprobada => 'Aprobado',
        ValidationStatus.rechazada => 'Rechazado',
      };
}

class PaymentValidation extends Equatable {
  const PaymentValidation({
    required this.id,
    required this.invoiceId,
    required this.method,
    required this.reference,
    required this.status,
    this.receiptUrl,
    this.notes,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String invoiceId;
  final SaasPaymentMethod method;
  final String reference;
  final ValidationStatus status;
  final String? receiptUrl;

  /// Notas del fundador: en un rechazo son el motivo que lee el comercio.
  final String? notes;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory PaymentValidation.fromJson(Map<dynamic, dynamic> json) =>
      PaymentValidation(
        id: json['id'].toString(),
        invoiceId: (json['subscription_invoice_id'] ?? json['invoice_id'] ?? '')
            .toString(),
        method: SaasPaymentMethod.fromApi(json['payment_method']?.toString()),
        reference: (json['reference_number'] ?? '').toString(),
        status: ValidationStatus.fromApi(json['status']?.toString()),
        receiptUrl: json['receipt_file_url']?.toString(),
        notes: json['validation_notes']?.toString(),
        createdAt: json['created_at'] == null
            ? null
            : DateTime.tryParse(json['created_at'].toString()),
        updatedAt: json['updated_at'] == null
            ? null
            : DateTime.tryParse(json['updated_at'].toString()),
      );

  @override
  List<Object?> get props => [id, invoiceId, method, reference, status, notes];
}

// ---------------------------------------------------------------------------
// Instrucciones de pago
// ---------------------------------------------------------------------------

/// SPEI: CLABE fija de Nexus + concepto = código del comercio.
class SpeiInstructions extends Equatable {
  const SpeiInstructions({
    required this.clabe,
    required this.bank,
    required this.holder,
    required this.concept,
    required this.amountMxn,
  });

  final String clabe;
  final String bank;
  final String holder;
  final String concept;
  final double amountMxn;

  factory SpeiInstructions.fromJson(Map<dynamic, dynamic> json) =>
      SpeiInstructions(
        clabe: (json['clabe'] ?? '').toString(),
        bank: (json['bank'] ?? json['bank_name'] ?? '').toString(),
        holder: (json['holder'] ?? '').toString(),
        concept: (json['concept'] ?? '').toString(),
        amountMxn: _toDouble(json['amount'] ?? json['amount_mxn']),
      );

  /// "6461 8015 7000 0000 04" — más fácil de cotejar contra la banca móvil.
  String get clabeGrouped {
    final digits = clabe.replaceAll(RegExp(r'\s'), '');
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && i % 4 == 0) buffer.write(' ');
      buffer.write(digits[i]);
    }
    return buffer.toString();
  }

  @override
  List<Object?> get props => [clabe, bank, holder, concept, amountMxn];
}

/// OXXO: solo existe cuando el backend la entrega (sin proveedor en el MVP).
class OxxoInstructions extends Equatable {
  const OxxoInstructions({
    required this.reference,
    required this.barcode,
    required this.expiresAt,
  });

  final String reference;
  final String barcode;
  final DateTime expiresAt;

  factory OxxoInstructions.fromJson(Map<dynamic, dynamic> json) =>
      OxxoInstructions(
        reference: (json['reference_number'] ?? '').toString(),
        barcode: (json['barcode'] ?? '').toString(),
        expiresAt: DateTime.parse(json['expires_at'].toString()),
      );

  /// "9876 5432 1098 76" — como lo imprime la ficha de OXXO.
  String get referenceGrouped {
    final digits = reference.replaceAll(RegExp(r'\s'), '');
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && i % 4 == 0) buffer.write(' ');
      buffer.write(digits[i]);
    }
    return buffer.toString();
  }

  @override
  List<Object?> get props => [reference, barcode, expiresAt];
}

// ---------------------------------------------------------------------------
// Suscripción del comercio (GET /api/v1/saas/subscription)
// ---------------------------------------------------------------------------

class Subscription extends Equatable {
  const Subscription({
    required this.tenantId,
    required this.tenantCode,
    required this.tenantName,
    required this.status,
    this.plan,
    this.pendingInvoice,
    this.pendingValidation,
    this.daysOverdue = 0,
    this.softLockAt,
    this.hardLockAt,
    this.spei,
    this.oxxo,
  });

  final String tenantId;
  final String tenantCode;
  final String tenantName;
  final SubscriptionStatus status;
  final SaasPlan? plan;
  final SubscriptionInvoice? pendingInvoice;

  /// Aviso de pago en revisión para la factura pendiente, si lo hay.
  final PaymentValidation? pendingValidation;
  final int daysOverdue;

  /// Fechas exactas de las transiciones — el tendero las ve venir.
  final DateTime? softLockAt;
  final DateTime? hardLockAt;
  final SpeiInstructions? spei;
  final OxxoInstructions? oxxo;

  factory Subscription.fromJson(Map<dynamic, dynamic> json) {
    final tenant = (json['tenant'] as Map?) ?? const {};
    return Subscription(
      tenantId: (tenant['id'] ?? '').toString(),
      tenantCode: (tenant['code'] ?? '').toString(),
      tenantName: (tenant['name'] ?? '').toString(),
      status: SubscriptionStatus.fromApi(
        (json['status'] ?? tenant['subscription_status'])?.toString(),
      ),
      plan: json['plan'] is Map ? SaasPlan.fromJson(json['plan'] as Map) : null,
      pendingInvoice: json['pending_invoice'] is Map
          ? SubscriptionInvoice.fromJson(json['pending_invoice'] as Map)
          : null,
      pendingValidation: json['pending_validation'] is Map
          ? PaymentValidation.fromJson(json['pending_validation'] as Map)
          : null,
      daysOverdue: (json['days_overdue'] as num?)?.toInt() ?? 0,
      softLockAt: json['soft_lock_at'] == null
          ? null
          : DateTime.tryParse(json['soft_lock_at'].toString()),
      hardLockAt: json['hard_lock_at'] == null
          ? null
          : DateTime.tryParse(json['hard_lock_at'].toString()),
      spei: json['payment_instructions'] is Map
          ? SpeiInstructions.fromJson(json['payment_instructions'] as Map)
          : null,
      oxxo: json['oxxo'] is Map
          ? OxxoInstructions.fromJson(json['oxxo'] as Map)
          : null,
    );
  }

  bool get hasPaymentInReview =>
      pendingValidation?.status == ValidationStatus.pendiente;

  /// Días que faltan para el vencimiento (negativo = ya venció).
  int? daysUntilDue(DateTime now) {
    final due = pendingInvoice?.dueDate;
    if (due == null) return null;
    return DateTime(due.year, due.month, due.day)
        .difference(DateTime(now.year, now.month, now.day))
        .inDays;
  }

  Subscription copyWith({
    SubscriptionStatus? status,
    SaasPlan? plan,
    SubscriptionInvoice? pendingInvoice,
    PaymentValidation? pendingValidation,
    bool clearValidation = false,
    int? daysOverdue,
  }) =>
      Subscription(
        tenantId: tenantId,
        tenantCode: tenantCode,
        tenantName: tenantName,
        status: status ?? this.status,
        plan: plan ?? this.plan,
        pendingInvoice: pendingInvoice ?? this.pendingInvoice,
        pendingValidation: clearValidation
            ? null
            : (pendingValidation ?? this.pendingValidation),
        daysOverdue: daysOverdue ?? this.daysOverdue,
        softLockAt: softLockAt,
        hardLockAt: hardLockAt,
        spei: spei,
        oxxo: oxxo,
      );

  @override
  List<Object?> get props => [
        tenantId,
        status,
        plan,
        pendingInvoice,
        pendingValidation,
        daysOverdue,
        spei,
        oxxo,
      ];
}

// ---------------------------------------------------------------------------
// Perfil de sesión (GET /api/v1/saas/me)
// ---------------------------------------------------------------------------

class SaasProfile extends Equatable {
  const SaasProfile({
    required this.email,
    required this.permissions,
    required this.isFounder,
    required this.tenantCode,
    required this.tenantName,
    required this.status,
    this.roleName,
    this.planId,
  });

  final String email;
  final List<String> permissions;

  /// D7: `saas.manage` (+ correo en `NEXUS_FOUNDER_EMAILS` si está definido).
  final bool isFounder;
  final String tenantCode;
  final String tenantName;
  final SubscriptionStatus status;
  final String? roleName;
  final String? planId;

  factory SaasProfile.fromJson(Map<dynamic, dynamic> json) {
    final user = (json['user'] as Map?) ?? const {};
    final tenant = (json['tenant'] as Map?) ?? const {};
    return SaasProfile(
      email: (user['email'] ?? '').toString(),
      permissions: ((json['permissions'] as List?) ?? const [])
          .map((e) => e.toString())
          .toList(),
      isFounder: json['is_founder'] == true,
      tenantCode: (tenant['code'] ?? '').toString(),
      tenantName: (tenant['name'] ?? '').toString(),
      status:
          SubscriptionStatus.fromApi(tenant['subscription_status']?.toString()),
      roleName: user['role_name']?.toString(),
      planId: tenant['plan_id']?.toString(),
    );
  }

  bool get isOwner => roleName == 'TENANT_OWNER' || roleName == 'OWNER';

  @override
  List<Object?> get props =>
      [email, permissions, isFounder, tenantCode, status, roleName, planId];
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

double _toDouble(dynamic value) {
  if (value == null) return 0;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString()) ?? 0;
}

/// Suma meses calendario conservando el día (recortado al último del mes).
/// Espejo de `_add_months` del backend: una mensualidad por mes.
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
  final fixed = value.toStringAsFixed(2);
  final parts = fixed.split('.');
  final intPart = parts[0].replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+$)'),
    (m) => '${m[1]},',
  );
  return '\$$intPart.${parts[1]}';
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

/// "Sep 2026" — etiqueta del periodo de una factura.
String periodLabel(DateTime d) {
  final m = _months[d.month - 1];
  return '${m[0].toUpperCase()}${m.substring(1)} ${d.year}';
}
