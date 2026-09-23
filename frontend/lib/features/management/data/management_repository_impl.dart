import 'package:dio/dio.dart';

import '../../../core/network/dio_client.dart';
import '../../analytics/data/models/json_number.dart';
import '../domain/app_permission.dart';
import '../domain/category.dart';
import '../domain/tenant_member.dart';
import '../domain/tenant_role.dart';
import '../domain/warehouse.dart';
import 'management_repository.dart';

/// Gestión del comercio contra el backend real — Permisos por rol, Fase A
/// (Sep 22, 2026).
///
/// | Parte                 | Fuente                                          |
/// |-----------------------|-------------------------------------------------|
/// | Quién soy + permisos  | `GET /auth/me` → `role.permissions[].code`       |
/// | Personas              | `GET/POST /users`, `PUT /users/{id}`, `PATCH /users/{id}/status` |
/// | Roles (lectura)       | `GET /roles` — 4 roles globales con `permissions[]` |
/// | Almacenes, categorías | **mock** (decisión de Eduardo, sin cambio aquí)  |
///
/// Los códigos de `Permissions.*` son exactamente los del servidor; a un
/// `OWNER` el backend no le siembra filas (`require_permission` lo deja
/// pasar por definición), así que aquí recibe el catálogo completo.
class ManagementRepositoryImpl implements ManagementRepository {
  ManagementRepositoryImpl({required this.client, required this.fallback});

  final DioClient client;

  /// Mock para lo que el backend todavía no cubre.
  final ManagementRepositoryMock fallback;

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

  // ── Delegado al mock ───────────────────────────────────────────────────

  @override
  Future<List<Warehouse>> listWarehouses() => fallback.listWarehouses();

  @override
  Future<Warehouse> createWarehouse(String name) =>
      fallback.createWarehouse(name);

  @override
  Future<Warehouse> updateWarehouse(
          {required String id, required String name}) =>
      fallback.updateWarehouse(id: id, name: name);

  @override
  Future<void> deactivateWarehouse(String id) =>
      fallback.deactivateWarehouse(id);

  @override
  Future<List<Category>> listCategories() => fallback.listCategories();

  @override
  Future<Category> createCategory(String name) => fallback.createCategory(name);

  @override
  Future<Category> renameCategory({required String id, required String name}) =>
      fallback.renameCategory(id: id, name: name);

  @override
  Future<void> deleteCategory(String id) => fallback.deleteCategory(id);

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
    final data = e.response?.data;
    final detail = data is Map ? data['detail']?.toString() : null;
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
}
