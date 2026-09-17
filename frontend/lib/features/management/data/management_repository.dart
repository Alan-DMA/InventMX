import '../domain/app_permission.dart';
import '../domain/category.dart';
import '../domain/tenant_member.dart';
import '../domain/tenant_role.dart';
import '../domain/warehouse.dart';

// ---------------------------------------------------------------------------
// Contrato
// ---------------------------------------------------------------------------

/// Administración del propio comercio: almacenes, personas y permisos.
///
/// Es scope de **un solo tenant** — nada que ver con el panel de fundadores
/// (`saas.manage`, Tarea 14.2), que administra la plataforma entera.
///
/// Estado del backend (verificado Sep 2026): el legacy sólo expone
/// `GET /api/v1/inventory/warehouses`. No existen alta/edición/baja de
/// almacenes, ni CRUD de usuarios del tenant, ni edición de permisos por rol.
/// Por eso todo corre contra [ManagementRepositoryMock] — cuando Alan los
/// entregue cambia el repositorio, no la UI.
abstract class ManagementRepository {
  /// Quién está usando la app ahora mismo.
  Future<TenantMember> getCurrentMember();

  // ── Almacenes ──────────────────────────────────────────────────────────
  /// GET /inventory/warehouses
  Future<List<Warehouse>> listWarehouses();

  /// POST /inventory/warehouses (pendiente de Alan)
  Future<Warehouse> createWarehouse(String name);

  /// PUT /inventory/warehouses/{id} (pendiente de Alan)
  Future<Warehouse> updateWarehouse({required String id, required String name});

  /// DELETE /inventory/warehouses/{id} — baja lógica (pendiente de Alan).
  Future<void> deactivateWarehouse(String id);

  // ── Personas del comercio ──────────────────────────────────────────────
  Future<List<TenantMember>> listMembers();

  Future<TenantMember> createMember({
    required String name,
    required String email,
    required String roleId,
  });

  Future<TenantMember> updateMember({
    required String id,
    String? name,
    String? email,
    String? roleId,
  });

  Future<void> deactivateMember(String id);

  // ── Categorías ─────────────────────────────────────────────────────────
  /// GET /inventory/categories (pendiente de Alan; hoy las categorías sólo
  /// existen como texto dentro de cada producto)
  Future<List<Category>> listCategories();

  Future<Category> createCategory(String name);

  Future<Category> renameCategory({required String id, required String name});

  /// Rechaza con [CategoryInUseException] si tiene productos.
  Future<void> deleteCategory(String id);

  // ── Roles y permisos ───────────────────────────────────────────────────
  Future<List<TenantRole>> listRoles();

  Future<TenantRole> updateRolePermissions({
    required String roleId,
    required Set<String> permissions,
  });
}

// ---------------------------------------------------------------------------
// Mock — única fuente de verdad mientras el backend no exponga estos módulos
// ---------------------------------------------------------------------------

class ManagementRepositoryMock implements ManagementRepository {
  ManagementRepositoryMock({this.currentEmail = 'demo@nexus.mx'});

  /// Correo de la sesión — el usuario en sesión es el Dueño de la semilla,
  /// igual que hace `SaasRepositoryMock` con el perfil de facturación.
  final String currentEmail;

  static const _fakeDelay = Duration(milliseconds: 400);

  static int _warehouseCounter = 0;
  static int _memberCounter = 0;
  static int _categoryCounter = 0;

  late final List<Warehouse> _warehouses = _seedWarehouses();
  late final List<TenantMember> _members = _seedMembers();
  late final List<TenantRole> _roles = _seedRoles();
  late final List<Category> _categories = _seedCategories();

  // ── Sesión ─────────────────────────────────────────────────────────────

  @override
  Future<TenantMember> getCurrentMember() async {
    await Future.delayed(_fakeDelay);
    return _members.firstWhere(
      (m) => m.email == currentEmail,
      orElse: () => _members.first,
    );
  }

  // ── Almacenes ──────────────────────────────────────────────────────────

  @override
  Future<List<Warehouse>> listWarehouses() async {
    await Future.delayed(_fakeDelay);
    return List.unmodifiable(_warehouses);
  }

