import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/data/auth_repository.dart';
import '../../auth/presentation/login_provider.dart';
import '../data/management_repository.dart';
import '../data/management_repository_impl.dart';
import '../domain/app_permission.dart';
import '../domain/category.dart';
import '../domain/tenant_member.dart';
import '../domain/tenant_role.dart';
import '../domain/warehouse.dart';

// ---------------------------------------------------------------------------
// Repositorio
// ---------------------------------------------------------------------------

/// Personas y roles contra el backend real desde la Fase B (Sep 21, 2026,
/// decisión D6a de Eduardo): la tasa de comisión por empleado sólo tiene
/// sentido si se guarda en `users`. Almacenes, categorías y la edición de
/// permisos siguen en el mock (la Impl delega). `--dart-define=MANAGEMENT_MOCK=true`
/// vuelve al mock completo (tests y demos).
const bool kManagementUseMock =
    bool.fromEnvironment('MANAGEMENT_MOCK', defaultValue: false);

final managementRepositoryProvider = Provider<ManagementRepository>((ref) {
  final mock = ManagementRepositoryMock(
    currentEmail: ref.watch(currentUserNameProvider) ?? 'demo@nexus.mx',
  );
  if (kManagementUseMock) return mock;
  return ManagementRepositoryImpl(
    client: ref.watch(dioClientProvider),
    fallback: mock,
  );
});

// ---------------------------------------------------------------------------
// Quién soy
// ---------------------------------------------------------------------------

class CurrentMemberNotifier extends AsyncNotifier<TenantMember?> {
  @override
  Future<TenantMember?> build() async {
    if (!ref.watch(sessionProvider)) return null;
    return ref.watch(managementRepositoryProvider).getCurrentMember();
  }
}

final currentMemberProvider =
    AsyncNotifierProvider<CurrentMemberNotifier, TenantMember?>(
  CurrentMemberNotifier.new,
);

// ---------------------------------------------------------------------------
// Almacenes
// ---------------------------------------------------------------------------

class WarehousesNotifier extends AsyncNotifier<List<Warehouse>> {
  @override
  Future<List<Warehouse>> build() =>
      ref.watch(managementRepositoryProvider).listWarehouses();

  ManagementRepository get _repo => ref.read(managementRepositoryProvider);

  /// Las mutaciones dejan escapar la excepción a propósito: el modal muestra
  /// el mensaje del 422 tal cual lo arma el dominio, no uno inventado en la UI
  /// (mismo criterio que `deactivateSupplier`, decisión técnica #7 de U-07).
  Future<void> create(String name) async {
    await _repo.createWarehouse(name);
    await _reload();
  }

  Future<void> rename({required String id, required String name}) async {
    await _repo.updateWarehouse(id: id, name: name);
    await _reload();
  }

  Future<void> deactivate(String id) async {
    await _repo.deactivateWarehouse(id);
    await _reload();
  }

  Future<void> _reload() async {
    state = await AsyncValue.guard(_repo.listWarehouses);
  }
}

final warehousesProvider =
    AsyncNotifierProvider<WarehousesNotifier, List<Warehouse>>(
  WarehousesNotifier.new,
);

/// Sólo los almacenes en los que se puede operar hoy — es lo que alimenta el
/// selector de Perfil y (a futuro, W-01) el modal de traslados.
final activeWarehousesProvider = Provider<List<Warehouse>>((ref) {
  final all = ref.watch(warehousesProvider).valueOrNull ?? const <Warehouse>[];
  return all.where((w) => w.isActive).toList();
});

// ---------------------------------------------------------------------------
// Personas del comercio
// ---------------------------------------------------------------------------

class MembersNotifier extends AsyncNotifier<List<TenantMember>> {
  @override
  Future<List<TenantMember>> build() =>
      ref.watch(managementRepositoryProvider).listMembers();

  ManagementRepository get _repo => ref.read(managementRepositoryProvider);

  Future<void> create({
    required String name,
    required String email,
    required String roleId,
    required String password,
    CommissionType commissionType = CommissionType.percentageSale,
    double commissionRate = 0,
    String? defaultWarehouseId,
  }) async {
    await _repo.createMember(
      name: name,
      email: email,
      roleId: roleId,
      password: password,
      commissionType: commissionType,
      commissionRate: commissionRate,
      defaultWarehouseId: defaultWarehouseId,
    );
    await _reload();
  }

