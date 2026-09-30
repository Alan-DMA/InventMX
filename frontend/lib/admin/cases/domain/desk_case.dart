import 'package:equatable/equatable.dart';

/// Estado del caso, escrito como lo ve el operador.
enum DeskCaseStatus {
  waiting('WAITING_SUPPORT', 'Esperando a soporte'),
  answered('ANSWERED', 'Respondido'),
  resolved('RESOLVED', 'Resuelto');

  const DeskCaseStatus(this.api, this.label);
  final String api;
  final String label;

  static DeskCaseStatus fromApi(String? raw) =>
      DeskCaseStatus.values.firstWhere((s) => s.api == raw, orElse: () => DeskCaseStatus.waiting);
}

/// Un renglón de la cola.
class DeskCase extends Equatable {
  const DeskCase({
    required this.id,
    required this.number,
    required this.fromApp,
    required this.topicTitle,
    required this.status,
    required this.contactEmail,
    required this.createdAt,
    required this.lastMessageAt,
    this.tenantId,
    this.tenantName,
    this.contactName,
    this.claimedStoreName,
    this.suggestedTenantName,
    this.lastMessagePreview,
    this.lastMessageBySupport,
  });

  final String id;
  final int number;

  /// Escrito desde la app (con sesión). Si no, llegó por el formulario sin
  /// sesión y la respuesta va por correo.
  final bool fromApp;
  final String? tenantId;
  final String? tenantName;
  final String topicTitle;
  final DeskCaseStatus status;
  final String contactEmail;
  final String? contactName;
  final String? claimedStoreName;
  final String? suggestedTenantName;
  final DateTime createdAt;
  final DateTime lastMessageAt;
  final String? lastMessagePreview;
  final bool? lastMessageBySupport;

  /// Cómo se nombra la tienda en la cola: la real, o lo que dijo quien
  /// escribió sin sesión.
  String get storeLabel => tenantName ?? claimedStoreName ?? 'Sin tienda';

  factory DeskCase.fromJson(Map<String, dynamic> json) => DeskCase(
        id: json['id'].toString(),
        number: (json['number'] as num).toInt(),
        fromApp: json['channel'] != 'PUBLIC',
        tenantId: json['tenant_id']?.toString(),
        tenantName: json['tenant_name'] as String?,
        topicTitle: (json['topic_title'] ?? '').toString(),
        status: DeskCaseStatus.fromApi(json['status'] as String?),
        contactEmail: (json['contact_email'] ?? '').toString(),
        contactName: json['contact_name'] as String?,
        claimedStoreName: json['claimed_store_name'] as String?,
        suggestedTenantName: json['suggested_tenant_name'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String),
        lastMessageAt: DateTime.parse(json['last_message_at'] as String),
        lastMessagePreview: json['last_message_preview'] as String?,
        lastMessageBySupport: json['last_message_by_support'] as bool?,
      );

  @override
  List<Object?> get props => [id, status, lastMessageAt, lastMessagePreview];
}

class DeskCasePage {
  const DeskCasePage({required this.items, required this.total});
  final List<DeskCase> items;
  final int total;

  factory DeskCasePage.fromJson(Map<String, dynamic> json) => DeskCasePage(
        items: [for (final e in json['items'] as List) DeskCase.fromJson(e as Map<String, dynamic>)],
        total: (json['total'] as num).toInt(),
      );
}

class DeskAnswer {
  const DeskAnswer({required this.label, required this.value});
  final String label;
  final String value;
}

class DeskMessage {
  const DeskMessage({
    required this.id,
    required this.fromSupport,
    required this.authorName,
    required this.body,
    required this.createdAt,
  });

  final String id;
  final bool fromSupport;
  final String authorName;
  final String body;
  final DateTime createdAt;

  factory DeskMessage.fromJson(Map<String, dynamic> json) => DeskMessage(
        id: json['id'].toString(),
        fromSupport: json['author_kind'] == 'SUPPORT',
        authorName: (json['author_name'] ?? '').toString(),
        body: (json['body'] ?? '').toString(),
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}

/// Metadatos de la tienda del caso (nunca su contenido, P2).
class DeskStore {
  const DeskStore({
    required this.tenantId,
    required this.name,
    required this.status,
    required this.plan,
    required this.suggested,
    this.paidUntil,
    this.lockReason,
  });

  final String tenantId;
  final String name;
  final String status;
  final String plan;
  final DateTime? paidUntil;
  final String? lockReason;

  /// Caso sin sesión: tienda cuyo correo coincide; falta validar (P21).
  final bool suggested;

  bool get suspendedForAbuse => lockReason == 'ABUSE' && status != 'ACTIVE';
  bool get lockedForNonPayment => !suspendedForAbuse && status == 'HARD_LOCK';

  String get planLabel => switch (plan) {
        'EMPRENDEDOR' => 'Plan Emprendedor',
        'COMERCIO' => 'Plan Comercio',
        'CORPORATIVO' => 'Plan Corporativo',
        _ => 'Plan $plan',
      };

  factory DeskStore.fromJson(Map<String, dynamic> json) => DeskStore(
        tenantId: json['tenant_id'].toString(),
        name: (json['name'] ?? '').toString(),
        status: (json['status'] ?? '').toString(),
        plan: (json['plan'] ?? '').toString(),
        paidUntil: json['paid_until'] == null ? null : DateTime.parse(json['paid_until'] as String),
        lockReason: json['lock_reason'] as String?,
        suggested: json['suggested'] == true,
      );
}

class DeskCaseDetail {
  const DeskCaseDetail({required this.summary, required this.answers, required this.messages, this.store});

  final DeskCase summary;
  final List<DeskAnswer> answers;
  final List<DeskMessage> messages;
  final DeskStore? store;

  factory DeskCaseDetail.fromJson(Map<String, dynamic> json) => DeskCaseDetail(
        summary: DeskCase.fromJson(json),
        answers: [
          for (final a in (json['answers'] as List? ?? const []))
            DeskAnswer(label: (a['label'] ?? '').toString(), value: (a['value'] ?? '').toString()),
        ],
        messages: [
          for (final m in (json['messages'] as List? ?? const [])) DeskMessage.fromJson(m as Map<String, dynamic>)
        ],
        store: json['store'] == null ? null : DeskStore.fromJson(json['store'] as Map<String, dynamic>),
      );
}
