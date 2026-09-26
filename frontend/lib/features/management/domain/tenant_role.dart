import 'package:equatable/equatable.dart';

import 'app_permission.dart';

/// Rol dentro de un comercio. Los cuatro roles de sistema replican los
/// sembrados por la migración `0001` del backend (`OWNER`, `ADMIN`,
/// `CASHIER`, `WAREHOUSE`).
class TenantRole extends Equatable {
  const TenantRole({
    required this.id,
    required this.label,
    required this.description,
    required this.permissions,
    String? code,
    this.isCustom = false,
  }) : code = code ?? id;

  /// Identificador del backend. Con el backend real es un UUID; el mock usa
  /// el propio código como id.
  final String id;

  /// Código estable del rol (`OWNER`, `ADMIN`, `CASHIER`, `WAREHOUSE`): es lo
  /// que la app compara, nunca el id — el UUID cambia por instalación.
  final String code;

  bool get isOwner => code == RoleCodes.owner;

  /// Cómo se le llama al rol en la tienda ("Dueño", "Cajero").
  final String label;
  final String description;
  final Set<String> permissions;

  /// El comercio tiene su **propia versión** de este rol (Fase B): el servidor
  /// lo delata con `tenant_id` no nulo. Un rol estándar se comparte con todos
  /// los comercios y nadie lo edita.
  final bool isCustom;

  /// Acceso total por definición: el servidor deja pasar al dueño todas las
  /// puertas, así que personalizarlo no significaría nada.
  bool get isEditable => !isOwner;

  bool can(String permission) => permissions.contains(permission);

  TenantRole copyWith({Set<String>? permissions, bool? isCustom}) => TenantRole(
        id: id,
        code: code,
        label: label,
        description: description,
        permissions: permissions ?? this.permissions,
        isCustom: isCustom ?? this.isCustom,
      );

  @override
  List<Object?> get props =>
      [id, code, label, description, permissions, isCustom];
}

/// Códigos de rol del backend real (`public.roles.name`).
abstract final class RoleCodes {
  static const owner = 'OWNER';
  static const admin = 'ADMIN';
  static const cashier = 'CASHIER';
  static const warehouse = 'WAREHOUSE';
}

/// Etiquetas de tendero para los cuatro roles globales del seed.
extension RoleCodeLabel on String {
  String get roleLabel => switch (this) {
        RoleCodes.owner => 'Dueño',
        RoleCodes.admin => 'Encargado',
        RoleCodes.cashier => 'Cajero',
        RoleCodes.warehouse => 'Almacenista',
        _ => this,
      };
}

/// Se intentó editar el rol Dueño, que tiene acceso total por definición.
class ProtectedRoleException implements Exception {
  const ProtectedRoleException();

  String get message =>
      'El rol Dueño no se puede cambiar: tiene acceso a todo por definición.';

  @override
  String toString() => message;
}

/// Se intentó dejar un rol sin el permiso mínimo para que la app sirva.
class MinimumPermissionException implements Exception {
  const MinimumPermissionException();

  String get message =>
      'Todo rol conserva "Ver productos, categorías y existencias": sin eso, '
      'quien lo tenga entraría a una app en blanco.';

  @override
  String toString() => message;
}
