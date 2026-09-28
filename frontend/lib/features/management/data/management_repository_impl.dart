import 'package:dio/dio.dart';

import '../../../core/network/dio_client.dart';
import '../../analytics/data/models/json_number.dart';
import '../domain/app_permission.dart';
import '../domain/category.dart';
import '../domain/tenant_member.dart';
import '../domain/tenant_role.dart';
import '../domain/warehouse.dart';
import 'management_repository.dart';

/// Gestión del comercio contra el backend real — Permisos por rol (Fases A
/// y B, Sep 2026) y Ajustes operativos (Sep 27, 2026).
///
/// | Parte                 | Fuente                                          |
/// |-----------------------|-------------------------------------------------|
/// | Quién soy + permisos  | `GET /auth/me` → `role.permissions[].code`       |
/// | Personas              | `GET/POST /users`, `PUT /users/{id}`, `PATCH /users/{id}/status` |
/// | Roles                 | `GET /roles`, `PUT /roles/{id}/permissions`, `DELETE /roles/{id}` |
/// | Almacenes             | `GET/POST/PUT/DELETE /inventory/warehouses`, `…/{id}/activate`, `…/{id}/make-default` (D7) |
/// | Categorías            | `GET/POST/PUT/DELETE /inventory/categories` (D8) |
///
/// Los códigos de `Permissions.*` son exactamente los del servidor; a un
/// `OWNER` el backend no le siembra filas (`require_permission` lo deja
/// pasar por definición), así que aquí recibe el catálogo completo.
class ManagementRepositoryImpl implements ManagementRepository {
  ManagementRepositoryImpl({required this.client});

  final DioClient client;

  // ── Sesión ─────────────────────────────────────────────────────────────

