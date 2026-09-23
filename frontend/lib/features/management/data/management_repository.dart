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
/// Estado del backend (Sep 22, 2026 — Permisos por rol, Fase A): el modular
/// expone `GET/POST /users`, `PUT /users/{id}` (incluye `default_warehouse_id`),
/// `PATCH /users/{id}/status`, `GET /roles` (con `permissions[]`) y
/// `GET /permissions`. **Personas, roles y permisos corren contra el real**
/// (`ManagementRepositoryImpl`); almacenes y categorías siguen en el mock
/// hasta que Alan los entregue — la Impl delega esas partes al mock. La
/// edición de permisos por rol no existe en el servidor (Fase B): los roles
/// son de sólo lectura.
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

  /// POST /users — la contraseña inicial la elige el dueño y se la dice a la
  /// persona; el backend la exige (mín. 6). Tasa 0 = no comisiona.
  Future<TenantMember> createMember({
    required String name,
    required String email,
    required String roleId,
    required String password,
    CommissionType commissionType = CommissionType.percentageSale,
    double commissionRate = 0,
    String? defaultWarehouseId,
  });

  /// PUT /users/{id}. El correo no se puede cambiar en el backend real
  /// (`UserUpdate` no lo acepta): la UI lo muestra bloqueado al editar.
  /// `defaultWarehouseId` asigna el almacén donde opera la persona (D15).
  Future<TenantMember> updateMember({
    required String id,
    String? name,
    String? email,
    String? roleId,
    CommissionType? commissionType,
    double? commissionRate,
    String? defaultWarehouseId,
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
  /// GET /roles — los cuatro roles globales con sus permisos. Sólo lectura:
  /// personalizarlos por comercio es la Fase B.
  Future<List<TenantRole>> listRoles();
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
    final me = _members.firstWhere(
      (m) => m.email == currentEmail,
      orElse: () => _members.first,
    );
    // Igual que `/auth/me`: los permisos efectivos son los del rol.
    final role = _roles.firstWhere((r) => r.id == me.roleId);
    return me.copyWith(permissions: role.permissions);
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
    required String password,
    CommissionType commissionType = CommissionType.percentageSale,
    double commissionRate = 0,
    String? defaultWarehouseId,
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
      commissionType: commissionType,
      commissionRate: commissionRate,
      defaultWarehouseId: defaultWarehouseId,
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
    CommissionType? commissionType,
    double? commissionRate,
    String? defaultWarehouseId,
  }) async {
    await Future.delayed(_fakeDelay);
    final index = _members.indexWhere((m) => m.id == id);
    if (index < 0) throw Exception('Usuario no encontrado: $id');
    final current = _members[index];

    final cleanEmail = email?.trim().toLowerCase();
    if (cleanEmail != null) _assertEmailFree(cleanEmail, exceptId: id);

    // Degradar al último Dueño activo dejaría el comercio sin quien administre.
    if (roleId != null && roleId != RoleCodes.owner) {
      _assertNotLastOwner(current);
    }

    final updated = current.copyWith(
      name: name?.trim(),
      email: cleanEmail,
      roleId: roleId,
      commissionType: commissionType,
      commissionRate: commissionRate,
      defaultWarehouseId: defaultWarehouseId,
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
    if (member.roleId != RoleCodes.owner || !member.isActive) return;
    final owners =
        _members.where((m) => m.roleId == RoleCodes.owner && m.isActive).length;
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
        roleId: RoleCodes.owner,
        isActive: true,
        createdAt: base,
      ),
      TenantMember(
        id: 'usr-002',
        name: 'María Hernández',
        email: 'maria.hernandez@nexus.mx',
        roleId: RoleCodes.admin,
        isActive: true,
        createdAt: base.add(const Duration(days: 12)),
      ),
      TenantMember(
        id: 'usr-003',
        name: 'José Luis Ramírez',
        email: 'jose.ramirez@nexus.mx',
        roleId: RoleCodes.cashier,
        isActive: true,
        createdAt: base.add(const Duration(days: 30)),
        commissionType: CommissionType.percentageSale,
        commissionRate: 5,
      ),
      TenantMember(
        id: 'usr-004',
        name: 'Ana Torres',
        email: 'ana.torres@nexus.mx',
        roleId: RoleCodes.cashier,
        isActive: true,
        createdAt: base.add(const Duration(days: 96)),
      ),
      TenantMember(
        id: 'usr-005',
        name: 'Carlos Mendoza',
        email: 'carlos.mendoza@nexus.mx',
        roleId: RoleCodes.warehouse,
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

  /// Los cuatro roles globales del seed (`0002_seed_rbac_permissions.py`)
  /// con exactamente sus permisos; el id es el código porque el mock no
  /// tiene UUIDs. OWNER lleva el catálogo completo, como en el servidor.
  List<TenantRole> _seedRoles() => [
        TenantRole(
          id: RoleCodes.owner,
          code: RoleCodes.owner,
          label: 'Dueño',
          description: 'Dueño del comercio con acceso total',
          permissions: Permissions.all,
        ),
        TenantRole(
          id: RoleCodes.admin,
          code: RoleCodes.admin,
          label: 'Encargado',
          description: 'Administrador de tienda y catálogo',
          permissions: Permissions.all
              .where((p) => p != Permissions.settingsBilling)
              .toSet(),
        ),
        const TenantRole(
          id: RoleCodes.cashier,
          code: RoleCodes.cashier,
          label: 'Cajero',
          description: 'Cajero para punto de venta y corte de caja',
          permissions: {
            Permissions.inventoryView,
            Permissions.salesView,
            Permissions.salesCheckout,
            Permissions.cashView,
            Permissions.cashOpenSession,
            Permissions.cashCloseSession,
            Permissions.cashManualMovement,
          },
        ),
        const TenantRole(
          id: RoleCodes.warehouse,
          code: RoleCodes.warehouse,
          label: 'Almacenista',
          description: 'Encargado de almacén y recepción de compras',
          permissions: {
            Permissions.inventoryView,
            Permissions.inventoryCreate,
            Permissions.inventoryAdjustStock,
            Permissions.purchasesView,
            Permissions.purchasesCreate,
          },
        ),
      ];

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