  Future<void> edit({
    required String id,
    String? name,
    String? email,
    String? roleId,
    CommissionType? commissionType,
    double? commissionRate,
    String? defaultWarehouseId,
  }) async {
    await _repo.updateMember(
      id: id,
      name: name,
      email: email,
      roleId: roleId,
      commissionType: commissionType,
      commissionRate: commissionRate,
      defaultWarehouseId: defaultWarehouseId,
    );
    await _reload();
    // Cambiarse el rol o el almacén a sí mismo repinta toda la sesión.
    ref.invalidate(currentMemberProvider);
  }

  Future<void> deactivate(String id) async {
    await _repo.deactivateMember(id);
    await _reload();
  }

  Future<void> _reload() async {
    state = await AsyncValue.guard(_repo.listMembers);
  }
}

final membersProvider =
    AsyncNotifierProvider<MembersNotifier, List<TenantMember>>(
  MembersNotifier.new,
);

// ---------------------------------------------------------------------------
// Categorías
// ---------------------------------------------------------------------------

class CategoriesNotifier extends AsyncNotifier<List<Category>> {
  @override
  Future<List<Category>> build() =>
      ref.watch(managementRepositoryProvider).listCategories();

  ManagementRepository get _repo => ref.read(managementRepositoryProvider);

  Future<void> create(String name) async {
    await _repo.createCategory(name);
    await _reload();
  }

  Future<void> rename({required String id, required String name}) async {
    await _repo.renameCategory(id: id, name: name);
    await _reload();
  }

  Future<void> remove(String id) async {
    await _repo.deleteCategory(id);
    await _reload();
  }

  Future<void> _reload() async {
    state = await AsyncValue.guard(_repo.listCategories);
  }
}

final categoriesProvider =
    AsyncNotifierProvider<CategoriesNotifier, List<Category>>(
  CategoriesNotifier.new,
);

// ---------------------------------------------------------------------------
// Roles y permisos
// ---------------------------------------------------------------------------

/// Sólo lectura: los cuatro roles globales con los permisos que manda el
/// servidor. Personalizarlos por comercio es la Fase B.
class RolesNotifier extends AsyncNotifier<List<TenantRole>> {
  @override
  Future<List<TenantRole>> build() =>
      ref.watch(managementRepositoryProvider).listRoles();
}

final rolesProvider = AsyncNotifierProvider<RolesNotifier, List<TenantRole>>(
  RolesNotifier.new,
);

final rolesByIdProvider = Provider<Map<String, TenantRole>>((ref) {
  final roles = ref.watch(rolesProvider).valueOrNull ?? const <TenantRole>[];
  return {for (final role in roles) role.id: role};
});

// ---------------------------------------------------------------------------
// Puertas de permiso
// ---------------------------------------------------------------------------

/// Permisos efectivos de quien está en sesión, tal como los manda
/// `GET /auth/me → role.permissions[].code` (OWNER → catálogo completo).
///
/// Vacío mientras carga o sin sesión: fail-closed. Nunca se ofrece una acción
/// para después negarla (mismo criterio que `isCorporativoPlanProvider`).
final myPermissionsProvider = Provider<Set<String>>((ref) {
  return ref.watch(currentMemberProvider).valueOrNull?.permissions ??
      const <String>{};
});

/// `true` cuando `/auth/me` ya respondió (con o sin permisos). El router
/// sólo rebota rutas con permisos conocidos; la UI, en cambio, es fail-closed
/// desde el primer frame.
final permissionsKnownProvider = Provider<bool>(
  (ref) => ref.watch(currentMemberProvider).valueOrNull != null,
);

/// El rol de quien está en sesión (para la etiqueta del perfil y del menú).
/// Los roles se observan **antes** de resolver quién soy, a propósito: así
/// las dos cargas van en paralelo y no en cascada.
final myRoleProvider = Provider<TenantRole?>((ref) {
  final rolesById = ref.watch(rolesByIdProvider);
  final member = ref.watch(currentMemberProvider).valueOrNull;
  if (member == null) return null;
  return rolesById[member.roleId];
});