  @override
  Future<Warehouse> createWarehouse(String name) async {
    await Future.delayed(_fakeDelay);
    final clean = name.trim();
    _assertWarehouseNameFree(clean, exceptId: null);

    final warehouse = Warehouse(
      id: 'wh-${(++_warehouseCounter).toString().padLeft(3, '0')}-new',
      name: clean,
      isActive: true,
      createdAt: DateTime.now(),
    );
    _warehouses.add(warehouse);
    return warehouse;
  }

  @override
  Future<Warehouse> updateWarehouse({
    required String id,
    required String name,
  }) async {
    await Future.delayed(_fakeDelay);
    final clean = name.trim();
    _assertWarehouseNameFree(clean, exceptId: id);

    final index = _warehouses.indexWhere((w) => w.id == id);
    if (index < 0) throw Exception('Almacén no encontrado: $id');
    final updated = _warehouses[index].copyWith(name: clean);
    _warehouses[index] = updated;
    return updated;
  }

  @override
  Future<void> deactivateWarehouse(String id) async {
    await Future.delayed(_fakeDelay);
    final activos = _warehouses.where((w) => w.isActive).toList();
    if (activos.length <= 1 && activos.any((w) => w.id == id)) {
      throw const LastWarehouseException();
    }
    final index = _warehouses.indexWhere((w) => w.id == id);
    if (index < 0) throw Exception('Almacén no encontrado: $id');
    _warehouses[index] = _warehouses[index].copyWith(isActive: false);
  }

  void _assertWarehouseNameFree(String name, {required String? exceptId}) {
    final taken = _warehouses.any(
        (w) => w.id != exceptId && w.name.toLowerCase() == name.toLowerCase());
    if (taken) throw DuplicateWarehouseNameException(name);
  }

  // ── Personas ───────────────────────────────────────────────────────────

  @override
  Future<List<TenantMember>> listMembers() async {
    await Future.delayed(_fakeDelay);
    return List.unmodifiable(_members);
  }

  @override
  Future<TenantMember> createMember({
    required String name,
    required String email,
    required String roleId,
  }) async {
    await Future.delayed(_fakeDelay);
    final cleanEmail = email.trim().toLowerCase();
    _assertEmailFree(cleanEmail, exceptId: null);

    final member = TenantMember(
      id: 'usr-${(++_memberCounter).toString().padLeft(3, '0')}-new',
      name: name.trim(),
      email: cleanEmail,
      roleId: roleId,
      isActive: true,
      createdAt: DateTime.now(),
    );
    _members.add(member);
    return member;
  }

  @override
  Future<TenantMember> updateMember({
    required String id,
    String? name,
    String? email,
    String? roleId,
  }) async {
    await Future.delayed(_fakeDelay);
    final index = _members.indexWhere((m) => m.id == id);
    if (index < 0) throw Exception('Usuario no encontrado: $id');
    final current = _members[index];

    final cleanEmail = email?.trim().toLowerCase();
    if (cleanEmail != null) _assertEmailFree(cleanEmail, exceptId: id);

    // Degradar al último Dueño activo dejaría el comercio sin quien administre.
    if (roleId != null && roleId != TenantRoles.owner) {
      _assertNotLastOwner(current);
    }

    final updated = current.copyWith(
      name: name?.trim(),
      email: cleanEmail,
      roleId: roleId,
    );
    _members[index] = updated;
    return updated;
  }

  @override
  Future<void> deactivateMember(String id) async {
    await Future.delayed(_fakeDelay);
    final index = _members.indexWhere((m) => m.id == id);
    if (index < 0) throw Exception('Usuario no encontrado: $id');
    _assertNotLastOwner(_members[index]);
    _members[index] = _members[index].copyWith(isActive: false);
  }

  void _assertEmailFree(String email, {required String? exceptId}) {
    final taken =
        _members.any((m) => m.id != exceptId && m.email.toLowerCase() == email);
    if (taken) throw DuplicateMemberEmailException(email);
  }

  void _assertNotLastOwner(TenantMember member) {
    if (member.roleId != TenantRoles.owner || !member.isActive) return;
    final owners = _members
        .where((m) => m.roleId == TenantRoles.owner && m.isActive)
        .length;
    if (owners <= 1) throw const LastOwnerException();
  }

