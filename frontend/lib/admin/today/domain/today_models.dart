/// Lo que pide decisión o seguimiento (no lo que sólo pasó).
class AttentionItem {
  const AttentionItem({
    required this.kind,
    required this.tenantName,
    required this.since,
    required this.summary,
    required this.awaitingYou,
    this.tenantId,
    this.until,
    this.refId,
  });

  /// DELETION_PENDING, EXPORT_IN_PROGRESS, EXPORT_FAILED, SUPPORT_ACCESS_ACTIVE, SUPPORT_SESSION_OPEN,
  /// ASSISTED_CODE_UNUSED, ABUSE_SUSPENSION o CASE_WAITING.
  final String kind;
  final String? tenantId;
  final String tenantName;
  final DateTime since;
  final DateTime? until;
  final String summary;
  final String? refId;

  /// Eliminación pedida por el otro fundador: te toca aprobarla o cancelarla.
  final bool awaitingYou;

  factory AttentionItem.fromJson(Map<String, dynamic> json) => AttentionItem(
        kind: (json['kind'] ?? '').toString(),
        tenantId: json['tenant_id']?.toString(),
        tenantName: (json['tenant_name'] ?? '').toString(),
        since: DateTime.parse(json['since'] as String),
        until: json['until'] == null ? null : DateTime.parse(json['until'] as String),
        summary: (json['summary'] ?? '').toString(),
        refId: json['ref_id']?.toString(),
        awaitingYou: json['awaiting_you'] == true,
      );
}

/// Algo que pasó (acción de soporte, tienda nueva, caso nuevo).
class FeedEvent {
  const FeedEvent({required this.kind, required this.occurredAt, required this.summary, this.tenantId, this.reason});

  /// AUDIT, SIGNUP o CASE.
  final String kind;
  final DateTime occurredAt;
  final String? tenantId;
  final String summary;
  final String? reason;

  factory FeedEvent.fromJson(Map<String, dynamic> json) => FeedEvent(
        kind: (json['kind'] ?? '').toString(),
        occurredAt: DateTime.parse(json['occurred_at'] as String),
        tenantId: json['tenant_id']?.toString(),
        summary: (json['summary'] ?? '').toString(),
        reason: json['reason'] as String?,
      );
}

class FeedPage {
  const FeedPage({required this.attention, required this.events});
  final List<AttentionItem> attention;
  final List<FeedEvent> events;

  factory FeedPage.fromJson(Map<String, dynamic> json) => FeedPage(
        attention: [
          for (final a in (json['attention'] as List? ?? const [])) AttentionItem.fromJson(a as Map<String, dynamic>)
        ],
        events: [for (final e in (json['events'] as List? ?? const [])) FeedEvent.fromJson(e as Map<String, dynamic>)],
      );
}

/// Columna lateral: conteos, sin gráficas. El ingreso sólo existe cuando
/// Google Play esté conectado (P13/P19).
class PlatformMetrics {
  const PlatformMetrics({
    required this.tenantsTotal,
    required this.byStatus,
    required this.byPlan,
    required this.signupsLast30Days,
    required this.abuseSuspended,
    required this.revenueConnected,
    this.monthlyRevenueMxn,
  });

  final int tenantsTotal;
  final Map<String, int> byStatus;
  final Map<String, int> byPlan;
  final int signupsLast30Days;
  final int abuseSuspended;
  final bool revenueConnected;
  final double? monthlyRevenueMxn;

  static Map<String, int> _counts(Object? raw) =>
      {for (final e in ((raw as Map?) ?? const {}).entries) e.key.toString(): (e.value as num).toInt()};

  factory PlatformMetrics.fromJson(Map<String, dynamic> json) => PlatformMetrics(
        tenantsTotal: (json['tenants_total'] as num?)?.toInt() ?? 0,
        byStatus: _counts(json['tenants_by_status']),
        byPlan: _counts(json['tenants_by_plan']),
        signupsLast30Days: (json['signups_last_30_days'] as num?)?.toInt() ?? 0,
        abuseSuspended: (json['abuse_suspended'] as num?)?.toInt() ?? 0,
        revenueConnected: json['revenue_connected'] == true,
        monthlyRevenueMxn:
            json['monthly_revenue_mxn'] == null ? null : double.tryParse(json['monthly_revenue_mxn'].toString()),
      );
}
