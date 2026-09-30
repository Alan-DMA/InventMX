import 'package:nexus_app/admin/core/admin_http.dart';
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
        subscriptionSource: 'TRIAL',
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
      support: const SupportState(),
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
