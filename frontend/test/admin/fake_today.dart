import 'package:nexus_app/admin/core/admin_http.dart';
import 'package:nexus_app/admin/tenants/data/support_actions_repository.dart';
import 'package:nexus_app/admin/tenants/data/tenants_repository.dart';
import 'package:nexus_app/admin/tenants/domain/tenant_models.dart';
import 'package:nexus_app/admin/today/data/today_repository.dart';
import 'package:nexus_app/admin/today/domain/today_models.dart';

/// "Hoy" en memoria: devuelve los eventos del rango pedido y anota cada rango
/// (para probar que "Ver días anteriores" no deja huecos ni repite).
class FakeToday implements TodayRepository {
  final List<AttentionItem> attention = [];
  final List<FeedEvent> events = [];
  final List<(DateTime, DateTime)> ranges = [];
  bool failFeed = false;
  PlatformMetrics metricsValue = const PlatformMetrics(
    tenantsTotal: 212,
    byStatus: {'ACTIVE': 198, 'SOFT_LOCK': 6, 'HARD_LOCK': 8},
    byPlan: {'EMPRENDEDOR': 150, 'COMERCIO': 50, 'CORPORATIVO': 12},
    signupsLast30Days: 14,
    abuseSuspended: 2,
    revenueConnected: false,
  );

  @override
  Future<FeedPage> feed({required DateTime since, required DateTime until}) async {
    if (failFeed) throw const AdminApiException('Sin conexión con el servidor. Revisa tu red y vuelve a intentar.');
    ranges.add((since, until));
    return FeedPage(
      attention: List.of(attention),
      events: events.where((e) => !e.occurredAt.isBefore(since) && e.occurredAt.isBefore(until)).toList(),
    );
  }

  @override
  Future<PlatformMetrics> metrics() async => metricsValue;
}

/// Tiendas en memoria.
class FakeTenants implements TenantsRepository {
  final Map<String, TenantDetail> tenants = {};
  int views = 0;

  void add({
    required String id,
    required String name,
    String status = 'ACTIVE',
    String? lockReason,
    String? suspensionReason,
    String ownerEmail = 'sol@tiendita.mx',
    String subscriptionSource = 'TRIAL',
    SupportState support = const SupportState(),
  }) {
    tenants[id] = TenantDetail(
      summary: TenantSummary(
        id: id,
        name: name,
        slug: name.toLowerCase().replaceAll(' ', '-'),
        plan: 'COMERCIO',
        status: status,
        lockReason: lockReason,
        createdAt: DateTime(2026, 8, 12),
        ownerName: 'Doña Sol',
        ownerEmail: ownerEmail,
        usersCount: 2,
        usersLimit: 5,
        paidUntil: DateTime(2026, 10, 27),
        entitlement: 'VIGENTE',
        subscriptionSource: subscriptionSource,
      ),
      catalogEnabled: true,
      warehouses: const [DiagnosticWarehouse(name: 'Almacén Principal', isActive: true, isDefault: true)],
      users: [
        DiagnosticUser(
          fullName: 'Doña Sol',
          email: ownerEmail,
          role: 'OWNER',
          isActive: true,
          lastLoginAt: DateTime(2026, 9, 30, 18),
        ),
      ],
      support: support,
      activity: [
        AuditLine(
          occurredAt: DateTime(2026, 9, 30, 14, 5),
          action: 'DAYS_GIFTED',
          summary: 'Eduardo regaló 7 días a $name',
          reason: 'Compensación por la falla del cierre de turno',
        ),
      ],
      suspensionReason: suspensionReason,
    );
  }

  @override
  Future<List<TenantSummary>> search(String query, {int limit = 20}) async {
    final q = query.toLowerCase();
    return tenants.values
        .map((t) => t.summary)
        .where((t) =>
            t.name.toLowerCase().contains(q) || t.slug.contains(q) || (t.ownerEmail ?? '').toLowerCase().contains(q))
        .take(limit)
        .toList();
  }

  @override
  Future<TenantDetail> detail(String id) async {
    views++;
    final t = tenants[id];
    if (t == null) throw const AdminApiException('Comercio no encontrado.', statusCode: 404);
    return t;
  }
}

/// Acciones de soporte en memoria: cambian las tiendas de [FakeTenants] como
/// lo haría el servidor y anotan cada llamada.
class FakeActions implements SupportActionsRepository {
  FakeActions(this.tenants, this.now);

