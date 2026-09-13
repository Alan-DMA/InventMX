import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../sales_pos/domain/payment_entry.dart';
import '../../domain/cash_denomination_entry.dart';
import '../../domain/cash_movement.dart';
import '../../domain/cash_session.dart';

// ---------------------------------------------------------------------------
// Colores propios de la tarjeta — mismo criterio ya aprobado en 8.2
// (`SaleReceiptCard`): el ticket imita papel real y se mantiene claro aunque
// el resto de la pantalla use el tema oscuro de Nexus.
// ---------------------------------------------------------------------------

const _paperColor = Color(0xFFF9F9FF);
const _inkColor = Color(0xFF191C23);
const _inkMuted = Color(0xFF414754);

/// Tarjeta visual del ticket de Corte Z — Subtarea 10.2.3.
///
/// Mismo formato tipo ticket térmico (58/80mm) que `SaleReceiptCard` (Tarea
/// 8.2.1): tipografía monoespaciada, separadores punteados y bordes
/// dentados que imitan el papel picado de una impresora térmica.
///
/// Widget puramente presentacional — todos los totales (ventas del turno,
/// desglose físico, movimientos) llegan ya calculados desde
/// `CashSessionSummaryScreen`.
///
/// Trazabilidad: Constitución Art. VII (7.2) · Doc. Maestro RF-18/RF-19 ·
///              HU-16 / CU-20
class CashClosingTicketCard extends StatelessWidget {
  const CashClosingTicketCard({
    super.key,
    required this.session,
    required this.businessName,
    required this.physicalEntries,
    required this.digitalTotals,
    required this.movements,
    required this.cashSalesMxn,
    required this.salesCount,
    required this.pageBackground,
  });

  /// Sesión ya cerrada (`status == closed`, con `physicalCashMxn`,
  /// `differenceMxn` y `balanceResult` resueltos).
  final CashSession session;
  final String businessName;
  final List<CashDenominationEntry> physicalEntries;
  final Map<PaymentMethodMxn, double> digitalTotals;
  final List<CashMovement> movements;
  final double cashSalesMxn;
  final int salesCount;

  /// Color de fondo de la pantalla contenedora — "perfora" el borde dentado,
  /// misma técnica que `SaleReceiptCard`.
  final Color pageBackground;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: _paperColor,
          boxShadow: [
            BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 2)),
          ],
        ),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(17),
              child: _TicketContent(
                session: session,
                businessName: businessName,
                physicalEntries: physicalEntries,
                digitalTotals: digitalTotals,
                movements: movements,
                cashSalesMxn: cashSalesMxn,
                salesCount: salesCount,
              ),
            ),
            Positioned(top: -4, left: 0, right: 0, child: _NotchRow(color: pageBackground)),
            Positioned(bottom: -4, left: 0, right: 0, child: _NotchRow(color: pageBackground)),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Contenido del ticket
// ---------------------------------------------------------------------------

class _TicketContent extends StatelessWidget {
  const _TicketContent({
    required this.session,
    required this.businessName,
    required this.physicalEntries,
    required this.digitalTotals,
    required this.movements,
    required this.cashSalesMxn,
    required this.salesCount,
  });

  final CashSession session;
  final String businessName;
  final List<CashDenominationEntry> physicalEntries;
  final Map<PaymentMethodMxn, double> digitalTotals;
  final List<CashMovement> movements;
  final double cashSalesMxn;
  final int salesCount;

  double get _digitalSalesMxn => digitalTotals.values.fold(0.0, (sum, v) => sum + v);

  double get _totalSalesMxn => cashSalesMxn + _digitalSalesMxn;

  Color _resultColor() => switch (session.balanceResult) {
        CashBalanceResult.exact => AppColors.emerald,
        CashBalanceResult.short => AppColors.error,
        CashBalanceResult.over => AppColors.warning,
        null => _inkMuted,
      };

