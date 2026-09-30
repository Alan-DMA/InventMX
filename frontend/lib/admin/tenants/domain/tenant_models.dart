/// Metadatos de una tienda (nunca su contenido, P2).
class TenantSummary {
  const TenantSummary({
    required this.id,
    required this.name,
    required this.slug,
    required this.plan,
    required this.status,
    required this.createdAt,
    required this.usersCount,
    required this.usersLimit,
    required this.entitlement,
    this.lockReason,
    this.ownerName,
    this.ownerEmail,
    this.lastActivityAt,
    this.paidUntil,
    this.graceUntil,
    this.subscriptionSource,
  });

  final String id;
  final String name;
  final String slug;
  final String plan;
  final String status;
  final String? lockReason;
  final DateTime createdAt;
  final String? ownerName;
  final String? ownerEmail;
  final int usersCount;
  final int usersLimit;
  final DateTime? lastActivityAt;
  final DateTime? paidUntil;
  final DateTime? graceUntil;

  /// VIGENTE / GRACIA / VENCIDA / SIN_FECHA.
  final String entitlement;

  /// TRIAL, COURTESY, MANUAL, GATEWAY o GOOGLE_PLAY.
  final String? subscriptionSource;

  static DateTime? _date(Object? raw) => raw == null ? null : DateTime.parse(raw as String);

  factory TenantSummary.fromJson(Map<String, dynamic> json) => TenantSummary(
        id: json['id'].toString(),
        name: (json['name'] ?? '').toString(),
        slug: (json['slug'] ?? '').toString(),
        plan: (json['plan'] ?? '').toString(),
        status: (json['status'] ?? '').toString(),
        lockReason: json['lock_reason'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String),
        ownerName: json['owner_name'] as String?,
        ownerEmail: json['owner_email'] as String?,
        usersCount: (json['users_count'] as num?)?.toInt() ?? 0,
        usersLimit: (json['users_limit'] as num?)?.toInt() ?? 0,
        lastActivityAt: _date(json['last_activity_at']),
        paidUntil: _date(json['paid_until']),
        graceUntil: _date(json['grace_until']),
        entitlement: (json['entitlement'] ?? 'SIN_FECHA').toString(),
        subscriptionSource: json['subscription_source'] as String?,
      );
}

class DiagnosticUser {
  const DiagnosticUser(
      {required this.fullName, required this.email, required this.isActive, this.role, this.lastLoginAt});
  final String fullName;
  final String email;
  final String? role;
  final bool isActive;
  final DateTime? lastLoginAt;
}

class DiagnosticWarehouse {
  const DiagnosticWarehouse({required this.name, required this.isActive, required this.isDefault});
  final String name;
  final bool isActive;
  final bool isDefault;
}

/// Una línea de la bitácora, ya en palabras.
class AuditLine {
  const AuditLine({required this.occurredAt, required this.action, required this.summary, this.reason});
  final DateTime occurredAt;
  final String action;
  final String summary;
  final String? reason;

  factory AuditLine.fromJson(Map<String, dynamic> json) => AuditLine(
        occurredAt: DateTime.parse(json['occurred_at'] as String),
        action: (json['action'] ?? '').toString(),
        summary: (json['summary'] ?? json['action'] ?? '').toString(),
        reason: json['reason'] as String?,
      );
}

/// Lo que está en curso con la tienda.
class SupportState {
  const SupportState({
    this.accessGrantedUntil,
    this.assistedCodeUntil,
    this.deletionRequestedBy,
    this.deletionExpiresAt,
    this.lastExportStatus,
    this.lastExportAt,
  });

  final DateTime? accessGrantedUntil;
  final DateTime? assistedCodeUntil;
  final String? deletionRequestedBy;
  final DateTime? deletionExpiresAt;

  /// PENDING / SENT / FAILED.
  final String? lastExportStatus;
  final DateTime? lastExportAt;

  bool get isEmpty =>
      accessGrantedUntil == null && assistedCodeUntil == null && deletionExpiresAt == null && lastExportStatus == null;
}

class TenantDetail {
  const TenantDetail({
    required this.summary,
    required this.warehouses,
    required this.users,
    required this.support,
    required this.activity,
    this.catalogEnabled,
    this.suspensionReason,
  });

  final TenantSummary summary;
  final bool? catalogEnabled;
  final List<DiagnosticWarehouse> warehouses;
  final List<DiagnosticUser> users;
  final SupportState support;
  final List<AuditLine> activity;
  final String? suspensionReason;

  factory TenantDetail.fromJson(Map<String, dynamic> json) {
    final diagnostics = (json['diagnostics'] as Map?) ?? const {};
    final support = (json['support'] as Map?) ?? const {};
    final deletion = support['pending_deletion'] as Map?;
    final export = support['last_export'] as Map?;
    return TenantDetail(
      summary: TenantSummary.fromJson(json),
      catalogEnabled: diagnostics['catalog_enabled'] as bool?,
      warehouses: [
        for (final w in (diagnostics['warehouses'] as List? ?? const []))
          DiagnosticWarehouse(
            name: (w['name'] ?? '').toString(),
            isActive: w['is_active'] != false,
            isDefault: w['is_default'] == true,
          ),
      ],
      users: [
        for (final u in (diagnostics['users'] as List? ?? const []))
          DiagnosticUser(
            fullName: (u['full_name'] ?? '').toString(),
            email: (u['email'] ?? '').toString(),
            role: u['role'] as String?,
            isActive: u['is_active'] != false,
            lastLoginAt: u['last_login_at'] == null ? null : DateTime.parse(u['last_login_at'] as String),
          ),
      ],
      support: SupportState(
        accessGrantedUntil: TenantSummary._date(support['access_granted_until']),
        assistedCodeUntil: TenantSummary._date(support['assisted_code_until']),
        deletionRequestedBy: deletion?['requested_by_name'] as String?,
        deletionExpiresAt: TenantSummary._date(deletion?['expires_at']),
        lastExportStatus: export?['status'] as String?,
        lastExportAt: TenantSummary._date(export?['created_at']),
      ),
      activity: [
        for (final a in (json['activity'] as List? ?? const [])) AuditLine.fromJson(a as Map<String, dynamic>)
      ],
      suspensionReason: json['suspension_reason'] as String?,
    );
  }
}
