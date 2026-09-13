import 'package:equatable/equatable.dart';

/// Tipo de movimiento de caja menor — `CashMovement.type` en
/// `docs/api/components.yaml` (WITHDRAWAL/DEPOSIT).
enum CashMovementType {
  withdrawal,
  deposit;

  /// Valor enviado a `POST /cash/sessions/{id}/movements` (docs/api/cash.yaml).
  String get apiValue => switch (this) {
        CashMovementType.withdrawal => 'WITHDRAWAL',
        CashMovementType.deposit => 'DEPOSIT',
      };

  String get label => switch (this) {
        CashMovementType.withdrawal => 'Retiro',
        CashMovementType.deposit => 'Entrada',
      };
}

/// Movimiento extraordinario de caja menor durante un turno (retiro a
/// proveedor, recarga de cambio, etc.) — modelado sobre `CashMovement` de
/// `docs/api/components.yaml`.
///
/// Trazabilidad: Constitución Art. VII (7.2) · Doc. Maestro RF-18, Sección 6
///              (SR-07) · HU-16 / CU-19
class CashMovement extends Equatable {
  const CashMovement({
    required this.id,
    required this.cashSessionId,
    required this.type,
    required this.amountMxn,
    required this.description,
    required this.createdAt,
  });

  final String id;
  final String cashSessionId;
  final CashMovementType type;
  final double amountMxn;
  final String description;
  final DateTime createdAt;

  @override
  List<Object?> get props =>
      [id, cashSessionId, type, amountMxn, description, createdAt];
}