  // ── Categorías ─────────────────────────────────────────────────────────

  @override
  Future<List<Category>> listCategories() async {
    await Future.delayed(_fakeDelay);
    return List.unmodifiable(_categories);
  }

  @override
  Future<Category> createCategory(String name) async {
    await Future.delayed(_fakeDelay);
    final clean = name.trim();
    _assertCategoryNameFree(clean, exceptId: null);

    final category = Category(
      id: 'cat-${(++_categoryCounter).toString().padLeft(3, '0')}-new',
      name: clean,
      productCount: 0,
    );
    _categories.add(category);
    return category;
  }

  @override
  Future<Category> renameCategory({
    required String id,
    required String name,
  }) async {
    await Future.delayed(_fakeDelay);
    final clean = name.trim();
    _assertCategoryNameFree(clean, exceptId: id);

    final index = _categories.indexWhere((c) => c.id == id);
    if (index < 0) throw Exception('Categoría no encontrada: $id');
    final updated = _categories[index].copyWith(name: clean);
    _categories[index] = updated;
    return updated;
  }

  @override
  Future<void> deleteCategory(String id) async {
    await Future.delayed(_fakeDelay);
    final index = _categories.indexWhere((c) => c.id == id);
    if (index < 0) throw Exception('Categoría no encontrada: $id');
    final category = _categories[index];
    if (category.productCount > 0) {
      throw CategoryInUseException(category.productCount);
    }
    _categories.removeAt(index);
  }

  void _assertCategoryNameFree(String name, {required String? exceptId}) {
    final taken = _categories.any(
        (c) => c.id != exceptId && c.name.toLowerCase() == name.toLowerCase());
    if (taken) throw DuplicateCategoryNameException(name);
  }

  // ── Roles y permisos ───────────────────────────────────────────────────

  @override
  Future<List<TenantRole>> listRoles() async {
    await Future.delayed(_fakeDelay);
    return List.unmodifiable(_roles);
  }

  @override
  Future<TenantRole> updateRolePermissions({
    required String roleId,
    required Set<String> permissions,
  }) async {
    await Future.delayed(_fakeDelay);
    final required = TenantRoles.undroppable[roleId];
    if (required != null && !permissions.contains(required)) {
      throw const RoleLockoutException();
    }

    final index = _roles.indexWhere((r) => r.id == roleId);
    if (index < 0) throw Exception('Rol no encontrado: $roleId');
    final updated = _roles[index].copyWith(permissions: Set.of(permissions));
    _roles[index] = updated;
    return updated;
  }

  // ── Semillas ───────────────────────────────────────────────────────────

  /// Los tres almacenes que `TransferStockModal` trae hoy hardcodeados
  /// (W-01), para que al cablearlo consuma esta misma lista sin sorpresas.
  List<Warehouse> _seedWarehouses() {
    final base = DateTime(2026, 1, 15);
    return [
      Warehouse(
          id: 'wh-001',
          name: 'Almacén Principal',
          isActive: true,
          createdAt: base),
      Warehouse(
          id: 'wh-002',
          name: 'Mostrador',
          isActive: true,
          createdAt: base.add(const Duration(days: 2))),
      Warehouse(
          id: 'wh-003',
          name: 'Bodega',
          isActive: true,
          createdAt: base.add(const Duration(days: 40))),
    ];
  }

  /// El correo de la sesión se le asigna al Dueño, **salvo** que sea uno de
  /// los empleados de la semilla: así se puede entrar como Encargado o Cajero
  /// (en el mock, cualquiera de estos correos) y ver la app con los permisos
  /// recortados de ese rol, que es justo lo que hay que poder probar.
  static const _seededStaff = {
    'maria.hernandez@nexus.mx',
    'jose.ramirez@nexus.mx',
    'ana.torres@nexus.mx',
    'carlos.mendoza@nexus.mx',
  };