  @override
  Widget build(BuildContext context) {
    final mono = GoogleFonts.jetBrainsMono();
    final resultColor = _resultColor();

    return Column(
      children: [
        // ── Encabezado ────────────────────────────────────────────────────
        Text(
          businessName,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: _inkColor),
        ),
        const SizedBox(height: 4),
        const Text(
          'CORTE DE CAJA (CORTE Z)',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _inkMuted, letterSpacing: 0.6),
        ),

        const _DashedDivider(),

        // ── Turno: cajero, apertura/cierre ──────────────────────────────
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Turno ${session.id}', style: mono.copyWith(fontSize: 13, color: _inkMuted)),
                  Text(session.cashierName, style: const TextStyle(fontSize: 12, color: _inkMuted)),
                ],
              ),
            ),
            Text(
              'Apertura ${_formatDateTime(session.openedAt)}\n'
              'Cierre   ${session.closedAt != null ? _formatDateTime(session.closedAt!) : '—'}',
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 11, color: _inkMuted, height: 1.35),
            ),
          ],
        ),

        const _DashedDivider(),

        // ── Ventas del turno ──────────────────────────────────────────────
        _sectionTitle('VENTAS DEL TURNO ($salesCount)'),
        const SizedBox(height: 6),
        _row(mono, 'Efectivo', cashSalesMxn),
        for (final method in digitalTotals.keys) _row(mono, method.label, digitalTotals[method]!),
        const SizedBox(height: 4),
        _row(mono, 'Total ventas', _totalSalesMxn, bold: true),

        const _DashedDivider(),

        // ── Desglose de efectivo físico contado ────────────────────────────
        _sectionTitle('EFECTIVO FÍSICO CONTADO'),
        const SizedBox(height: 6),
        if (physicalEntries.isEmpty)
          Text('Sin denominaciones registradas.', style: mono.copyWith(fontSize: 12, color: _inkMuted))
        else
          for (final entry in physicalEntries)
            _row(
              mono,
              '${entry.denomination.kind.label} \$${entry.denomination.displayValue} x${entry.quantity}',
              entry.subtotalMxn,
            ),

        if (movements.isNotEmpty) ...[
          const _DashedDivider(),
          _sectionTitle('MOVIMIENTOS DE CAJA MENOR'),
          const SizedBox(height: 6),
          for (final movement in movements)
            _row(
              mono,
              movement.description,
              movement.type == CashMovementType.deposit ? movement.amountMxn : -movement.amountMxn,
            ),
        ],

        const _DashedDivider(),

        // ── Balance final ───────────────────────────────────────────────
        _sectionTitle('BALANCE FINAL'),
        const SizedBox(height: 6),
        _row(mono, 'Fondo inicial', session.openingAmountMxn),
        _row(mono, 'Efectivo esperado', session.expectedCashMxn),
        _row(mono, 'Efectivo físico', session.physicalCashMxn ?? 0),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: resultColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                session.balanceResult?.label ?? '—',
                style: mono.copyWith(fontSize: 14, fontWeight: FontWeight.w700, color: resultColor),
              ),
              Text(
                '${(session.differenceMxn ?? 0) >= 0 ? '+' : '-'}'
                '\$${(session.differenceMxn ?? 0).abs().toStringAsFixed(2)}',
                style: mono.copyWith(fontSize: 14, fontWeight: FontWeight.w700, color: resultColor),
              ),
            ],
          ),
        ),

        const _DashedDivider(topPad: 16, bottomPad: 8),

        const Text(
          'Documento interno de control — no es un CFDI.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: _inkMuted),
        ),
      ],
    );
  }

  Widget _sectionTitle(String text) => Align(
        alignment: Alignment.centerLeft,
        child: Text(
          text,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _inkMuted, letterSpacing: 0.5),
        ),
      );

  Widget _row(TextStyle mono, String label, double amountMxn, {bool bold = false}) {
    final weight = bold ? FontWeight.w700 : FontWeight.w400;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: mono.copyWith(fontSize: 13, fontWeight: weight, color: _inkColor),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '\$${amountMxn.toStringAsFixed(2)}',
            style: mono.copyWith(fontSize: 13, fontWeight: weight, color: _inkColor),
          ),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${(d.year % 100).toString().padLeft(2, '0')} '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

// ---------------------------------------------------------------------------
// Separador punteado — idéntico al de `SaleReceiptCard` (Tarea 8.2.1).
// ---------------------------------------------------------------------------

class _DashedDivider extends StatelessWidget {
  const _DashedDivider({this.topPad = 8, this.bottomPad = 8});

  final double topPad;
  final double bottomPad;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: topPad, bottom: bottomPad),
      child: CustomPaint(size: const Size(double.infinity, 1), painter: _DashedLinePainter()),
    );
  }
}

class _DashedLinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0x99C1C6D6)
      ..strokeWidth = 1;
    const dashWidth = 4.0;
    const gapWidth = 4.0;
    var x = 0.0;
    while (x < size.width) {
      canvas.drawLine(Offset(x, 0), Offset(x + dashWidth, 0), paint);
      x += dashWidth + gapWidth;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ---------------------------------------------------------------------------
// Fila de "muescas" — recortada por el ClipRRect padre para simular el borde
// dentado de papel picado (misma técnica que `SaleReceiptCard`).
// ---------------------------------------------------------------------------

class _NotchRow extends StatelessWidget {
  const _NotchRow({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: List.generate(
        9,
        (_) => Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
      ),
    );
  }
}
