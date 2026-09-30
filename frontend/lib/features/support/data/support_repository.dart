import 'package:dio/dio.dart';

import '../../../core/network/dio_client.dart';
import '../domain/support_models.dart';

/// Apartado de Soporte contra el backend (`/api/v1/support/*`, etapa 2a).
abstract class SupportRepository {
  /// GET /support/topics — los del rol en sesión (los de dueño sólo al dueño).
  Future<List<HelpTopic>> topics();

  /// GET /support/public/topics — para quien no puede entrar (P24).
  Future<List<HelpTopic>> publicTopics();

  /// GET /support/cases — los míos; el dueño ve los de toda la tienda (P25).
  Future<List<SupportCase>> cases();

  /// GET /support/cases/{id} — abrirlo marca leída la respuesta de soporte.
  Future<SupportCase> caseDetail(String id);

  /// POST /support/cases
  Future<SupportCase> createCase({
    required String topicKey,
    required Map<String, String> answers,
    required String description,
  });

  /// POST /support/cases/{id}/messages — responder reabre un caso resuelto.
  Future<SupportCase> reply(String id, String body);

  /// POST /support/cases/{id}/resolve
  Future<SupportCase> resolve(String id);

  /// GET /support/cases/unread — la insignia de ☰ · Soporte.
  Future<int> unreadCount();

  /// POST /support/public/cases — responde lo mismo siempre; devuelve el texto.
  Future<String> createPublicCase({
    required String topicKey,
    required Map<String, String> answers,
    required String description,
    required String accountEmail,
    required String storeName,
    required String contactEmail,
    String? contactName,
  });
}

class SupportException implements Exception {
  const SupportException(this.message);
  final String message;

  @override
  String toString() => message;
}

// ---------------------------------------------------------------------------
// Implementación real
// ---------------------------------------------------------------------------

class SupportRepositoryImpl implements SupportRepository {
  SupportRepositoryImpl({required this.client});

  final DioClient client;

  static const _base = '/api/v1/support';

  @override
  Future<List<HelpTopic>> topics() => _list('$_base/topics', HelpTopic.fromJson, 'No pudimos cargar los temas de ayuda.');

  @override
  Future<List<HelpTopic>> publicTopics() =>
      _list('$_base/public/topics', HelpTopic.fromJson, 'No pudimos cargar la ayuda.');

  @override
  Future<List<SupportCase>> cases() => _list('$_base/cases', SupportCase.fromJson, 'No pudimos cargar tus casos.');

  @override
  Future<SupportCase> caseDetail(String id) =>
      _one(() => client.get('$_base/cases/$id'), 'No pudimos abrir el caso.');

  @override
  Future<SupportCase> createCase({
    required String topicKey,
    required Map<String, String> answers,
    required String description,
  }) =>
      _one(
        () => client.post('$_base/cases', data: {
          'topic_key': topicKey,
          'answers': answers,
          'description': description,
        }),
        'No pudimos enviar tu caso. Intenta de nuevo.',
      );

  @override
  Future<SupportCase> reply(String id, String body) =>
      _one(() => client.post('$_base/cases/$id/messages', data: {'body': body}), 'No pudimos enviar tu mensaje.');

  @override
  Future<SupportCase> resolve(String id) =>
      _one(() => client.post('$_base/cases/$id/resolve'), 'No pudimos marcar el caso como resuelto.');

  @override
  Future<int> unreadCount() async {
    try {
      final res = await client.get('$_base/cases/unread');
      final dynamic data = res.data;
      return data is Map ? (data['unread'] as num?)?.toInt() ?? 0 : 0;
    } on DioException catch (e) {
      throw _map(e, 'No pudimos revisar tus casos.');
    }
  }

  @override
  Future<String> createPublicCase({
    required String topicKey,
    required Map<String, String> answers,
    required String description,
    required String accountEmail,
    required String storeName,
    required String contactEmail,
    String? contactName,
  }) async {
    try {
      final res = await client.post('$_base/public/cases', data: {
        'topic_key': topicKey,
        'answers': answers,
        'description': description,
        'account_email': accountEmail,
        'store_name': storeName,
        'contact_email': contactEmail,
        if (contactName != null && contactName.isNotEmpty) 'contact_name': contactName,
      });
      final dynamic data = res.data;
      return data is Map && data['message'] != null ? data['message'].toString() : kPublicCaseAccepted;
    } on DioException catch (e) {
      throw _map(e, 'No pudimos enviar tu mensaje. Intenta de nuevo.');
    }
  }

  Future<List<T>> _list<T>(String path, T Function(Map<dynamic, dynamic>) parse, String fallback) async {
    try {
      final res = await client.get(path);
      return (res.data as List? ?? const []).whereType<Map>().map(parse).toList();
    } on DioException catch (e) {
      throw _map(e, fallback);
    }
  }

  Future<SupportCase> _one(Future<Response<dynamic>> Function() call, String fallback) async {
    try {
      final res = await call();
      return SupportCase.fromJson(res.data as Map);
    } on DioException catch (e) {
      throw _map(e, fallback);
    }
  }

