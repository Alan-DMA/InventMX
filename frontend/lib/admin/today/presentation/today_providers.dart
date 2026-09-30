import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../session/admin_session.dart';
import '../data/today_repository.dart';
import '../domain/today_models.dart';

/// Medianoche local de hace `daysBack` días (constructor de fecha: respeta los
/// cambios de horario, a diferencia de restar horas).
DateTime localDayStart(DateTime t, {int daysBack = 0}) => DateTime(t.year, t.month, t.day - daysBack);

class FeedState {
  const FeedState({
    required this.attention,
    required this.events,
    required this.since,
    this.loadingEarlier = false,
    this.earlierError,
    this.lastEmptyRange,
  });

  final List<AttentionItem> attention;

  /// Lo más reciente primero.
  final List<FeedEvent> events;

  /// Desde dónde está cargado (medianoche local).
  final DateTime since;
  final bool loadingEarlier;
  final String? earlierError;

  /// "Ver días anteriores" trajo un rango sin movimientos: se dice.
  final (DateTime, DateTime)? lastEmptyRange;

  FeedState copyWith({
    List<AttentionItem>? attention,
    List<FeedEvent>? events,
    DateTime? since,
    bool? loadingEarlier,
    String? earlierError,
    (DateTime, DateTime)? lastEmptyRange,
  }) =>
      FeedState(
        attention: attention ?? this.attention,
        events: events ?? this.events,
        since: since ?? this.since,
        loadingEarlier: loadingEarlier ?? this.loadingEarlier,
        earlierError: earlierError,
        lastEmptyRange: lastEmptyRange ?? this.lastEmptyRange,
      );
}

/// Requiere atención + lo que pasó. El servidor no decide dónde empieza un
/// día (S-12): aquí se piden días completos en la hora del equipo — hoy y los
/// dos anteriores — y "Ver días anteriores" pide exactamente los 3 previos.
class FeedNotifier extends AsyncNotifier<FeedState> {
  static const daysPerPage = 3;

  TodayRepository get _repo => ref.read(todayRepositoryProvider);
  DateTime _now() => ref.read(adminClockProvider)();

  @override
  Future<FeedState> build() async {
    ref.watch(adminSessionProvider.select((s) => s.session?.token));
    final now = _now();
    final since = localDayStart(now, daysBack: daysPerPage - 1);
    final page = await _repo.feed(since: since, until: now);
    return FeedState(attention: page.attention, events: _sorted(page.events), since: since);
  }

  static List<FeedEvent> _sorted(List<FeedEvent> events) =>
      [...events]..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));

  Future<void> loadEarlier() async {
    final current = state.valueOrNull;
    if (current == null || current.loadingEarlier) return;
    state = AsyncData(current.copyWith(loadingEarlier: true));
    final until = current.since;
    final since = localDayStart(until, daysBack: daysPerPage);
    try {
      final page = await _repo.feed(since: since, until: until);
      state = AsyncData(current.copyWith(
        events: _sorted([...current.events, ...page.events]),
        since: since,
        loadingEarlier: false,
        lastEmptyRange: page.events.isEmpty ? (since, until) : null,
      ));
    } catch (e) {
      state = AsyncData(current.copyWith(loadingEarlier: false, earlierError: e.toString()));
    }
  }

  /// Cada 60 s (P33): vuelve a pedir lo que ya se ve, sin "cargando" y sin
  /// perder lo mostrado si falla la red.
  Future<void> refreshSilently() async {
    final current = state.valueOrNull;
    if (current == null) return;
    try {
      final page = await _repo.feed(since: current.since, until: _now());
      state = AsyncData(current.copyWith(attention: page.attention, events: _sorted(page.events)));
    } catch (_) {}
  }
}

final feedProvider = AsyncNotifierProvider<FeedNotifier, FeedState>(FeedNotifier.new);

final metricsProvider = FutureProvider<PlatformMetrics>((ref) async {
  ref.watch(adminSessionProvider.select((s) => s.session?.token));
  return ref.watch(todayRepositoryProvider).metrics();
});
