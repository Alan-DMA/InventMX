import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../../../core/theme/app_colors.dart';
import '../../domain/cart_state.dart';
import '../../domain/payment_entry.dart';

// ---------------------------------------------------------------------------
// Colores propios de la tarjeta — la tarjeta imita un ticket de papel real y
// se mantiene clara aunque el resto de la pantalla use el tema oscuro de
// Nexus (decisión aprobada: "Ticket claro sobre fondo oscuro").
// ---------------------------------------------------------------------------

const _paperColor = Color(0xFFF9F9FF);
const _inkColor = Color(0xFF191C23);
const _inkMuted = Color(0xFF414754);

/// Tarjeta visual del comprobante de venta — Tarea 8.2.1.
///
/// Formato tipo ticket térmico (58/80mm): tipografía monoespaciada para
/// montos y folio, separadores punteados y bordes dentados que imitan el
/// papel picado de una impresora térmica.
///
/// Trazabilidad: Doc. Maestro RF-08 (Sección 5.2) · Constitución Art. VIII
/// (8.2: Nota de venta administrativa, NO CFDI) · HU-14 / CU-16
class SaleReceiptCard extends StatelessWidget {
  const SaleReceiptCard({
    super.key,
    required this.result,
    required this.businessName,
    required this.warehouseName,
    required this.footerMessage,
    required this.pageBackground,
  });

  final CheckoutResult result;
  final String businessName;
  final String warehouseName;
  final String footerMessage;

  /// Color de fondo de la pantalla contenedora — se usa para "perforar" el
  /// borde dentado superior/inferior de la tarjeta (misma técnica que el
  /// diseño de Figma: círculos del color del fondo recortados por la propia
  /// tarjeta).
  final Color pageBackground;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: _paperColor,
          boxShadow: [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 8,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(17),
              child: _ReceiptContent(
                result: result,
                businessName: businessName,
                warehouseName: warehouseName,
                footerMessage: footerMessage,
              ),
            ),
            Positioned(
              top: -4,
              left: 0,
              right: 0,
              child: _NotchRow(color: pageBackground),
            ),
            Positioned(
              bottom: -4,
              left: 0,
              right: 0,
              child: _NotchRow(color: pageBackground),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Contenido del ticket
// ---------------------------------------------------------------------------

class _ReceiptContent extends StatelessWidget {
  const _ReceiptContent({
    required this.result,
    required this.businessName,
    required this.warehouseName,
    required this.footerMessage,
  });

  final CheckoutResult result;
  final String businessName;
  final String warehouseName;
  final String footerMessage;

  @override
  Widget build(BuildContext context) {
    final mono = GoogleFonts.jetBrainsMono();
    final hasChange = result.changeGivenMxn > 0;

    return Column(
      children: [
        // ── Encabezado del comercio ──────────────────────────────────────
        Text(
          businessName,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: _inkColor,
          ),
        ),
        if (warehouseName.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            warehouseName,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14, color: _inkMuted),
          ),
        ],
        const SizedBox(height: 12),
        QrImageView(
          data: result.folio,
          size: 86,
          backgroundColor: _paperColor,
          eyeStyle: const QrEyeStyle(color: _inkColor),
          dataModuleStyle: const QrDataModuleStyle(color: _inkColor),
        ),

        const _DashedDivider(),

        // ── Folio, cajero, fecha/hora ─────────────────────────────────────
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    result.folio,
                    style: mono.copyWith(fontSize: 14, color: _inkMuted),
                  ),
                  Text(
                    result.cashierName,
                    style: const TextStyle(fontSize: 12, color: _inkMuted),
                  ),
                ],
              ),
            ),
            Text(
              '${_formatDate(result.completedAt)}\n${_formatTime(result.completedAt)}',
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 12, color: _inkMuted, height: 1.35),
            ),
          ],
        ),

        const _DashedDivider(),

        // ── Ítems ─────────────────────────────────────────────────────────
        Column(
          children: [
            for (final item in result.items)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        '${item.name} x${item.quantity}',
                        style: mono.copyWith(fontSize: 14, color: _inkColor),
                      ),
                    ),
                    Text(
                      '\$${item.subtotalMxn.toStringAsFixed(2)}',
                      style: mono.copyWith(fontSize: 14, color: _inkColor),
                    ),
                  ],
                ),
              ),
          ],
        ),

        const _DashedDivider(),

        // ── Totales y desglose de pago ──────────────────────────────────
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Total',
              style: mono.copyWith(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: _inkColor,
              ),
            ),
            Text(
              '\$${result.totalMxn.toStringAsFixed(2)}',
              style: mono.copyWith(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: _inkColor,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        for (final payment in result.payments)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _paymentLabel(payment),
                  style: mono.copyWith(fontSize: 14, color: _inkMuted),
                ),
                Text(
                  '\$${payment.amountMxn.toStringAsFixed(2)}',
                  style: mono.copyWith(fontSize: 14, color: _inkMuted),
                ),
              ],
            ),
          ),
        if (hasChange)
          Container(
            margin: const EdgeInsets.only(top: 4),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.emerald.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Vuelto',
                  style: mono.copyWith(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.emeraldDark,
                  ),
                ),
                Text(
                  '\$${result.changeGivenMxn.toStringAsFixed(2)}',
                  style: mono.copyWith(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.emeraldDark,
                  ),
                ),
              ],
            ),
          ),

        const _DashedDivider(topPad: 16, bottomPad: 8),

        // ── Pie ───────────────────────────────────────────────────────────
        Text(
          footerMessage,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 14, color: _inkMuted),
        ),
      ],
    );
  }

  String _paymentLabel(PaymentEntry payment) => payment.method.label;

  String _formatDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${(d.year % 100).toString().padLeft(2, '0')}';

  String _formatTime(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

// ---------------------------------------------------------------------------
// Separador punteado — imita el corte entre secciones de un ticket térmico.
// ---------------------------------------------------------------------------

class _DashedDivider extends StatelessWidget {
  const _DashedDivider({this.topPad = 8, this.bottomPad = 8});

  final double topPad;
  final double bottomPad;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: topPad, bottom: bottomPad),
      child: CustomPaint(
        size: const Size(double.infinity, 1),
        painter: _DashedLinePainter(),
      ),
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
// dentado de papel picado (misma técnica que el diseño de Figma).
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
