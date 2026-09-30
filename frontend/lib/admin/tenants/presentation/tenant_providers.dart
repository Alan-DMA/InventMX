import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../cases/data/cases_repository.dart';
import '../../cases/domain/desk_case.dart';
import '../../router/admin_routes.dart';
import '../data/tenants_repository.dart';
import '../domain/tenant_models.dart';

/// La ficha abierta. Cada apertura queda en la bitácora (decisión 3 de la
/// Fase 1); por eso no se refresca sola.
final tenantDetailProvider = FutureProvider.autoDispose.family<TenantDetail, String>(
  (ref, id) => ref.watch(tenantsRepositoryProvider).detail(id),
);

/// Los casos de esa tienda, para la ficha.
final tenantCasesProvider = FutureProvider.autoDispose.family<List<DeskCase>, String>(
  (ref, id) => ref.watch(casesRepositoryProvider).forTenant(id),
);

/// Abre la ficha de una tienda sobre la sección actual (`?tienda=<id>`).
void openStore(BuildContext context, String tenantId) =>
    context.go(AdminRoutes.withStore(GoRouterState.of(context).uri, tenantId));