final hasPermissionProvider = Provider.family<bool, String>(
  (ref, permission) => ref.watch(myPermissionsProvider).contains(permission),
);

/// Dueño del comercio. El servidor no le siembra permisos: los tiene todos
/// por definición, y hay cosas que sólo son suyas (suscripción, clonar).
/// Sale de `/auth/me` (`role.name`), no de la lista de roles: el router lo
/// consulta y no debe arrastrar una carga extra.
final isOwnerProvider = Provider<bool>(
  (ref) => ref.watch(currentMemberProvider).valueOrNull?.isOwner ?? false,
);

// Operación ------------------------------------------------------------------

final canCheckoutProvider = Provider<bool>(
  (ref) => ref.watch(hasPermissionProvider(Permissions.salesCheckout)),
);

final canViewSalesProvider = Provider<bool>(
  (ref) => ref.watch(hasPermissionProvider(Permissions.salesView)),
);

final canCancelSalesProvider = Provider<bool>(
  (ref) => ref.watch(hasPermissionProvider(Permissions.salesCancel)),
);

final canViewCashProvider = Provider<bool>(
  (ref) => ref.watch(hasPermissionProvider(Permissions.cashView)),
);

final canViewInventoryProvider = Provider<bool>(
  (ref) => ref.watch(hasPermissionProvider(Permissions.inventoryView)),
);

final canCreateInventoryProvider = Provider<bool>(
  (ref) => ref.watch(hasPermissionProvider(Permissions.inventoryCreate)),
);

final canEditPriceProvider = Provider<bool>(
  (ref) => ref.watch(hasPermissionProvider(Permissions.inventoryEditPrice)),
);

final canAdjustStockProvider = Provider<bool>(
  (ref) => ref.watch(hasPermissionProvider(Permissions.inventoryAdjustStock)),
);

final canViewPurchasesProvider = Provider<bool>(
  (ref) => ref.watch(hasPermissionProvider(Permissions.purchasesView)),
);

final canCreatePurchasesProvider = Provider<bool>(
  (ref) => ref.watch(hasPermissionProvider(Permissions.purchasesCreate)),
);

final canPayCreditProvider = Provider<bool>(
  (ref) => ref.watch(hasPermissionProvider(Permissions.purchasesPayCredit)),
);

// Administración -------------------------------------------------------------

final canSeeReportsProvider = Provider<bool>(
  (ref) => ref.watch(hasPermissionProvider(Permissions.reportsViewBasic)),
);

final canManageMembersProvider = Provider<bool>(
  (ref) => ref.watch(hasPermissionProvider(Permissions.settingsManageUsers)),
);

/// Preferencias operativas (almacenes, categorías, margen), catálogo web y
/// asignar el almacén donde opera cada quien (D15).
final canManageStoreProvider = Provider<bool>(
  (ref) => ref.watch(hasPermissionProvider(Permissions.settingsManageStore)),
);

/// La sección "Administración" del menú existe si hay algo que mostrar en ella.
final canOpenAdministrationProvider = Provider<bool>((ref) =>
    ref.watch(canSeeReportsProvider) ||
    ref.watch(canManageMembersProvider) ||
    ref.watch(canManageStoreProvider) ||
    ref.watch(isOwnerProvider));

// Pestañas del shell ---------------------------------------------------------

/// Ramas del `StatefulShellRoute`, en el orden en que están declaradas.
enum ShellTab { home, inventory, sales, purchases, cash }

/// Qué pestañas ve quien está en sesión. Inicio e Inventario siempre (todo
/// rol tiene `inventory.view`); las demás por permiso. Mientras carga sólo
/// quedan esas dos: fail-closed, nunca una pestaña que luego se esconda.
final visibleTabsProvider = Provider<List<ShellTab>>((ref) => [
      ShellTab.home,
      ShellTab.inventory,
      if (ref.watch(canCheckoutProvider)) ShellTab.sales,
      if (ref.watch(canViewPurchasesProvider)) ShellTab.purchases,
      if (ref.watch(canViewCashProvider)) ShellTab.cash,
    ]);
