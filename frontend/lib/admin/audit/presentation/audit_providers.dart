import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../session/admin_session.dart';
import '../data/audit_repository.dart';
import '../domain/audit_models.dart';

/// Filtros de la bitácora.
class AuditFilter {
  const AuditFilter({this.action, this.tenantId, this.tenantName, this.onlyMine = false, this.showNoise = false});

  final String? action;
  final String? tenantId;
  final String? tenantName;
  final bool onlyMine;

  /// Aperturas de ficha y accesos al panel (apagado por omisión: es el ruido
  /// que el feed ya quita).
  final bool showNoise;

  bool get isFiltered => action != null || tenantId != null || onlyMine;

  AuditFilter copyWith({
    String? action,
    bool clearAction = false,
    String? tenantId,
    String? tenantName,
    bool clearTenant = false,
    bool? onlyMine,
    bool? showNoise,
  }) =>
      AuditFilter(
        action: clearAction ? null : action ?? this.action,
        tenantId: clearTenant ? null : tenantId ?? this.tenantId,
        tenantName: clearTenant ? null : tenantName ?? this.tenantName,
        onlyMine: onlyMine ?? this.onlyMine,
        showNoise: showNoise ?? this.showNoise,
      );
}

final auditFilterProvider = StateProvider<AuditFilter>((_) => const AuditFilter());

class AuditListState {
  const AuditListState({required this.items, required this.total, this.loadingMore = false, this.moreError});
  final List<AuditEntry> items;
  final int total;
  final bool loadingMore;
  final String? moreError;

  bool get hasMore => items.length < total;
}

class AuditListNotifier extends AutoDisposeAsyncNotifier<AuditListState> {
  static const pageSize = 50;

  AuditRepository get _repo => ref.read(auditRepositoryProvider);

  Future<AuditPage> _page(AuditFilter f, int offset) => _repo.list(
        action: f.action,
        tenantId: f.tenantId,
        operatorId: f.onlyMine ? ref.read(adminSessionProvider).session?.operatorId : null,
        excludeNoise: !f.showNoise,
        limit: pageSize,
        offset: offset,
      );

  @override
  Future<AuditListState> build() async {
    final page = await _page(ref.watch(auditFilterProvider), 0);
    return AuditListState(items: page.items, total: page.total);
  }

  Future<void> loadMore() async {
    final current = state.valueOrNull;
    if (current == null || current.loadingMore || !current.hasMore) return;
    state = AsyncData(AuditListState(items: current.items, total: current.total, loadingMore: true));
    try {
      final page = await _page(ref.read(auditFilterProvider), current.items.length);
      state = AsyncData(AuditListState(items: [...current.items, ...page.items], total: page.total));
    } catch (e) {
      state = AsyncData(AuditListState(items: current.items, total: current.total, moreError: e.toString()));
    }
  }
}

final auditListProvider = AsyncNotifierProvider.autoDispose<AuditListNotifier, AuditListState>(AuditListNotifier.new);

/// Estado de la verificación de la cadena. Vive toda la sesión: si la cadena
/// está rota, el armazón muestra la alerta roja fija en todas las secciones.
sealed class ChainState {
  const ChainState();
}

class ChainUnknown extends ChainState {
  const ChainUnknown();
}

class ChainChecking extends ChainState {
  const ChainChecking();
}

class ChainIntact extends ChainState {
  const ChainIntact(this.checked);
  final int checked;
}

class ChainBroken extends ChainState {
  const ChainBroken(this.brokenAtId, this.checked);
  final int? brokenAtId;
  final int checked;
}

/// No se pudo verificar (red): no es lo mismo que una cadena rota.
class ChainCheckFailed extends ChainState {
  const ChainCheckFailed(this.message);
  final String message;
}

class ChainNotifier extends Notifier<ChainState> {
  @override
  ChainState build() {
    ref.watch(adminSessionProvider.select((s) => s.session?.token));
    return const ChainUnknown();
  }

  Future<void> verify() async {
    if (state is ChainChecking) return;
    state = const ChainChecking();
    try {
      final result = await ref.read(auditRepositoryProvider).verify();
      state = result.intact ? ChainIntact(result.checked) : ChainBroken(result.brokenAtId, result.checked);
    } catch (e) {
      state = ChainCheckFailed(e.toString());
    }
  }
}

final chainProvider = NotifierProvider<ChainNotifier, ChainState>(ChainNotifier.new);
