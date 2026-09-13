import 'package:equatable/equatable.dart';

/// Proveedor — modelado sobre el schema `Supplier` de
/// `docs/api/components.yaml`.
///
/// Trazabilidad: Constitución Art. I (1.2.8) · Doc. Maestro Sección 5.3
///              (RF-15, RF-16) · HU-17 / CU-22
class Supplier extends Equatable {
  const Supplier({
    required this.id,
    required this.name,
    required this.balanceDueMxn,
    required this.createdAt,
    this.contactName,
    this.phone,
    this.email,
    this.rfc,
  });

  final String id;
  final String name;
  final String? contactName;
  final String? phone;
  final String? email;
  final String? rfc;

  /// Suma de saldos pendientes en `AccountPayable` de este proveedor.
  final double balanceDueMxn;

  final DateTime createdAt;

  @override
  List<Object?> get props =>
      [id, name, contactName, phone, email, rfc, balanceDueMxn, createdAt];
}