  final FakeTenants tenants;
  final DateTime Function() now;
  final List<String> calls = [];
  AdminApiException? failNext;
  bool failPreview = false;
  int previewCalls = 0;

  void _maybeFail() {
    final f = failNext;
    if (f != null) {
      failNext = null;
      throw f;
    }
  }

  TenantDetail _update(String id,
      {String? status, String? lockReason, DateTime? paidUntil, String? suspension, bool clearLock = false}) {
    final d = tenants.tenants[id]!;
    final t = d.summary;
    final updated = TenantDetail(
      summary: TenantSummary(
        id: t.id,
        name: t.name,
        slug: t.slug,
        plan: t.plan,
        status: status ?? t.status,
        lockReason: clearLock ? null : lockReason ?? t.lockReason,
        createdAt: t.createdAt,
        ownerName: t.ownerName,
        ownerEmail: t.ownerEmail,
        usersCount: t.usersCount,
        usersLimit: t.usersLimit,
        paidUntil: paidUntil ?? t.paidUntil,
        entitlement: t.entitlement,
        subscriptionSource: t.subscriptionSource,
      ),
      catalogEnabled: d.catalogEnabled,
      warehouses: d.warehouses,
      users: d.users,
      support: d.support,
      activity: d.activity,
      suspensionReason: clearLock ? null : suspension ?? d.suspensionReason,
    );
    tenants.tenants[id] = updated;
    return updated;
  }

  @override
  Future<OwnerPreview> preview(String tenantId, PreviewAction action, {String? reason, int? days}) async {
    previewCalls++;
    if (failPreview) throw const AdminApiException('Sin conexión con el servidor.');
    final summary = switch (action) {
      PreviewAction.giftDays => 'Soporte Nexus te regaló $days ${days == 1 ? 'día' : 'días'}.',
      PreviewAction.suspend => 'Soporte Nexus suspendió tu tienda.',
      PreviewAction.lift => 'Soporte Nexus levantó la suspensión de tu tienda.',
      PreviewAction.export => 'Soporte Nexus preparó una copia de tus datos; te llegará por correo.',
      PreviewAction.assistedRecovery => 'Soporte Nexus te envió un código para entrar.',
      PreviewAction.deletion => 'Soporte Nexus pidió eliminar tu tienda.',
    };
    return OwnerPreview(summary: summary, reason: reason, by: 'Soporte Nexus · Eduardo');
  }

  @override
  Future<RecoverySent> assistedRecovery(String tenantId,
      {required String reason, required Map<String, bool> checks, String? googleOrderId}) async {
    _maybeFail();
    calls.add('recovery:${checks.values.every((v) => v)}:${googleOrderId ?? ''}');
    return RecoverySent(sentTo: 's•••@tiendita.mx', expiresAt: now().add(const Duration(hours: 24)));
  }

  @override
  Future<TenantDetail> giftDays(String tenantId, {required int days, required String reason}) async {
    _maybeFail();
    calls.add('gift:$days');
    final t = tenants.tenants[tenantId]!.summary;
    return _update(tenantId, paidUntil: (t.paidUntil ?? now()).add(Duration(days: days)));
  }

  @override
  Future<TenantDetail> suspend(String tenantId, {required String reason}) async {
    _maybeFail();
    calls.add('suspend');
    return _update(tenantId, status: 'HARD_LOCK', lockReason: 'ABUSE', suspension: reason);
  }

  @override
  Future<TenantDetail> lift(String tenantId, {required String reason}) async {
    _maybeFail();
    calls.add('lift');
    return _update(tenantId, status: 'ACTIVE', clearLock: true);
  }

  @override
  Future<String> export(String tenantId, {required String reason}) async {
    _maybeFail();
    calls.add('export');
    return 'PENDING';
  }

  @override
  Future<DeletionRequestRead> requestDeletion(String tenantId,
      {required String reason, required String confirmSlug}) async {
    _maybeFail();
    calls.add('delete:$confirmSlug');
    return DeletionRequestRead(
      id: 'req-1',
      requestedById: 'op-me',
      requestedBy: 'Eduardo',
      reason: reason,
      expiresAt: now().add(const Duration(hours: 72)),
    );
  }

  @override
  Future<void> approveDeletion(String requestId, {required String reason}) async {
    _maybeFail();
    calls.add('approve:$requestId');
  }

  @override
  Future<void> cancelDeletion(String requestId, {required String reason}) async {
    _maybeFail();
    calls.add('cancel:$requestId');
  }
}
