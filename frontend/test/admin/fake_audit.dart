import 'package:nexus_app/admin/audit/data/audit_repository.dart';
import 'package:nexus_app/admin/audit/domain/audit_models.dart';
import 'package:nexus_app/admin/core/admin_http.dart';
import 'package:nexus_app/admin/help_topics/data/help_topics_repository.dart';
import 'package:nexus_app/admin/help_topics/domain/admin_help_topic.dart';

/// Bitácora en memoria: filtra como el servidor y anota cada consulta.
class FakeAudit implements AuditRepository {
  final List<AuditEntry> entries = [];
  final List<Map<String, Object?>> queries = [];
  ChainVerification chain = const ChainVerification(intact: true, checked: 42);
  bool failVerify = false;
  int verifications = 0;

  static const _noise = {'TENANT_VIEWED', 'LOGIN_SUCCEEDED', 'TOTP_ENROLLED', 'RECOVERY_CODE_USED'};

  /// `operator` guarda el id de quien la hizo (para "Sólo mis acciones").
  final Map<int, String> operatorOf = {};

  @override
  Future<AuditPage> list({
    String? action,
    String? tenantId,
    String? operatorId,
    bool excludeNoise = true,
    int limit = 50,
    int offset = 0,
  }) async {
    queries.add({'action': action, 'tenant': tenantId, 'operator': operatorId, 'noise': !excludeNoise});
    final all = entries
        .where((e) => action == null || e.action == action)
        .where((e) => tenantId == null || e.targetTenantId == tenantId)
        .where((e) => operatorId == null || operatorOf[e.id] == operatorId)
        .where((e) => !excludeNoise || action != null || !_noise.contains(e.action))
        .toList()
      ..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
    return AuditPage(items: all.skip(offset).take(limit).toList(), total: all.length);
  }

  @override
  Future<ChainVerification> verify() async {
    verifications++;
    if (failVerify) throw const AdminApiException('Sin conexión con el servidor.');
    return chain;
  }
}

/// Temas de ayuda en memoria.
class FakeTopics implements HelpTopicsRepository {
  final Map<String, AdminHelpTopic> topics = {};
  final List<Map<String, Object?>> saves = [];
  AdminApiException? failNext;

  void add(String key, String title, {String audience = 'ALL', int order = 10, bool active = true, String? by}) {
    topics[key] = AdminHelpTopic(
      key: key,
      title: title,
      summary: 'Resumen de $title',
      body: 'Antes de escribirnos, prueba esto:\n\n• Revisa que tengas internet.\n• Cierra y abre la app.',
      audience: audience,
      sortOrder: order,
      isActive: active,
      updatedAt: DateTime(2026, 9, 29, 10),
      updatedByName: by,
      rawActions: const [
        {'label': 'Ir a Mi suscripción', 'target': 'subscription'},
      ],
      rawFormFields: const [
        {
          'key': 'module',
          'label': '¿En qué parte de la app?',
          'type': 'select',
          'required': true,
          'options': ['Caja']
        },
      ],
    );
  }

  @override
  Future<List<AdminHelpTopic>> list() async =>
      topics.values.toList()..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

  @override
  Future<AdminHelpTopic> save(AdminHelpTopic original, HelpTopicDraft draft, {required String reason}) async {
    final f = failNext;
    if (f != null) {
      failNext = null;
      throw f;
    }
    saves.add({
      'key': original.key,
      'title': draft.title.trim(),
      'active': draft.isActive,
      'actions': original.rawActions,
      'form_fields': original.rawFormFields,
      'reason': reason,
    });
    final saved = AdminHelpTopic(
      key: original.key,
      title: draft.title.trim(),
      summary: draft.summary.trim(),
      body: draft.body.trim(),
      audience: draft.audience,
      sortOrder: draft.sortOrder,
      isActive: draft.isActive,
      updatedAt: DateTime(2026, 9, 30, 20),
      updatedByName: 'Eduardo Cristancho',
      rawActions: original.rawActions,
      rawFormFields: original.rawFormFields,
    );
    topics[original.key] = saved;
    return saved;
  }
}
