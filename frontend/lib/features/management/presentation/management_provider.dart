import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/login_provider.dart';
import '../data/management_repository.dart';
import '../domain/app_permission.dart';
import '../domain/category.dart';
import '../domain/tenant_member.dart';
import '../domain/tenant_role.dart';
import '../domain/warehouse.dart';

// ---------------------------------------------------------------------------
// Repositorio
// ---------------------------------------------------------------------------

/// 100% mock por decisión de Eduardo (Sep 2026): esta pasada no se conecta a
/// backend real, ni siquiera a `GET /inventory/warehouses` que ya existe en el
/// legacy — así Almacenes, Usuarios y Permisos se comportan igual entre sí en
/// vez de mezclar una sección real con dos simuladas.
final managementRepositoryProvider = Provider<ManagementRepository>((ref) {
  return ManagementRepositoryMock(
    currentEmail: ref.watch(currentUserNameProvider) ?? 'demo@nexus.mx',
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
  }) async {
    await _repo.createMember(name: name, email: email, roleId: roleId);
    await _reload();
  }

  Future<void> edit({
    required String id,
    String? name,
    String? email,
    String? roleId,
  }) async {
    await _repo.updateMember(id: id, name: name, email: email, roleId: roleId);
    await _reload();
    // Cambiarse el rol a sí mismo repinta los permisos de toda la sesión.
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

class RolesNotifier extends AsyncNotifier<List<TenantRole>> {
  @override
  Future<List<TenantRole>> build() =>
      ref.watch(managementRepositoryProvider).listRoles();

  ManagementRepository get _repo => ref.read(managementRepositoryProvider);

  Future<void> setPermissions({
    required String roleId,
    required Set<String> permissions,
  }) async {
    await _repo.updateRolePermissions(roleId: roleId, permissions: permissions);
    state = await AsyncValue.guard(_repo.listRoles);
  }

  /// Prende o apaga un permiso suelto de la matriz.
  Future<void> toggle({
    required TenantRole role,
    required String permission,
    required bool granted,
  }) {
    final next = Set.of(role.permissions);
    if (granted) {
      next.add(permission);
    } else {
      next.remove(permission);
    }
    return setPermissions(roleId: role.id, permissions: next);
  }
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

/// Permisos efectivos de quien está en sesión = los de su rol.
///
/// Vacío mientras carga o sin sesión: fail-closed. Nunca se ofrece una acción
/// para después negarla (mismo criterio que `isCorporativoPlanProvider`).
final myPermissionsProvider = Provider<Set<String>>((ref) {
  return ref.watch(myRoleProvider)?.permissions ?? const <String>{};
});

/// Los roles se observan **antes** de resolver quién soy, a propósito: si se
/// leyeran después de `currentMember` la carga sería en cascada (una espera
/// tras otra) en vez de en paralelo.
final myRoleProvider = Provider<TenantRole?>((ref) {
  final rolesById = ref.watch(rolesByIdProvider);
  final member = ref.watch(currentMemberProvider).valueOrNull;
  if (member == null) return null;
  return rolesById[member.roleId];
});

final hasPermissionProvider = Provider.family<bool, String>(
  (ref, permission) => ref.watch(myPermissionsProvider).contains(permission),
);

/// Decisión técnica #11: el almacén operativo se cambia por **permiso**, no
/// por un cheque fijo "solo dueño".
final canManageWarehousesProvider = Provider<bool>(
  (ref) => ref
      .watch(hasPermissionProvider(Permissions.inventarioGestionarAlmacenes)),
);

final canManageMembersProvider = Provider<bool>(
  (ref) => ref.watch(hasPermissionProvider(Permissions.usuariosGestionar)),
);

/// Entrada al hub de Gestión: basta con poder administrar algo.
final canOpenManagementProvider = Provider<bool>((ref) =>
    ref.watch(canManageWarehousesProvider) ||
    ref.watch(canManageMembersProvider));
