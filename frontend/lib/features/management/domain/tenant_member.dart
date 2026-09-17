import 'package:equatable/equatable.dart';

/// Una persona que trabaja en el comercio. Es el `User` del backend acotado
/// al tenant en sesión — nunca cruza a usuarios de otro comercio (RLS).
class TenantMember extends Equatable {
  const TenantMember({
    required this.id,
    required this.name,
    required this.email,
    required this.roleId,
    required this.isActive,
    required this.createdAt,
  });

  final String id;
  final String name;
  final String email;
  final String roleId;
  final bool isActive;
  final DateTime createdAt;

  /// Iniciales para el avatar ("José Luis Ramírez" → "JR").
  String get initials {
    final parts =
        name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  TenantMember copyWith({
    String? name,
    String? email,
    String? roleId,
    bool? isActive,
  }) =>
      TenantMember(
        id: id,
        name: name ?? this.name,
        email: email ?? this.email,
        roleId: roleId ?? this.roleId,
        isActive: isActive ?? this.isActive,
        createdAt: createdAt,
      );

  @override
  List<Object?> get props => [id, name, email, roleId, isActive, createdAt];
}

/// El correo ya lo usa otra persona del comercio.
class DuplicateMemberEmailException implements Exception {
  const DuplicateMemberEmailException(this.email);
  final String email;

  String get message => 'Ya hay alguien en el negocio con el correo $email.';

  @override
  String toString() => message;
}

/// Se intentó dar de baja (o degradar) al único dueño activo.
class LastOwnerException implements Exception {
  const LastOwnerException();

  String get message =>
      'Este es el único Dueño del negocio. Nombra a otro Dueño antes de '
      'cambiarle el rol o darlo de baja.';

  @override
  String toString() => message;
}