  /// El backend explica el rechazo ("Falta responder: …"); se muestra tal cual.
  static SupportException _map(DioException e, String fallback) {
    if (e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout) {
      return const SupportException('Sin conexión con el servidor. Revisa tu red e intenta de nuevo.');
    }
    final dynamic data = e.response?.data;
    if (data is Map) {
      final dynamic error = data['error'];
      if (error is Map && error['message'] is String) return SupportException(error['message'] as String);
      if (data['detail'] is String) return SupportException(data['detail'] as String);
    }
    return SupportException(fallback);
  }
}

/// Lo que responde el formulario sin sesión, exista o no la cuenta.
const kPublicCaseAccepted =
    'Recibimos tu mensaje. Si los datos son correctos, te escribimos al correo de contacto que nos diste.';

// ---------------------------------------------------------------------------
// Mock — demo sin backend y tests
// ---------------------------------------------------------------------------

class SupportRepositoryMock implements SupportRepository {
  SupportRepositoryMock({
    this.latency = const Duration(milliseconds: 250),
    List<HelpTopic>? topics,
    List<SupportCase>? cases,
    DateTime Function()? now,
  })  : _topics = topics ?? demoTopics,
        _cases = [...?cases],
        _now = now ?? DateTime.now;

  final Duration latency;
  final List<HelpTopic> _topics;
  final List<SupportCase> _cases;
  final DateTime Function() _now;
  int _nextNumber = 1042;

  /// Lo que se envió sin sesión (para los tests).
  final List<Map<String, String>> publicCases = [];

  Future<void> _wait() => Future.delayed(latency);

  @override
  Future<List<HelpTopic>> topics() async {
    await _wait();
    return _topics.where((t) => t.key != 'cannot_login').toList();
  }

  @override
  Future<List<HelpTopic>> publicTopics() async {
    await _wait();
    return _topics.where((t) => t.key == 'cannot_login').toList();
  }

  @override
  Future<List<SupportCase>> cases() async {
    await _wait();
    return List.of(_cases)..sort((a, b) => b.lastMessageAt.compareTo(a.lastMessageAt));
  }

  @override
  Future<SupportCase> caseDetail(String id) async {
    await _wait();
    final index = _cases.indexWhere((c) => c.id == id);
    if (index < 0) throw const SupportException('Caso no encontrado.');
    final opened = _copy(_cases[index], unread: false);
    _cases[index] = opened;
    return opened;
  }

  @override
  Future<SupportCase> createCase({
    required String topicKey,
    required Map<String, String> answers,
    required String description,
  }) async {
    await _wait();
    final topic = _topics.firstWhere((t) => t.key == topicKey);
    for (final field in topic.formFields) {
      if (field.required && (answers[field.key] ?? '').trim().isEmpty) {
        throw SupportException('Falta responder: ${field.label}');
      }
    }
    final now = _now();
    final number = _nextNumber++;
    final created = SupportCase(
      id: 'case-$number',
      number: number,
      topicKey: topic.key,
      topicTitle: topic.title,
      status: CaseStatus.waitingSupport,
      createdAt: now,
      lastMessageAt: now,
      authorName: 'Tú',
      answers: [
        for (final field in topic.formFields)
          if ((answers[field.key] ?? '').isNotEmpty) CaseAnswer(label: field.label, value: answers[field.key]!),
      ],
      messages: [
        CaseMessage(id: 'm-$number-1', fromSupport: false, authorName: 'Tú', body: description, createdAt: now),
      ],
    );
    _cases.add(created);
    return created;
  }

  @override
  Future<SupportCase> reply(String id, String body) async {
    await _wait();
    final index = _cases.indexWhere((c) => c.id == id);
    final current = _cases[index];
    final now = _now();
    final updated = _copy(
      current,
      status: CaseStatus.waitingSupport,
      lastMessageAt: now,
      messages: [
        ...current.messages,
        CaseMessage(id: 'm-${current.number}-${current.messages.length + 1}', fromSupport: false,
            authorName: 'Tú', body: body, createdAt: now),
      ],
    );
    _cases[index] = updated;
    return updated;
  }

  @override
  Future<SupportCase> resolve(String id) async {
    await _wait();
    final index = _cases.indexWhere((c) => c.id == id);
    _cases[index] = _copy(_cases[index], status: CaseStatus.resolved);
    return _cases[index];
  }

  @override
  Future<int> unreadCount() async {
    await _wait();
    return _cases.where((c) => c.unread && c.isMine).length;
  }

  /// Demo y tests: soporte responde un caso; queda sin leer para quien lo
  /// escribió, como en el servidor.
  void supportReplies(String id, String body, {String by = 'Soporte Nexus · Eduardo'}) {
    final index = _cases.indexWhere((c) => c.id == id);
    final current = _cases[index];
    final now = _now();
    _cases[index] = _copy(
      current,
      status: CaseStatus.answered,
      unread: true,
      lastMessageAt: now,
      messages: [
        ...current.messages,
        CaseMessage(id: 'm-${current.number}-${current.messages.length + 1}', fromSupport: true,
            authorName: by, body: body, createdAt: now),
      ],
    );
  }

