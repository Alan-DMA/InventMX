import 'package:nexus_app/admin/cases/data/cases_repository.dart';
import 'package:nexus_app/admin/cases/domain/desk_case.dart';
import 'package:nexus_app/admin/core/admin_http.dart';

import 'admin_harness.dart';

/// Mesa de casos en memoria, con el orden del backend: Esperando del más
/// antiguo al más reciente; lo demás, lo reciente primero.
class FakeCases implements CasesRepository {
  FakeCases(this.clock);

  final TestClock clock;
  final Map<String, DeskCaseDetail> _cases = {};
  bool failList = false;
  bool failNextReply = false;
  int replies = 0;

  /// Agrega un caso que escribió alguien de la tienda hace `hoursAgo`.
  void add({
    required String id,
    required int number,
    required int hoursAgo,
    String store = 'Abarrotes Luz',
    String topic = 'Algo no funciona',
    String body = 'El corte de caja no cuadra.',
    DeskCaseStatus status = DeskCaseStatus.waiting,
    bool fromApp = true,
    String lockReason = '',
    String storeStatus = 'ACTIVE',
  }) {
    final at = clock.now.subtract(Duration(hours: hoursAgo));
    final summary = DeskCase(
      id: id,
      number: number,
      fromApp: fromApp,
      tenantId: fromApp ? 't-$id' : null,
      tenantName: fromApp ? store : null,
      claimedStoreName: fromApp ? null : store,
      suggestedTenantName: fromApp ? null : store,
      topicTitle: topic,
      status: status,
      contactEmail: 'sol@tiendita.mx',
      contactName: 'Doña Sol',
      createdAt: at,
      lastMessageAt: at,
      lastMessagePreview: body,
      lastMessageBySupport: false,
    );
    _cases[id] = DeskCaseDetail(
      summary: summary,
      answers: const [DeskAnswer(label: '¿En qué parte de la app?', value: 'Caja')],
      messages: [DeskMessage(id: '$id-m1', fromSupport: false, authorName: 'Doña Sol', body: body, createdAt: at)],
      store: DeskStore(
        tenantId: 't-$id',
        name: store,
        status: storeStatus,
        plan: 'COMERCIO',
        paidUntil: DateTime(2026, 10, 27),
        lockReason: lockReason.isEmpty ? null : lockReason,
        suggested: !fromApp,
      ),
    );
  }

  /// El tendero vuelve a escribir (el caso regresa a "Esperando").
  void requesterWrites(String id, String body) {
    final d = _cases[id]!;
    final now = clock.now;
    _cases[id] = _with(d, status: DeskCaseStatus.waiting, at: now, preview: body, bySupport: false, messages: [
      ...d.messages,
      DeskMessage(
          id: '$id-m${d.messages.length + 1}', fromSupport: false, authorName: 'Doña Sol', body: body, createdAt: now)
    ]);
  }

  DeskCaseStatus statusOf(String id) => _cases[id]!.summary.status;

  DeskCaseDetail _with(
    DeskCaseDetail d, {
    DeskCaseStatus? status,
    DateTime? at,
    String? preview,
    bool? bySupport,
    List<DeskMessage>? messages,
  }) {
    final s = d.summary;
    return DeskCaseDetail(
      summary: DeskCase(
        id: s.id,
        number: s.number,
        fromApp: s.fromApp,
        tenantId: s.tenantId,
        tenantName: s.tenantName,
        claimedStoreName: s.claimedStoreName,
        suggestedTenantName: s.suggestedTenantName,
        topicTitle: s.topicTitle,
        status: status ?? s.status,
        contactEmail: s.contactEmail,
        contactName: s.contactName,
        createdAt: s.createdAt,
        lastMessageAt: at ?? s.lastMessageAt,
        lastMessagePreview: preview ?? s.lastMessagePreview,
        lastMessageBySupport: bySupport ?? s.lastMessageBySupport,
      ),
      answers: d.answers,
      messages: messages ?? d.messages,
      store: d.store,
    );
  }

  @override
  Future<DeskCasePage> list({required DeskCaseStatus status, String? query, int limit = 30, int offset = 0}) async {
    if (failList) throw const AdminApiException('Sin conexión con el servidor. Revisa tu red y vuelve a intentar.');
    final q = (query ?? '').trim().toLowerCase();
    final all = _cases.values
        .map((d) => d.summary)
        .where((c) => c.status == status)
        .where((c) =>
            q.isEmpty ||
            '${c.number}' == q ||
            c.storeLabel.toLowerCase().contains(q) ||
            c.topicTitle.toLowerCase().contains(q))
        .toList()
      ..sort((a, b) => status == DeskCaseStatus.waiting
          ? a.lastMessageAt.compareTo(b.lastMessageAt)
          : b.lastMessageAt.compareTo(a.lastMessageAt));
    return DeskCasePage(items: all.skip(offset).take(limit).toList(), total: all.length);
  }

  @override
  Future<int> waitingCount() async => (await list(status: DeskCaseStatus.waiting, limit: 1)).total;

  @override
  Future<List<DeskCase>> forTenant(String tenantId, {int limit = 10}) async =>
      _cases.values.map((d) => d.summary).where((c) => c.tenantId == tenantId).take(limit).toList();

  @override
  Future<DeskCaseDetail> detail(String id) async {
    final d = _cases[id];
    if (d == null) throw const AdminApiException('Caso no encontrado.', statusCode: 404);
    return d;
  }

  @override
  Future<DeskCaseDetail> reply(String id, String body, {bool resolve = false}) async {
    if (failNextReply) {
      failNextReply = false;
      throw const AdminApiException('Sin conexión con el servidor. Revisa tu red y vuelve a intentar.');
    }
    replies++;
    final d = _cases[id]!;
    final now = clock.now;
    _cases[id] = _with(d,
        status: resolve ? DeskCaseStatus.resolved : DeskCaseStatus.answered,
        at: now,
        preview: body,
        bySupport: true,
        messages: [
          ...d.messages,
          DeskMessage(
              id: '$id-r$replies',
              fromSupport: true,
              authorName: 'Soporte Nexus · Eduardo Cristancho',
              body: body,
              createdAt: now),
        ]);
    return _cases[id]!;
  }

  @override
  Future<DeskCaseDetail> setStatus(String id, DeskCaseStatus status) async {
    _cases[id] = _with(_cases[id]!, status: status);
    return _cases[id]!;
  }
}
