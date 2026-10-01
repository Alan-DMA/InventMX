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
/// Lo que pasó en el turno según el servidor (Integración de Caja, Oct 2026):
/// la app ya no recalcula el esperado con `GET /sales` y nombres de cajero.
class CashShiftSummary extends Equatable {
  const CashShiftSummary({
    this.cashSalesMxn = 0,
    this.cashReceivedMxn = 0,
    this.changeGivenMxn = 0,
    this.depositsMxn = 0,
    this.withdrawalsMxn = 0,
    this.digitalTotalsMxn = const {},
    this.salesCount = 0,
    this.salesTotalMxn = 0,
    this.movementsCount = 0,
  });

  /// Ventas en efectivo, netas de cambio (lo que de verdad entró al cajón).
  final double cashSalesMxn;

  /// Efectivo que entregaron los clientes y cambio que se les dio (ya descontado).
  final double cashReceivedMxn;
  final double changeGivenMxn;
  final double depositsMxn;
  final double withdrawalsMxn;

  /// Por método del API: `SPEI`, `CARD_TPV`, `CODI`, `OTHER`.
  final Map<String, double> digitalTotalsMxn;
  final int salesCount;
  final double salesTotalMxn;
  final int movementsCount;

  @override
  List<Object?> get props =>
      [cashSalesMxn, cashReceivedMxn, changeGivenMxn, depositsMxn, withdrawalsMxn, digitalTotalsMxn, salesCount, salesTotalMxn, movementsCount];
}

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
    this.summary,
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

  /// Del servidor; `null` si la respuesta no lo trae (mock, versiones viejas).
  final CashShiftSummary? summary;

  CashSession copyWith({
    CashSessionStatus? status,
    double? expectedCashMxn,
    double? physicalCashMxn,
    double? differenceMxn,
    CashBalanceResult? balanceResult,
    DateTime? closedAt,
    CashShiftSummary? summary,
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
      summary: summary ?? this.summary,
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
        summary,
      ];
}
