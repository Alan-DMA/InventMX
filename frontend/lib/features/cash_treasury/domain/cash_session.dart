import 'package:equatable/equatable.dart';

/// Estado de una sesión de caja — Doc. Maestro RF-18, `CashSessionStatus`
/// en `docs/api/components.yaml`.
enum CashSessionStatus { open, closed }

/// Resultado del arqueo al cerrar el turno.
enum CashBalanceResult {
  exact,
  short,
  over;

  String get label => switch (this) {
        CashBalanceResult.exact => 'Cuadre exacto',
        CashBalanceResult.short => 'Faltante',
        CashBalanceResult.over => 'Sobrante',
      };
}

/// Sesión de caja (turno) — modelada sobre `CashSession` de
/// `docs/api/components.yaml`.
///
/// Trazabilidad: Constitución Art. VII (7.2) · Doc. Maestro RF-18, RF-19
///              Sección 6 (SR-07) · HU-15 / CU-17, CU-18
class CashSession extends Equatable {
  const CashSession({
    required this.id,
    required this.cashierName,
    required this.status,
    required this.openingAmountMxn,
    required this.expectedCashMxn,
    required this.openedAt,
    this.physicalCashMxn,
    this.differenceMxn,
    this.balanceResult,
    this.closedAt,
  });

  final String id;
  final String cashierName;
  final CashSessionStatus status;
  final double openingAmountMxn;

  /// Saldo teórico: fondo inicial + ventas en efectivo del turno.
  final double expectedCashMxn;

  final double? physicalCashMxn;
  final double? differenceMxn;
  final CashBalanceResult? balanceResult;
  final DateTime openedAt;
  final DateTime? closedAt;

  CashSession copyWith({
    CashSessionStatus? status,
    double? expectedCashMxn,
    double? physicalCashMxn,
    double? differenceMxn,
    CashBalanceResult? balanceResult,
    DateTime? closedAt,
  }) {
    return CashSession(
      id: id,
      cashierName: cashierName,
      status: status ?? this.status,
      openingAmountMxn: openingAmountMxn,
      expectedCashMxn: expectedCashMxn ?? this.expectedCashMxn,
      openedAt: openedAt,
      physicalCashMxn: physicalCashMxn ?? this.physicalCashMxn,
      differenceMxn: differenceMxn ?? this.differenceMxn,
      balanceResult: balanceResult ?? this.balanceResult,
      closedAt: closedAt ?? this.closedAt,
    );
  }

  @override
  List<Object?> get props => [
        id,
        cashierName,
        status,
        openingAmountMxn,
        expectedCashMxn,
        physicalCashMxn,
        differenceMxn,
        balanceResult,
        openedAt,
        closedAt,
      ];
}
