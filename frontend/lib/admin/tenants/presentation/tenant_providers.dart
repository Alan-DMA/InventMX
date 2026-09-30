import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../cases/data/cases_repository.dart';
import '../../cases/domain/desk_case.dart';
import '../../router/admin_routes.dart';
import '../data/tenants_repository.dart';
import '../domain/tenant_models.dart';

/// La ficha abierta. Cada apertura queda en la bitácora (decisión 3 de la
/// Fase 1): no se refresca sola, y tras una acción se actualiza en el lugar
/// (`replace` / `patchSupport`) en vez de volver a pedirla.
class TenantDetailNotifier extends AutoDisposeFamilyAsyncNotifier<TenantDetail, String> {
  @override
  Future<TenantDetail> build(String id) => ref.watch(tenantsRepositoryProvider).detail(id);

  void replace(TenantDetail detail) => state = AsyncData(detail);

  void patchSupport(SupportState Function(SupportState current) change) {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncData(current.withSupport(change(current.support)));
  }
}

final tenantDetailProvider =
    AsyncNotifierProvider.autoDispose.family<TenantDetailNotifier, TenantDetail, String>(TenantDetailNotifier.new);

/// Los casos de esa tienda, para la ficha.
final tenantCasesProvider = FutureProvider.autoDispose.family<List<DeskCase>, String>(
  (ref, id) => ref.watch(casesRepositoryProvider).forTenant(id),
);

/// Abre la ficha de una tienda sobre la sección actual (`?tienda=<id>`).
void openStore(BuildContext context, String tenantId) =>
    context.go(AdminRoutes.withStore(GoRouterState.of(context).uri, tenantId));
