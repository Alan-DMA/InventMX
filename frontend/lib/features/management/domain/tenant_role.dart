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

  bool can(String permission) => permissions.contains(permission);

  TenantRole copyWith({Set<String>? permissions}) => TenantRole(
        id: id,
        code: code,
        label: label,
        description: description,
        permissions: permissions ?? this.permissions,
      );

  @override
  List<Object?> get props => [id, code, label, description, permissions];
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
