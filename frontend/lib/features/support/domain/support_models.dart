import 'package:equatable/equatable.dart';

import '../../saas_admin/domain/subscription.dart' show shortDate;

/// Apartado de Soporte, estilo Steam (Centro de soporte, P23–P27).
///
/// Los temas (ayuda + formulario) los sirve el servidor (`GET /support/topics`)
/// y se editan desde el panel sin publicar la app: aquí sólo se pintan.

// ---------------------------------------------------------------------------
// Temas de ayuda
// ---------------------------------------------------------------------------

enum FormFieldType {
  text,
  textarea,
  select;

  static FormFieldType fromApi(String? raw) => switch (raw) {
        'textarea' => FormFieldType.textarea,
        'select' => FormFieldType.select,
        _ => FormFieldType.text,
      };
}

class FormFieldSpec extends Equatable {
  const FormFieldSpec({
    required this.key,
    required this.label,
    required this.type,
    this.required = false,
    this.options = const [],
  });

  final String key;
  final String label;
  final FormFieldType type;
  final bool required;
  final List<String> options;

  factory FormFieldSpec.fromJson(Map<dynamic, dynamic> json) => FormFieldSpec(
        key: (json['key'] ?? '').toString(),
        label: (json['label'] ?? '').toString(),
        type: FormFieldType.fromApi(json['type']?.toString()),
        required: json['required'] == true,
        options: (json['options'] as List? ?? const []).map((o) => o.toString()).toList(),
      );

  @override
  List<Object?> get props => [key, label, type, required, options];
}

/// Botón de la ayuda que lleva a una pantalla de la app. La app ignora los
/// `target` que no conoce (un tema nuevo del servidor no rompe la app vieja).
class TopicAction extends Equatable {
  const TopicAction({required this.label, required this.target});

  final String label;
  final String target;

  factory TopicAction.fromJson(Map<dynamic, dynamic> json) =>
      TopicAction(label: (json['label'] ?? '').toString(), target: (json['target'] ?? '').toString());

  @override
  List<Object?> get props => [label, target];
}

/// Un bloque del texto de ayuda: párrafo o lista de viñetas.
class HelpBlock extends Equatable {
  const HelpBlock.paragraph(this.text) : bullets = const [];
  const HelpBlock.bullets(this.bullets) : text = '';

  final String text;
  final List<String> bullets;

  bool get isList => bullets.isNotEmpty;

  @override
  List<Object?> get props => [text, bullets];
}

class HelpTopic extends Equatable {
  const HelpTopic({
    required this.key,
    required this.title,
    this.summary = '',
    this.body = '',
    this.actions = const [],
    this.formFields = const [],
  });

  final String key;
  final String title;
  final String summary;

  /// Párrafos separados por línea en blanco; "• " al inicio de línea = viñeta.
  final String body;
  final List<TopicAction> actions;
  final List<FormFieldSpec> formFields;

  factory HelpTopic.fromJson(Map<dynamic, dynamic> json) => HelpTopic(
        key: (json['key'] ?? '').toString(),
        title: (json['title'] ?? '').toString(),
        summary: (json['summary'] ?? '').toString(),
        body: (json['body'] ?? '').toString(),
        actions: (json['actions'] as List? ?? const []).whereType<Map>().map(TopicAction.fromJson).toList(),
        formFields: (json['form_fields'] as List? ?? const []).whereType<Map>().map(FormFieldSpec.fromJson).toList(),
      );

  /// El cuerpo en bloques: las líneas seguidas con viñeta forman una lista.
  List<HelpBlock> get blocks {
    final result = <HelpBlock>[];
    for (final chunk in body.split(RegExp(r'\n\s*\n'))) {
      final lines = chunk.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
      final prose = <String>[];
      final bullets = <String>[];
      void flushProse() {
        if (prose.isNotEmpty) result.add(HelpBlock.paragraph(prose.join(' ')));
        prose.clear();
      }

      void flushBullets() {
        if (bullets.isNotEmpty) result.add(HelpBlock.bullets(List.of(bullets)));
        bullets.clear();
      }

      for (final line in lines) {
        if (line.startsWith('•')) {
          flushProse();
          bullets.add(line.substring(1).trim());
        } else {
          flushBullets();
          prose.add(line);
        }
      }
      flushProse();
      flushBullets();
    }
    return result;
  }