  @override
  Future<String> createPublicCase({
    required String topicKey,
    required Map<String, String> answers,
    required String description,
    required String accountEmail,
    required String storeName,
    required String contactEmail,
    String? contactName,
  }) async {
    await _wait();
    publicCases.add({
      'topic_key': topicKey,
      ...answers,
      'description': description,
      'account_email': accountEmail,
      'store_name': storeName,
      'contact_email': contactEmail,
    });
    return kPublicCaseAccepted;
  }

  static SupportCase _copy(
    SupportCase c, {
    CaseStatus? status,
    bool? unread,
    DateTime? lastMessageAt,
    List<CaseMessage>? messages,
  }) =>
      SupportCase(
        id: c.id,
        number: c.number,
        topicKey: c.topicKey,
        topicTitle: c.topicTitle,
        status: status ?? c.status,
        createdAt: c.createdAt,
        lastMessageAt: lastMessageAt ?? c.lastMessageAt,
        unread: unread ?? c.unread,
        authorName: c.authorName,
        isMine: c.isMine,
        answers: c.answers,
        messages: messages ?? c.messages,
      );

  /// Los mismos temas que siembra la migración 0028 (resumidos).
  static const demoTopics = <HelpTopic>[
    HelpTopic(
      key: 'account_suspended',
      title: 'Mi cuenta está suspendida',
      summary: 'Por qué se suspende una cuenta y cómo se reactiva.',
      body: 'Una cuenta se suspende por una de dos razones, y la pantalla de suspensión te dice cuál:\n\n'
          '• Tu suscripción venció y terminaron los días de gracia.\n'
          '• Soporte Nexus la suspendió por un uso indebido.\n\n'
          'Mientras está suspendida no se borra nada.',
      actions: [TopicAction(label: 'Ver Mi suscripción', target: 'subscription')],
      formFields: [FormFieldSpec(key: 'since', label: '¿Desde cuándo está suspendida?', type: FormFieldType.text)],
    ),
    HelpTopic(
      key: 'something_broken',
      title: 'Algo no funciona',
      summary: 'Un error al vender, en el inventario, la caja u otra parte.',
      body: 'Antes de escribirnos, prueba esto:\n\n'
          '• Revisa que tengas internet.\n'
          '• Cierra la app por completo y vuelve a abrirla.\n\n'
          'Si sigue pasando, cuéntanos qué hacías y qué viste.',
      formFields: [
        FormFieldSpec(
          key: 'module',
          label: '¿En qué parte de la app?',
          type: FormFieldType.select,
          required: true,
          options: ['Ventas', 'Inventario', 'Caja', 'Compras', 'Catálogo web', 'Otra'],
        ),
        FormFieldSpec(key: 'when', label: '¿Cuándo pasó?', type: FormFieldType.text),
        FormFieldSpec(key: 'steps', label: '¿Qué estabas haciendo?', type: FormFieldType.textarea),
      ],
    ),
    HelpTopic(
      key: 'staff_access',
      title: 'Otro usuario de mi tienda no puede entrar',
      summary: 'Un empleado olvidó su contraseña o no puede iniciar sesión.',
      body: 'Quien administra la tienda puede ponerle una contraseña nueva a un empleado desde Usuarios y permisos.',
      actions: [TopicAction(label: 'Ir a Usuarios y permisos', target: 'manage_members')],
      formFields: [
        FormFieldSpec(key: 'who', label: '¿Quién no puede entrar? (nombre o correo)', type: FormFieldType.text, required: true),
      ],
    ),
    HelpTopic(
      key: 'other',
      title: 'Otra pregunta',
      summary: 'Cualquier otra cosa en la que te podamos ayudar.',
      body: 'Cuéntanos qué necesitas y te respondemos aquí mismo, en la app.',
    ),
    HelpTopic(
      key: 'cannot_login',
      title: 'No puedo entrar a mi cuenta',
      summary: 'No te llega el código o perdiste acceso a tu correo.',
      body: 'Si olvidaste tu contraseña, en la pantalla de acceso toca "¿Olvidaste tu contraseña?".\n\n'
          '• El código vence en 30 minutos: usa el más reciente.\n'
          '• Revisa también la carpeta de spam o promociones.\n\n'
          'Si aun así no puedes entrar, escríbenos.',
      actions: [TopicAction(label: 'Pedir un código', target: 'forgot_password')],
      formFields: [
        FormFieldSpec(
          key: 'problem',
          label: '¿Qué está pasando?',
          type: FormFieldType.select,
          required: true,
          options: ['No me llega el código', 'Perdí acceso a mi correo', 'Otra cosa'],
        ),
      ],
    ),
  ];
}
