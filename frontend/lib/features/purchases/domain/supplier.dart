import 'package:equatable/equatable.dart';

/// Estado de un proveedor — `SupplierStatus` real del backend
/// (`backend/app/modules/purchasing_suppliers/domain/supplier.py`).
enum SupplierStatus {
  active,
  inactive;

  String get apiValue => switch (this) {
        SupplierStatus.active => 'ACTIVE',
        SupplierStatus.inactive => 'INACTIVE',
      };

  static SupplierStatus fromApi(String value) => switch (value) {
        'INACTIVE' => SupplierStatus.inactive,
        _ => SupplierStatus.active,
      };
}

/// Proveedor — modelado sobre `SupplierResponse` del backend real
/// (`schemas/supplier.py`), no sobre `docs/api/components.yaml` (desactualizado).
///
/// Trazabilidad: Constitución Art. I (1.2.8) · Doc. Maestro Sección 5.3
///              (RF-15, RF-16) · HU-17 / CU-22
class Supplier extends Equatable {
  const Supplier({
    required this.id,
    required this.name,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.tenantId,
    this.rfc,
    this.phone,
    this.email,
    this.address,
    this.creditDays = 0,
    this.creditLimitMxn = 0,
    this.notes,
  });

  final String id;
  final String? tenantId;
  final String name;
  final String? rfc;
  final String? phone;
  final String? email;
  final String? address;
  final int creditDays;
  final double creditLimitMxn;
  final SupplierStatus status;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  Supplier copyWith({
    String? name,
    String? rfc,
    String? phone,
    String? email,
    String? address,
    int? creditDays,
    double? creditLimitMxn,
    SupplierStatus? status,
    String? notes,
  }) =>
      Supplier(
        id: id,
        tenantId: tenantId,
        name: name ?? this.name,
        rfc: rfc ?? this.rfc,
        phone: phone ?? this.phone,
        email: email ?? this.email,
        address: address ?? this.address,
        creditDays: creditDays ?? this.creditDays,
        creditLimitMxn: creditLimitMxn ?? this.creditLimitMxn,
        status: status ?? this.status,
        notes: notes ?? this.notes,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );

  @override
  List<Object?> get props => [
        id,
        tenantId,
        name,
        rfc,
        phone,
        email,
        address,
        creditDays,
        creditLimitMxn,
        status,
        notes,
        createdAt,
        updatedAt,
      ];
}