  @override
  List<Object?> get props => [key, title, summary, body, actions, formFields];
}

// ---------------------------------------------------------------------------
// Casos
// ---------------------------------------------------------------------------

enum CaseStatus {
  waitingSupport,
  answered,
  resolved;

  static CaseStatus fromApi(String? raw) => switch (raw) {
        'ANSWERED' => CaseStatus.answered,
        'RESOLVED' => CaseStatus.resolved,
        _ => CaseStatus.waitingSupport,
      };

  String get label => switch (this) {
        CaseStatus.waitingSupport => 'Esperando a soporte',
        CaseStatus.answered => 'Respondido',
        CaseStatus.resolved => 'Resuelto',
      };
}

class CaseAnswer extends Equatable {
  const CaseAnswer({required this.label, required this.value});

  final String label;
  final String value;

  factory CaseAnswer.fromJson(Map<dynamic, dynamic> json) =>
      CaseAnswer(label: (json['label'] ?? '').toString(), value: (json['value'] ?? '').toString());

  @override
  List<Object?> get props => [label, value];
}

class CaseMessage extends Equatable {
  const CaseMessage({
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

  factory CaseMessage.fromJson(Map<dynamic, dynamic> json) => CaseMessage(
        id: (json['id'] ?? '').toString(),
        fromSupport: json['author_kind'] == 'SUPPORT',
        authorName: (json['author_name'] ?? '').toString(),
        body: (json['body'] ?? '').toString(),
        createdAt: _date(json['created_at']),
      );

  @override
  List<Object?> get props => [id, fromSupport, authorName, body, createdAt];
}

class SupportCase extends Equatable {
  const SupportCase({
    required this.id,
    required this.number,
    required this.topicKey,
    required this.topicTitle,
    required this.status,
    required this.createdAt,
    required this.lastMessageAt,
    this.unread = false,
    this.authorName,
    this.isMine = true,
    this.answers = const [],
    this.messages = const [],
  });

  final String id;
  final int number;
  final String topicKey;
  final String topicTitle;
  final CaseStatus status;
  final DateTime createdAt;
  final DateTime lastMessageAt;

  /// Soporte respondió y quien escribió no lo ha abierto (la insignia).
  final bool unread;
  final String? authorName;

  /// `false` cuando el dueño ve el caso de alguien de su equipo.
  final bool isMine;

  /// Sólo en el detalle.
  final List<CaseAnswer> answers;
  final List<CaseMessage> messages;

  factory SupportCase.fromJson(Map<dynamic, dynamic> json) => SupportCase(
        id: (json['id'] ?? '').toString(),
        number: (json['number'] as num?)?.toInt() ?? 0,
        topicKey: (json['topic_key'] ?? '').toString(),
        topicTitle: (json['topic_title'] ?? '').toString(),
        status: CaseStatus.fromApi(json['status']?.toString()),
        createdAt: _date(json['created_at']),
        lastMessageAt: _date(json['last_message_at']),
        unread: json['unread'] == true,
        authorName: json['author_name']?.toString(),
        isMine: json['is_mine'] != false,
        answers: (json['answers'] as List? ?? const []).whereType<Map>().map(CaseAnswer.fromJson).toList(),
        messages: (json['messages'] as List? ?? const []).whereType<Map>().map(CaseMessage.fromJson).toList(),
      );

  @override
  List<Object?> get props =>
      [id, number, topicKey, topicTitle, status, createdAt, lastMessageAt, unread, authorName, isMine, answers, messages];
}

DateTime _date(dynamic raw) => DateTime.tryParse(raw?.toString() ?? '')?.toLocal() ?? DateTime.now();

/// "10:15" — hora local a 24 h.
String clockTime(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

/// "28 sep · 10:15" — cuándo pasó algo en un caso.
String caseMoment(DateTime d) => '${shortDate(d)} · ${clockTime(d)}';
