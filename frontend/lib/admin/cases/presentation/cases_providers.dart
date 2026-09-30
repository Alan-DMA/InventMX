import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/browser/session_store.dart';
import '../../session/admin_session.dart';
import '../data/cases_repository.dart';
import '../domain/desk_case.dart';

/// Pestaña de la cola (Esperando / Respondidos / Resueltos).
final casesTabProvider = StateProvider<DeskCaseStatus>((_) => DeskCaseStatus.waiting);

/// Búsqueda: número, correo, tienda o tema.
final casesQueryProvider = StateProvider<String>((_) => '');

/// Cuántos casos esperan respuesta: el contador de "Casos" en la navegación.
/// Sólo cuenta lo que espera (Attention Bait, P33). Tras un fallo de red se
/// conserva el último número conocido (`valueOrNull`).
final waitingCountProvider = FutureProvider<int>((ref) async {
  if (!ref.watch(adminSessionProvider.select((s) => s.signedIn))) return 0;
  return ref.watch(casesRepositoryProvider).waitingCount();
});

/// El caso que más lleva esperando (el hilo vacío lo señala).
final oldestWaitingProvider = FutureProvider<DeskCase?>((ref) async {
  ref.watch(waitingCountProvider);
  final page = await ref.watch(casesRepositoryProvider).list(status: DeskCaseStatus.waiting, limit: 1);
  return page.items.isEmpty ? null : page.items.first;
});

class CaseListState {
  const CaseListState({required this.items, required this.total, this.loadingMore = false, this.moreError});

  final List<DeskCase> items;
  final int total;
  final bool loadingMore;
  final String? moreError;

  bool get hasMore => items.length < total;

  CaseListState copyWith({List<DeskCase>? items, int? total, bool? loadingMore, String? moreError}) => CaseListState(
        items: items ?? this.items,
        total: total ?? this.total,
        loadingMore: loadingMore ?? this.loadingMore,
        moreError: moreError,
      );
}

/// La cola de la pestaña y búsqueda actuales, por páginas ("Cargar más").
class CaseListNotifier extends AsyncNotifier<CaseListState> {
  static const pageSize = 30;

  CasesRepository get _repo => ref.read(casesRepositoryProvider);

  @override
  Future<CaseListState> build() async {
    // Otra sesión (u otro operador) empieza de cero
    ref.watch(adminSessionProvider.select((s) => s.session?.token));
    final status = ref.watch(casesTabProvider);
    final query = ref.watch(casesQueryProvider);
    final page = await _repo.list(status: status, query: query, limit: pageSize);
    return CaseListState(items: page.items, total: page.total);
  }

  Future<void> loadMore() async {
    final current = state.valueOrNull;
    if (current == null || current.loadingMore || !current.hasMore) return;
    state = AsyncData(current.copyWith(loadingMore: true));
    try {
      final page = await _repo.list(
        status: ref.read(casesTabProvider),
        query: ref.read(casesQueryProvider),
        limit: pageSize,
        offset: current.items.length,
      );
      state = AsyncData(CaseListState(items: [...current.items, ...page.items], total: page.total));
    } catch (e) {
      state = AsyncData(current.copyWith(loadingMore: false, moreError: e.toString()));
    }
  }

  /// Cada 60 s y tras responder: vuelve a pedir lo que ya se ve, sin pasar por
  /// "cargando" y sin perder lo mostrado si falla la red.
  Future<void> refreshSilently() async {
    final current = state.valueOrNull;
    if (current == null) return;
    try {
      final page = await _repo.list(
        status: ref.read(casesTabProvider),
        query: ref.read(casesQueryProvider),
        limit: current.items.length.clamp(pageSize, 200),
      );
      state = AsyncData(CaseListState(items: page.items, total: page.total));
    } catch (_) {}
  }
}

final caseListProvider = AsyncNotifierProvider<CaseListNotifier, CaseListState>(CaseListNotifier.new);

/// El hilo abierto. `pending` = llegó algo nuevo mientras se leía: se ofrece
/// "Actualizar" en vez de cambiar el hilo bajo los dedos (P33).
class CaseThread {
  const CaseThread({required this.detail, this.pending});
  final DeskCaseDetail detail;
  final DeskCaseDetail? pending;
}

class CaseThreadNotifier extends AutoDisposeFamilyAsyncNotifier<CaseThread, String> {
  CasesRepository get _repo => ref.read(casesRepositoryProvider);

  @override
  Future<CaseThread> build(String id) async => CaseThread(detail: await _repo.detail(id));

  Future<void> reply(String body, {required bool resolve}) async {
    final detail = await _repo.reply(arg, body, resolve: resolve);
    state = AsyncData(CaseThread(detail: detail));
  }

  Future<void> setStatus(DeskCaseStatus status) async {
    final detail = await _repo.setStatus(arg, status);
    state = AsyncData(CaseThread(detail: detail));
  }

  /// Pide el caso en segundo plano; si hay mensajes nuevos, los deja en espera.
  Future<void> checkForNews() async {
    final current = state.valueOrNull;
    if (current == null) return;
    try {
      final fresh = await _repo.detail(arg);
      if (fresh.messages.length != current.detail.messages.length ||
          fresh.summary.lastMessageAt.isAfter(current.detail.summary.lastMessageAt)) {
        state = AsyncData(CaseThread(detail: current.detail, pending: fresh));
      }
    } catch (_) {}
  }

  void applyPending() {
    final current = state.valueOrNull;
    if (current?.pending == null) return;
    state = AsyncData(CaseThread(detail: current!.pending!));
  }
}

final caseThreadProvider =
    AsyncNotifierProvider.autoDispose.family<CaseThreadNotifier, CaseThread, String>(CaseThreadNotifier.new);

/// Borradores de respuesta por caso, en la pestaña: sobreviven a F5 y al
/// vencimiento de la sesión (P34); se borran al enviar.
class CaseDrafts {
  CaseDrafts(this._store);
  final SessionStore _store;

  static String _key(String caseId) => 'nexus.admin.draft.$caseId';

  String read(String caseId) => _store.read(_key(caseId)) ?? '';

  void write(String caseId, String text) =>
      text.trim().isEmpty ? _store.remove(_key(caseId)) : _store.write(_key(caseId), text);

  void clear(String caseId) => _store.remove(_key(caseId));
}

final caseDraftsProvider = Provider<CaseDrafts>((ref) => CaseDrafts(ref.watch(sessionStoreProvider)));