  List<TenantMember> _seedMembers() {
    final base = DateTime(2026, 1, 15);
    final ownerEmail =
        _seededStaff.contains(currentEmail) ? 'dueno@nexus.mx' : currentEmail;
    return [
      TenantMember(
        id: 'usr-001',
        name: _nameFromEmail(ownerEmail),
        email: ownerEmail,
        roleId: TenantRoles.owner,
        isActive: true,
        createdAt: base,
      ),
      TenantMember(
        id: 'usr-002',
        name: 'María Hernández',
        email: 'maria.hernandez@nexus.mx',
        roleId: TenantRoles.manager,
        isActive: true,
        createdAt: base.add(const Duration(days: 12)),
      ),
      TenantMember(
        id: 'usr-003',
        name: 'José Luis Ramírez',
        email: 'jose.ramirez@nexus.mx',
        roleId: TenantRoles.cashier,
        isActive: true,
        createdAt: base.add(const Duration(days: 30)),
      ),
      TenantMember(
        id: 'usr-004',
        name: 'Ana Torres',
        email: 'ana.torres@nexus.mx',
        roleId: TenantRoles.cashier,
        isActive: true,
        createdAt: base.add(const Duration(days: 96)),
      ),
      TenantMember(
        id: 'usr-005',
        name: 'Carlos Mendoza',
        email: 'carlos.mendoza@nexus.mx',
        roleId: TenantRoles.salesperson,
        isActive: false,
        createdAt: base.add(const Duration(days: 140)),
      ),
    ];
  }

  /// Las categorías del mock de inventario, con cuántos productos usan cada
  /// una: "Otros" va vacía a propósito, para poder probar el borrado.
  List<Category> _seedCategories() => [
        const Category(id: 'cat-001', name: 'Bebidas', productCount: 5),
        const Category(id: 'cat-002', name: 'Abarrotes', productCount: 4),
        const Category(id: 'cat-003', name: 'Botanas', productCount: 3),
        const Category(id: 'cat-004', name: 'Limpieza', productCount: 3),
        const Category(id: 'cat-005', name: 'Otros', productCount: 0),
      ];

  /// Los cuatro roles sembrados en `backend/app/seed.py`, con sus mismos
  /// permisos. Única desviación: `inventario.gestionar_almacenes` (propuesto,
  /// decisión #11) se le da sólo al Dueño — crear almacenes es una decisión
  /// estructural del negocio, no de la operación diaria.
  List<TenantRole> _seedRoles() {
    final todos = Permissions.catalog.map((p) => p.name).toSet();
    return [
      TenantRole(
        id: TenantRoles.owner,
        label: 'Dueño',
        description: 'Control total del negocio, incluidos usuarios y permisos',
        permissions: todos,
      ),
      TenantRole(
        id: TenantRoles.manager,
        label: 'Encargado',
        description: 'Opera y administra el día a día, sin tocar los almacenes',
        permissions: todos
            .where((p) => p != Permissions.inventarioGestionarAlmacenes)
            .toSet(),
      ),
      const TenantRole(
        id: TenantRoles.cashier,
        label: 'Cajero',
        description: 'Cobra, abre y cierra su turno de caja',
        permissions: {
          Permissions.inventarioVer,
          Permissions.ventasVer,
          Permissions.ventasCrear,
          Permissions.ventasCobrar,
          Permissions.cajaVer,
          Permissions.cajaArquear,
          Permissions.cajaMovimientos,
        },
      ),
      const TenantRole(
        id: TenantRoles.salesperson,
        label: 'Vendedor',
        description: 'Arma la venta, pero no la cobra',
        permissions: {
          Permissions.inventarioVer,
          Permissions.ventasCrear,
        },
      ),
    ];
  }

  /// "eduardo.cristancho@nexus.mx" → "Eduardo Cristancho". El backend legacy
  /// no expone nombre completo en `/saas/me` (sólo email/username/role_name),
  /// así que el mock lo deriva en vez de inventar un nombre ajeno.
  static String _nameFromEmail(String email) {
    final local = email.split('@').first;
    final parts = local
        .split(RegExp(r'[._-]+'))
        .where((p) => p.isNotEmpty)
        .map((p) => '${p[0].toUpperCase()}${p.substring(1)}');
    return parts.isEmpty ? email : parts.join(' ');
  }
}