  @override
  Future<TenantMember> getCurrentMember() async {
    try {
      final res = await client.get('/api/v1/auth/me');
      return _memberFromJson(res.data as Map);
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  // ── Personas ───────────────────────────────────────────────────────────

  @override
  Future<List<TenantMember>> listMembers() async {
    try {
      final res = await client.get('/api/v1/users');
      final list = (res.data as List? ?? const [])
          .whereType<Map>()
          .map(_memberFromJson)
          .toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      return list;
    } on DioException catch (e) {
      throw _mapError(e);
    }
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
    try {
      final res = await client.post('/api/v1/users', data: {
        'full_name': name.trim(),
        'email': email.trim().toLowerCase(),
        'password': password,
        'role_id': roleId,
      });
      var member = _memberFromJson(res.data as Map);
      // `UserCreate` no acepta comisión ni almacén: se fijan en una segunda
      // llamada (`PUT /users/{id}`).
      if (commissionRate > 0 || defaultWarehouseId != null) {
        member = await updateMember(
          id: member.id,
          commissionType: commissionRate > 0 ? commissionType : null,
          commissionRate: commissionRate > 0 ? commissionRate : null,
          defaultWarehouseId: defaultWarehouseId,
        );
      }
      return member;
    } on DioException catch (e) {
      throw _mapError(e, email: email);
    }
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
    try {
      final res = await client.put('/api/v1/users/$id', data: {
        if (name != null) 'full_name': name.trim(),
        if (roleId != null) 'role_id': roleId,
        if (commissionType != null) 'commission_type': commissionType.apiValue,
        if (commissionRate != null) 'commission_rate': commissionRate,
        if (defaultWarehouseId != null)
          'default_warehouse_id': defaultWarehouseId,
      });
      return _memberFromJson(res.data as Map);
    } on DioException catch (e) {
      throw _mapError(e, email: email);
    }
  }

  @override
  Future<void> deactivateMember(String id) async {
    try {
      // El endpoint alterna: sólo se llama sobre alguien activo (la UI ya no
      // ofrece "dar de baja" a un inactivo).
      await client.patch('/api/v1/users/$id/status');
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  // ── Roles ──────────────────────────────────────────────────────────────

  @override
  Future<List<TenantRole>> listRoles() async {
    try {
      final res = await client.get('/api/v1/roles');
      final roles = (res.data as List? ?? const []).whereType<Map>().map((r) {
        final code = r['name']?.toString() ?? '';
        final id = r['id']?.toString() ?? code;
        return TenantRole(
          id: id,
          code: code,
          label: code.roleLabel,
          description: r['description']?.toString() ?? '',
          permissions: _permissionsFromJson(code, r['permissions']),
          isCustom: r['tenant_id'] != null,
        );
      }).toList();
      // Orden fijo de lectura: dueño → encargado → cajero → almacén.
      const order = [
        RoleCodes.owner,
        RoleCodes.admin,
        RoleCodes.cashier,
        RoleCodes.warehouse,
      ];
      roles
          .sort((a, b) => _rank(a.code, order).compareTo(_rank(b.code, order)));
      return roles;
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  static int _rank(String code, List<String> order) {
    final i = order.indexOf(code);
    return i < 0 ? order.length : i;
  }

  /// `permissions[].code` del servidor. OWNER → catálogo completo (el seed
  /// no le siembra filas). Códigos que la app no conoce se conservan: no
  /// abren puertas, pero tampoco se pierden al mostrar el rol.
  static Set<String> _permissionsFromJson(String code, Object? raw) {
    if (code == RoleCodes.owner) return Permissions.all;
    return (raw as List? ?? const [])
        .map((p) => p is Map ? p['code']?.toString() : p?.toString())
        .whereType<String>()
        .toSet();
  }

  @override
  Future<TenantRole> updateRolePermissions({
    required String roleId,
    required Set<String> permissions,
  }) async {
    try {
      final res = await client.put(
        '/api/v1/roles/$roleId/permissions',
        data: {'permissions': permissions.toList()},
      );
      return _roleFromJson(res.data as Map);
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  @override
  Future<TenantRole> resetRole(String roleId) async {
    try {
      final res = await client.delete('/api/v1/roles/$roleId');
      return _roleFromJson(res.data as Map);
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  static TenantRole _roleFromJson(Map r) {
    final code = r['name']?.toString() ?? '';
    return TenantRole(
      id: r['id']?.toString() ?? code,
      code: code,
      label: code.roleLabel,
      description: r['description']?.toString() ?? '',
      permissions: _permissionsFromJson(code, r['permissions']),
      isCustom: r['tenant_id'] != null,
    );
  }

  // ── Almacenes ──────────────────────────────────────────────────────────

  /// Activos e inactivos: la pantalla de Almacenes muestra los dados de baja
  /// para poder reactivarlos; los selectores filtran (`warehousesProvider`
  /// de Inventario).
  @override
  Future<List<Warehouse>> listWarehouses() async {
    try {
      final res = await client.get('/api/v1/inventory/warehouses');
      return (res.data as List? ?? const [])
          .whereType<Map>()
          .map(_warehouseFromJson)
          .toList();
    } on DioException catch (e) {
      throw _mapCatalogError(e);
    }
  }

  /// El servidor exige nombre único (409). El nuevo nunca nace como
  /// principal (`is_default: false`) — el esquema lo pone en `true` por
  /// omisión; el principal se cambia con "Hacer principal" (D7b).
  @override
  Future<Warehouse> createWarehouse(String name) async {
    final clean = name.trim();
    try {
      final res = await client.post(
        '/api/v1/inventory/warehouses',
        data: {'name': clean, 'is_default': false},
      );
      return _warehouseFromJson(res.data as Map);
    } on DioException catch (e) {
      throw _mapCatalogError(e,
          onConflict: () => DuplicateWarehouseNameException(clean));
    }
  }

  @override
  Future<Warehouse> updateWarehouse({
    required String id,
    required String name,
  }) async {
    final clean = name.trim();
    try {
      final res = await client.put(
        '/api/v1/inventory/warehouses/$id',
        data: {'name': clean},
      );
      return _warehouseFromJson(res.data as Map);
    } on DioException catch (e) {
      throw _mapCatalogError(e,
          onConflict: () => DuplicateWarehouseNameException(clean));
    }
  }

  /// El motivo del rechazo (422) viene armado del servidor y se muestra tal
  /// cual: cada regla de D7 dice qué resolver.
  @override
  Future<void> deactivateWarehouse(String id) async {
    try {
      await client.delete('/api/v1/inventory/warehouses/$id');
    } on DioException catch (e) {
      throw _mapCatalogError(e);
    }
  }

  @override
  Future<void> activateWarehouse(String id) async {
    try {
      await client.post('/api/v1/inventory/warehouses/$id/activate');
    } on DioException catch (e) {
      throw _mapCatalogError(e);
    }
  }

  @override
  Future<void> makeDefaultWarehouse(String id) async {
    try {
      await client.post('/api/v1/inventory/warehouses/$id/make-default');
    } on DioException catch (e) {
      throw _mapCatalogError(e);
    }
  }

  static Warehouse _warehouseFromJson(Map json) => Warehouse(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? 'Almacén',
        isActive: json['is_active'] != false,
        isDefault: json['is_default'] == true,
        createdAt: toDateTimeOrNull(json['created_at']) ?? DateTime.now(),
      );

  // ── Categorías ─────────────────────────────────────────────────────────

  /// Las mismas que usa Inventario (CA-A6): hasta Ajustes operativos esta
  /// pantalla mostraba las del mock.
  @override
  Future<List<Category>> listCategories() async {
    try {
      final res = await client.get('/api/v1/inventory/categories');
      return (res.data as List? ?? const [])
          .whereType<Map>()
          .map(_categoryFromJson)
          .toList();
    } on DioException catch (e) {
      throw _mapCatalogError(e);
    }
  }

  @override
  Future<Category> createCategory(String name) async {
    final clean = name.trim();
    try {
      final res = await client.post(
        '/api/v1/inventory/categories',
        data: {'name': clean},
      );
      return _categoryFromJson(res.data as Map);
    } on DioException catch (e) {
      throw _mapCatalogError(e,
          onConflict: () => DuplicateCategoryNameException(clean));
    }
  }

  @override
  Future<Category> renameCategory({
    required String id,
    required String name,
  }) async {
    final clean = name.trim();
    try {
      final res = await client.put(
        '/api/v1/inventory/categories/$id',
        data: {'name': clean},
      );
      return _categoryFromJson(res.data as Map);
    } on DioException catch (e) {
      throw _mapCatalogError(e,
          onConflict: () => DuplicateCategoryNameException(clean));
    }
  }

  /// Con productos el servidor responde 422 con cuántos tiene (D8).
  @override
  Future<void> deleteCategory(String id) async {
    try {
      await client.delete('/api/v1/inventory/categories/$id');
    } on DioException catch (e) {
      throw _mapCatalogError(e);
    }
  }

  static Category _categoryFromJson(Map json) => Category(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        productCount: toIntOrZero(json['product_count']),
      );

  // ── Mapeo ──────────────────────────────────────────────────────────────

  static TenantMember _memberFromJson(Map json) => TenantMember(
        id: json['id']?.toString() ?? '',
        name: (json['full_name'] ?? json['email'] ?? '').toString(),
        email: json['email']?.toString() ?? '',
        roleId: json['role_id']?.toString() ??
            ((json['role'] as Map?)?['id']?.toString() ?? ''),
        roleCode: (json['role'] as Map?)?['name']?.toString(),
        permissions: _permissionsFromJson(
          (json['role'] as Map?)?['name']?.toString() ?? '',
          (json['role'] as Map?)?['permissions'],
        ),
        defaultWarehouseId: json['default_warehouse_id']?.toString(),
        isActive: json['is_active'] != false,
        createdAt: toDateTimeOrNull(json['created_at']) ?? DateTime.now(),
        commissionType:
            CommissionType.fromApi(json['commission_type']?.toString()),
        commissionRate: toDoubleOrZero(json['commission_rate']),
      );

  /// El backend responde en español y con `detail`; se muestra tal cual
  /// (mismo criterio que compras y pedidos). Los casos con excepción de
  /// dominio propia (correo duplicado, último dueño) se conservan para que
  /// la UI siga tratándolos igual que con el mock.
  static Exception _mapError(DioException e, {String? email}) {
    final detail = _detailOf(e.response?.data);
    final status = e.response?.statusCode;
    if (status == 409 ||
        (detail != null && detail.toLowerCase().contains('correo'))) {
      return DuplicateMemberEmailException(email ?? '');
    }
    // "No es posible cambiar o degradar el rol del dueño principal" /
    // "No es posible desactivar la cuenta principal del dueño" → el mismo
    // caso que el mock llama "último dueño". Otros mensajes con OWNER (p. ej.
    // "sólo el dueño puede designar OWNER") se muestran tal cual.
    if (detail != null &&
        (detail.contains('degradar') ||
            detail.contains('desactivar la cuenta'))) {
      return const LastOwnerException();
    }
    if (detail != null) return Exception(detail);
    if (status == 403) {
      return Exception('No tienes permiso para administrar usuarios.');
    }
    if (e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout) {
      return Exception('Sin conexión con el servidor. Revisa tu red.');
    }
    return Exception('No se pudo completar la operación.');
  }

  /// Almacenes y categorías: 409 → la excepción de nombre repetido del
  /// dominio; lo demás, el mensaje del servidor tal cual (como en Usuarios).
  static Exception _mapCatalogError(
    DioException e, {
    Exception Function()? onConflict,
  }) {
    final status = e.response?.statusCode;
    if (status == 409 && onConflict != null) return onConflict();
    final detail = _detailOf(e.response?.data);
    if (detail != null) return Exception(detail);
    if (status == 403) {
      return Exception(
          'No tienes permiso para cambiar las preferencias de la tienda.');
    }
    if (e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout) {
      return Exception('Sin conexión con el servidor. Revisa tu red.');
    }
    return Exception('No se pudo completar la operación.');
  }

  /// El servidor responde de dos formas: `{detail}` (HTTPException) o
  /// `{error: {message}}` (excepciones de negocio con envolvente).
  static String? _detailOf(Object? data) {
    if (data is! Map) return null;
    final detail = data['detail'];
    if (detail is String) return detail;
    final error = data['error'];
    if (error is Map && error['message'] != null) {
      return error['message'].toString();
    }
    return null;
  }
}
