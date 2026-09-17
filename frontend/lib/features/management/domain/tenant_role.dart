import 'package:equatable/equatable.dart';

import 'app_permission.dart';

/// Rol dentro de un comercio. Los cuatro roles de sistema replican los
/// sembrados en `backend/app/seed.py`.
class TenantRole extends Equatable {
  const TenantRole({
    required this.id,
    required this.label,
    required this.description,
    required this.permissions,
  });

  /// Identificador del backend (`TENANT_OWNER`, `MANAGER`, …).
  final String id;

  /// Cómo se le llama al rol en la tienda ("Dueño", "Cajero").
  final String label;
  final String description;
  final Set<String> permissions;

  bool can(String permission) => permissions.contains(permission);

  TenantRole copyWith({Set<String>? permissions}) => TenantRole(
        id: id,
        label: label,
        description: description,
        permissions: permissions ?? this.permissions,
      );

  @override
  List<Object?> get props => [id, label, description, permissions];
}

abstract final class TenantRoles {
  static const owner = 'TENANT_OWNER';
  static const manager = 'MANAGER';
  static const cashier = 'CASHIER';
  static const salesperson = 'SALESPERSON';

  /// El dueño no puede quedarse sin la llave de la casa: si se le quita
  /// `usuarios.gestionar` nadie podría volver a repartir permisos y el
  /// comercio queda bloqueado sin salida (ver [RoleLockoutException]).
  static const undroppable = <String, String>{
    owner: Permissions.usuariosGestionar,
  };
}

/// Se intentó dejar al comercio sin nadie que pueda administrar permisos.
class RoleLockoutException implements Exception {
  const RoleLockoutException();

  String get message =>
      'El rol Dueño debe conservar "Dar de alta usuarios y cambiar sus '
      'permisos". Sin él nadie podría volver a repartir accesos.';

  @override
  String toString() => message;
}
