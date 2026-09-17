import 'package:equatable/equatable.dart';
import 'subscription.dart';

/// Dominio del panel de fundadores — Tarea 14.2.2 (Constitución Art. V §5.3).

/// GET /api/v1/saas/admin/metrics
class FounderMetrics extends Equatable {
  const FounderMetrics({
    required this.mrrMxn,
    required this.tenantsTotal,
    required this.tenantsActive,
    required this.tenantsSoftLock,
    required this.tenantsHardLock,
    required this.newTenants30d,
    required this.pendingValidations,
    required this.retentionRate,
  });

  /// Suma de la tarifa del plan de los comercios ACTIVE.
  final double mrrMxn;
  final int tenantsTotal;
  final int tenantsActive;
  final int tenantsSoftLock;
  final int tenantsHardLock;
  final int newTenants30d;
  final int pendingValidations;

  /// activos / total (0–1).
  final double retentionRate;

  int get tenantsOverdue => tenantsSoftLock + tenantsHardLock;

  factory FounderMetrics.fromJson(Map<dynamic, dynamic> json) => FounderMetrics(
        mrrMxn: _toDouble(json['mrr_mxn']),
        tenantsTotal: (json['tenants_total'] as num?)?.toInt() ?? 0,
        tenantsActive: (json['tenants_active'] as num?)?.toInt() ?? 0,
        tenantsSoftLock: (json['tenants_soft_lock'] as num?)?.toInt() ?? 0,
        tenantsHardLock: (json['tenants_hard_lock'] as num?)?.toInt() ?? 0,
        newTenants30d: (json['new_tenants_30d'] as num?)?.toInt() ?? 0,
        pendingValidations: (json['pending_validations'] as num?)?.toInt() ?? 0,
        retentionRate: _toDouble(json['retention_rate']),
      );

  @override
  List<Object?> get props => [
        mrrMxn,
        tenantsTotal,
        tenantsActive,
        tenantsSoftLock,
        tenantsHardLock,
        newTenants30d,
        pendingValidations,
        retentionRate,
      ];
}

/// Fila de GET /api/v1/saas/admin/tenants
class TenantSummary extends Equatable {
  const TenantSummary({
    required this.id,
    required this.code,
    required this.name,
    required this.status,
    this.ownerEmail,
    this.plan,
    this.createdAt,
    this.pendingInvoice,
    this.daysOverdue = 0,
    this.lastValidation,
  });

  final String id;
  final String code;
  final String name;
  final SubscriptionStatus status;
  final String? ownerEmail;
  final SaasPlan? plan;
  final DateTime? createdAt;
  final SubscriptionInvoice? pendingInvoice;
  final int daysOverdue;
  final PaymentValidation? lastValidation;

  factory TenantSummary.fromJson(Map<dynamic, dynamic> json) => TenantSummary(
        id: json['id'].toString(),
        code: (json['code'] ?? '').toString(),
        name: (json['name'] ?? '').toString(),
        status:
            SubscriptionStatus.fromApi(json['subscription_status']?.toString()),
        ownerEmail: json['owner_email']?.toString(),
        plan:
            json['plan'] is Map ? SaasPlan.fromJson(json['plan'] as Map) : null,
        createdAt: json['created_at'] == null
            ? null
            : DateTime.tryParse(json['created_at'].toString()),
        pendingInvoice: json['pending_invoice'] is Map
            ? SubscriptionInvoice.fromJson(json['pending_invoice'] as Map)
            : null,
        daysOverdue: (json['days_overdue'] as num?)?.toInt() ?? 0,
        lastValidation: json['last_validation'] is Map
            ? PaymentValidation.fromJson(json['last_validation'] as Map)
            : null,
      );

  TenantSummary copyWith({
    SubscriptionStatus? status,
    SaasPlan? plan,
    SubscriptionInvoice? pendingInvoice,
    int? daysOverdue,
    PaymentValidation? lastValidation,
  }) =>
      TenantSummary(
        id: id,
        code: code,
        name: name,
        status: status ?? this.status,
        ownerEmail: ownerEmail,
        plan: plan ?? this.plan,
        createdAt: createdAt,
        pendingInvoice: pendingInvoice ?? this.pendingInvoice,
        daysOverdue: daysOverdue ?? this.daysOverdue,
        lastValidation: lastValidation ?? this.lastValidation,
      );

  @override
  List<Object?> get props => [
        id,
        code,
        name,
        status,
        plan,
        pendingInvoice,
        daysOverdue,
        lastValidation
      ];
}

/// Fila de la bandeja: GET /api/v1/saas/admin/payment-validations
class ValidationInboxItem extends Equatable {
  const ValidationInboxItem({
    required this.validation,
    required this.tenantId,
    required this.tenantCode,
    required this.tenantName,
    required this.invoiceAmountMxn,
    required this.invoiceDueDate,
  });

  final PaymentValidation validation;
  final String tenantId;
  final String tenantCode;
  final String tenantName;
  final double invoiceAmountMxn;
  final DateTime invoiceDueDate;

  factory ValidationInboxItem.fromJson(Map<dynamic, dynamic> json) =>
      ValidationInboxItem(
        validation: PaymentValidation.fromJson(json),
        tenantId: (json['tenant_id'] ?? '').toString(),
        tenantCode: (json['tenant_code'] ?? '').toString(),
        tenantName: (json['tenant_name'] ?? '').toString(),
        invoiceAmountMxn: _toDouble(json['invoice_amount']),
        invoiceDueDate: DateTime.parse(json['invoice_due_date'].toString()),
      );

  @override
  List<Object?> get props => [validation, tenantId, invoiceAmountMxn];
}

/// Filtros de la lista de comercios del panel.
class TenantFilter extends Equatable {
  const TenantFilter({this.status, this.planId, this.query = ''});

  final SubscriptionStatus? status;
  final String? planId;
  final String query;

  bool get isEmpty => status == null && planId == null && query.isEmpty;

  TenantFilter copyWith({
    SubscriptionStatus? status,
    bool clearStatus = false,
    String? planId,
    bool clearPlan = false,
    String? query,
  }) =>
      TenantFilter(
        status: clearStatus ? null : (status ?? this.status),
        planId: clearPlan ? null : (planId ?? this.planId),
        query: query ?? this.query,
      );

  @override
  List<Object?> get props => [status, planId, query];
}

double _toDouble(dynamic value) {
  if (value == null) return 0;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString()) ?? 0;
}
