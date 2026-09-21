import 'package:equatable/equatable.dart';

import '../../analytics/domain/employee_performance.dart' show CommissionType;

export '../../analytics/domain/employee_performance.dart' show CommissionType;

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
    this.commissionType = CommissionType.percentageSale,
    this.commissionRate = 0,
  });

  final String id;
  final String name;
  final String email;
  final String roleId;
  final bool isActive;
  final DateTime createdAt;

  /// Esquema de comisión (RF-10). Lo fija el dueño desde Usuarios; tasa 0 =
  /// no comisiona (valor por defecto, sin sugerencia). El checkout del backend
  /// registra el asiento con estos valores cada vez que la persona cobra.
  final CommissionType commissionType;
  final double commissionRate;

  bool get hasCommission => commissionRate > 0;

  /// "5 % de lo que vende" · "10 % de la ganancia" · "$15.00 fijos por venta".
  /// Lenguaje de tendero, no de contador (Fase B, Sep 2026).
  String? get commissionLabel {
    if (!hasCommission) return null;
    final rate = commissionRate == commissionRate.roundToDouble()
        ? commissionRate.toStringAsFixed(0)
        : commissionRate.toStringAsFixed(2);
    return switch (commissionType) {
      CommissionType.percentageSale => '$rate % de lo que vende',
      CommissionType.percentageProfit => '$rate % de la ganancia',
      CommissionType.fixedPerSale =>
        '\$${commissionRate.toStringAsFixed(2)} fijos por venta',
    };
  }

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
    CommissionType? commissionType,
    double? commissionRate,
  }) =>
      TenantMember(
        id: id,
        name: name ?? this.name,
        email: email ?? this.email,
        roleId: roleId ?? this.roleId,
        isActive: isActive ?? this.isActive,
        createdAt: createdAt,
        commissionType: commissionType ?? this.commissionType,
        commissionRate: commissionRate ?? this.commissionRate,
      );

  @override
  List<Object?> get props => [
        id,
        name,
        email,
        roleId,
        isActive,
        createdAt,
        commissionType,
        commissionRate,
      ];
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
