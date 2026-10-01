/// Un tema de ayuda como lo edita el panel (P27: servido por el servidor).
/// Las acciones y los campos del formulario se conservan tal cual al guardar:
/// su edición es PD-07 (P29).
class AdminHelpTopic {
  const AdminHelpTopic({
    required this.key,
    required this.title,
    required this.summary,
    required this.body,
    required this.audience,
    required this.sortOrder,
    required this.isActive,
    required this.updatedAt,
    required this.rawActions,
    required this.rawFormFields,
    this.updatedByName,
  });

  final String key;
  final String title;
  final String summary;
  final String body;

  /// ALL, OWNER o ANONYMOUS.
  final String audience;
  final int sortOrder;
  final bool isActive;
  final DateTime updatedAt;
  final String? updatedByName;
  final List<Map<String, dynamic>> rawActions;
  final List<Map<String, dynamic>> rawFormFields;

  String get audienceLabel => audienceLabels[audience] ?? audience;

  static const audienceLabels = {
    'ALL': 'Todos los roles',
    'OWNER': 'Sólo dueños',
    'ANONYMOUS': 'Sin sesión (No puedo entrar)',
  };

  factory AdminHelpTopic.fromJson(Map<String, dynamic> json) => AdminHelpTopic(
        key: (json['key'] ?? '').toString(),
        title: (json['title'] ?? '').toString(),
        summary: (json['summary'] ?? '').toString(),
        body: (json['body'] ?? '').toString(),
        audience: (json['audience'] ?? 'ALL').toString(),
        sortOrder: (json['sort_order'] as num?)?.toInt() ?? 100,
        isActive: json['is_active'] != false,
        updatedAt: DateTime.parse(json['updated_at'] as String),
        updatedByName: json['updated_by_name'] as String?,
        rawActions: [for (final a in (json['actions'] as List? ?? const [])) Map<String, dynamic>.from(a as Map)],
        rawFormFields: [
          for (final f in (json['form_fields'] as List? ?? const [])) Map<String, dynamic>.from(f as Map)
        ],
      );
}

/// Lo editable (P29: sólo texto).
class HelpTopicDraft {
  const HelpTopicDraft({
    required this.title,
    required this.summary,
    required this.body,
    required this.audience,
    required this.sortOrder,
    required this.isActive,
  });

  final String title;
  final String summary;
  final String body;
  final String audience;
  final int sortOrder;
  final bool isActive;

  factory HelpTopicDraft.of(AdminHelpTopic t) => HelpTopicDraft(
        title: t.title,
        summary: t.summary,
        body: t.body,
        audience: t.audience,
        sortOrder: t.sortOrder,
        isActive: t.isActive,
      );

  bool sameAs(AdminHelpTopic t) =>
      title.trim() == t.title &&
      summary.trim() == t.summary &&
      body.trim() == t.body &&
      audience == t.audience &&
      sortOrder == t.sortOrder &&
      isActive == t.isActive;
}
