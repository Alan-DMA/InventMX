import 'package:flutter/material.dart';

import '../../domain/public_catalog.dart';
import '../../domain/whatsapp_order.dart';
import '../catalog_theme.dart';

/// El pedido como ticket — Tarea 13.2.2, iteración 3 de QA de Eduardo.
///
/// `wa.me` solo transporta texto, y un texto siempre se puede editar. Por eso
/// el chat lleva solo el aviso (folio, total, enlace) y **este ticket es lo
/// que la tienda abre desde el enlace** (`/tienda/{slug}/pedido/{folio}`),
/// tal como el cliente lo confirmó. El mismo widget es la vista previa en el
/// sheet: lo que ve es exactamente lo que la tienda verá.
///
/// Ancho fijo (320 px lógicos): cabe en cualquier teléfono sin scroll
/// horizontal.
class OrderTicket extends StatelessWidget {
  const OrderTicket({
    super.key,
    required this.store,
    required this.draft,
    required this.totals,
    required this.folio,
    required this.issuedAt,
  });

  final PublicStoreInfo store;
  final WhatsAppOrderDraft draft;
  final WhatsAppOrderBuild totals;
  final String folio;
  final DateTime issuedAt;

  static const double width = 320;

  static const _ink = Color(0xFF111827);
  static const _muted = Color(0xFF6B7280);
  static const _rule = Color(0xFFE5E7EB);
  static const _accent = Color(0xFF047857);

  @override
  Widget build(BuildContext context) {
    final ticket = Container(
      width: width,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      color: Colors.white,
      // Hereda la familia del tema (la del sistema) y fija el resto: así el
      // ticket se ve igual en la vista previa y en el PNG.
      child: DefaultTextStyle(
        style: (Theme.of(context).textTheme.bodyMedium ?? const TextStyle())
            .copyWith(fontSize: 12.5, height: 1.35, color: _ink),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            _header(),
            const SizedBox(height: 12),
            const _DashedRule(),
            const SizedBox(height: 10),
            _customer(),
            const SizedBox(height: 10),
            const _DashedRule(),
            const SizedBox(height: 10),
            _lines(),
            const SizedBox(height: 8),
            const _DashedRule(),
            const SizedBox(height: 8),
            _totals(),
            const SizedBox(height: 10),
            const _DashedRule(),
            const SizedBox(height: 10),
            _payment(),
            if ((draft.orderNotes ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              _row('Observaciones', draft.orderNotes!.trim()),
            ],
            const SizedBox(height: 14),
            const Center(
              child: Text(
                'Pedido generado vía Nexus · Catálogo Digital',
                style: TextStyle(fontSize: 10.5, color: _muted),
              ),
            ),
          ],
        ),
      ),
    );

    return ticket;
  }

  Widget _header() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                store.name.toUpperCase(),
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.3,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: _accent,
                borderRadius: BorderRadius.circular(5),
              ),
              child: const Text(
                'PEDIDO WEB',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: 0.6,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: Text(
                'Folio $folio',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontFeatures: CatalogTheme.tabular,
                ),
              ),
            ),
            Text(
              _formatDate(issuedAt),
              style: const TextStyle(
                color: _muted,
                fontFeatures: CatalogTheme.tabular,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _customer() {
    final phone = draft.customerPhone?.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _row('Cliente', draft.customerName.trim()),
        if (phone != null && phone.isNotEmpty) _row('Teléfono', phone),
        _row(
          'Entrega',
          draft.deliveryMethod == DeliveryMethod.delivery
              ? 'A domicilio'
              : 'Recoger en tienda',
        ),
        if (draft.deliveryMethod == DeliveryMethod.delivery)
          _row('Dirección', draft.deliveryAddress?.trim() ?? ''),
      ],
    );
  }

  Widget _lines() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Row(
          children: [
            SizedBox(
              width: 34,
              child: Text('CANT', style: _th),
            ),
            Expanded(child: Text('PRODUCTO', style: _th)),
            Text('IMPORTE', style: _th),
          ],
        ),
        const SizedBox(height: 6),
        for (final line in draft.lines)
          Padding(
            padding: const EdgeInsets.only(bottom: 5),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 34,
                  child: Text(
                    '${line.quantity}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontFeatures: CatalogTheme.tabular,
                    ),
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(line.product.name),
                      Text(
                        '${mxn(line.product.priceMxn)} c/u',
                        style: const TextStyle(
                          fontSize: 11,
                          color: _muted,
                          fontFeatures: CatalogTheme.tabular,
                        ),
                      ),
                      if ((line.notes ?? '').trim().isNotEmpty)
                        Text(
                          'Nota: ${line.notes!.trim()}',
                          style: const TextStyle(
                            fontSize: 11,
                            fontStyle: FontStyle.italic,
                            color: _muted,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  mxn(line.subtotalMxn),
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontFeatures: CatalogTheme.tabular,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _totals() {
    return Column(
      children: [
        _amount('Subtotal', totals.subtotalMxn),
        if (draft.deliveryMethod == DeliveryMethod.delivery)
          _amount('Envío a domicilio', totals.deliveryFeeMxn),
        const SizedBox(height: 4),
        Row(
          children: [
            const Expanded(
              child: Text(
                'TOTAL A PAGAR',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
              ),
            ),
            Text(
              '${mxn(totals.totalMxn)} MXN',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                fontFeatures: CatalogTheme.tabular,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _payment() {
    final tendered = draft.cashTenderedMxn;
    final change = totals.changeMxn;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _row('Forma de pago', _paymentLabel(draft.paymentMethod)),
        if (draft.paymentMethod == PaymentMethodPreview.cash &&
            tendered != null &&
            tendered > 0) ...[
          _row('Paga con', mxn(tendered)),
          if (change != null) _row('Cambio', mxn(change)),
        ],
      ],
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 92,
              child: Text(label, style: const TextStyle(color: _muted)),
            ),
            Expanded(
              child: Text(
                value,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      );

  Widget _amount(String label, double value) => Padding(
        padding: const EdgeInsets.only(bottom: 3),
        child: Row(
          children: [
            Expanded(child: Text(label, style: const TextStyle(color: _muted))),
            Text(
              mxn(value),
              style: const TextStyle(fontFeatures: CatalogTheme.tabular),
            ),
          ],
        ),
      );

  static const TextStyle _th = TextStyle(
    fontSize: 10,
    fontWeight: FontWeight.w700,
    color: _muted,
    letterSpacing: 0.6,
  );

  static String _paymentLabel(PaymentMethodPreview method) => switch (method) {
        PaymentMethodPreview.cash => 'Efectivo contra entrega',
        PaymentMethodPreview.transfer => 'Transferencia / SPEI',
        PaymentMethodPreview.cardOnDelivery => 'Tarjeta contra entrega',
      };

  static String _formatDate(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)}/${d.year} ${two(d.hour)}:${two(d.minute)}';
  }
}

/// Línea punteada de ticket — dibujada, no un string de guiones.
class _DashedRule extends StatelessWidget {
  const _DashedRule();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 1,
      child: CustomPaint(painter: _DashPainter()),
    );
  }
}

class _DashPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = OrderTicket._rule
      ..strokeWidth = 1;
    const dash = 4.0;
    const gap = 3.0;
    var x = 0.0;
    while (x < size.width) {
      canvas.drawLine(Offset(x, 0.5), Offset(x + dash, 0.5), paint);
      x += dash + gap;
    }
  }

  @override
  bool shouldRepaint(_DashPainter oldDelegate) => false;
}
