import '../domain/public_catalog.dart';
import '../domain/whatsapp_order.dart';

/// Arma el mensaje estructurado y el enlace `wa.me` — Tarea 13.2.2 (RF-24).
///
/// **Réplica exacta de `PublicCatalogService.build_whatsapp_order`** del
/// backend (mismo orden de líneas, mismos emojis, mismo formato de cifras),
/// por dos razones:
///   · el mock lo usa para que la UI y los tests no cambien al conectar el
///     endpoint real;
///   · sirve de respaldo si el servidor no responde — el cliente ya tiene
///     todo en pantalla y no debe perder el pedido por una caída.
///
/// Las validaciones también son las del backend (pedido mínimo, dirección
/// con al menos 5 caracteres, efectivo no menor al total) y lanzan
/// [OrderRejected] con el mismo texto que devolvería el 422.
class WhatsAppMessageFormatter {
  const WhatsAppMessageFormatter();

  static const _rule = '--------------------------------------------';

  WhatsAppOrderBuild build({
    required PublicStoreInfo store,
    required WhatsAppOrderDraft draft,
  }) {
    if (draft.lines.isEmpty) {
      throw const OrderRejected('Agrega al menos un producto al pedido.');
    }
    for (final line in draft.lines) {
      if (!line.product.inStock) {
        throw OrderRejected(
          'El producto "${line.product.name}" no está disponible para compra.',
        );
      }
    }

    final subtotal = _round(draft.subtotalMxn);
    if (store.minOrderAmountMxn > 0 && subtotal < store.minOrderAmountMxn) {
      throw OrderRejected(
        'El subtotal (\$${money(subtotal)} MXN) es menor al pedido mínimo '
        'requerido (\$${money(store.minOrderAmountMxn)} MXN).',
      );
    }

    var deliveryFee = 0.0;
    if (draft.deliveryMethod == DeliveryMethod.delivery) {
      if (!store.deliveryEnabled) {
        throw const OrderRejected(
            'Esta tienda no ofrece entrega a domicilio por ahora.');
      }
      final address = draft.deliveryAddress?.trim() ?? '';
      if (address.length < 5) {
        throw const OrderRejected(
            'Escribe la dirección de entrega (calle, número y colonia).');
      }
      deliveryFee = store.deliveryFeeMxn;
    } else if (!store.pickupEnabled) {
      throw const OrderRejected(
          'Esta tienda no ofrece recoger en tienda por ahora.');
    }

    final total = _round(subtotal + deliveryFee);

    double? change;
    final tendered = draft.cashTenderedMxn;
    if (draft.paymentMethod == PaymentMethodPreview.cash && tendered != null) {
      if (tendered < total) {
        throw OrderRejected(
          'El efectivo con el que pagará (\$${money(tendered)} MXN) no puede '
          'ser menor al total (\$${money(total)} MXN).',
        );
      }
      change = _round(tendered - total);
    }

    final lines = <String>[
      '🛒 *¡NUEVO PEDIDO WEB - ${store.name.toUpperCase()}!*',
      _rule,
      '👤 *Cliente:* ${draft.customerName.trim()}',
    ];
    final phone = draft.customerPhone?.trim();
    if (phone != null && phone.isNotEmpty) {
      lines.add('📱 *Teléfono:* $phone');
    }
    lines
      ..add('')
      ..add('📋 *DETALLE DE PRODUCTOS:*');
    for (final (i, line) in draft.lines.indexed) {
      var text = '${i + 1}. *${line.product.name}* x${line.quantity} - '
          '\$${money(_round(line.subtotalMxn))} MXN';
      final notes = line.notes?.trim();
      if (notes != null && notes.isNotEmpty) {
        text += ' _(Nota: $notes)_';
      }
      lines.add(text);
    }
    lines
      ..add(_rule)
      ..add('💵 *Subtotal:* \$${money(subtotal)} MXN');
    if (draft.deliveryMethod == DeliveryMethod.delivery) {
      lines
        ..add('🛵 *Envío a domicilio:* \$${money(deliveryFee)} MXN')
        ..add('📍 *Dirección:* ${draft.deliveryAddress!.trim()}');
    } else {
      lines.add('🏪 *Entrega:* Recoger en tienda');
    }
    lines
      ..add('💰 *TOTAL A PAGAR:* \$${money(total)} MXN')
      ..add(_rule)
      ..add('💳 *Forma de Pago:* ${_paymentLabel(draft.paymentMethod)}');
    if (draft.paymentMethod == PaymentMethodPreview.cash &&
        tendered != null &&
        tendered > 0) {
      lines
        ..add('💵 *Paga con:* \$${money(tendered)} MXN')
        ..add('🪙 *Cambio a devolver:* \$${money(change!)} MXN');
    }
    final notes = draft.orderNotes?.trim();
    if (notes != null && notes.isNotEmpty) {
      lines.add('📝 *Observaciones:* $notes');
    }
    lines
      ..add('')
      ..add('_Pedido generado vía InventMX Catálogo Digital_');

    final formatted = lines.join('\n');
    return WhatsAppOrderBuild(
      waLink: waLinkFor(store.whatsappNumber, formatted),
      formattedText: formatted,
      subtotalMxn: subtotal,
      deliveryFeeMxn: deliveryFee,
      totalMxn: total,
      changeMxn: change,
      itemCount: draft.lines.length,
    );
  }

  /// Mensaje corto que sí va por el chat (iteración 3 de QA): folio, quién,
  /// cuánto y el **enlace al ticket**. El detalle no viaja en el texto —
  /// vive en el servidor — así que editarlo no sirve de nada, y el toque
  /// abre directo el chat de la tienda (`wa.me/{número}`).
  static String orderLinkText({
    required PublicStoreInfo store,
    required SavedOrder order,
    required String ticketUrl,
  }) {
    final items =
        order.itemCount == 1 ? '1 artículo' : '${order.itemCount} artículos';
    final delivery = order.draft.deliveryMethod == DeliveryMethod.delivery
        ? 'a domicilio'
        : 'recoger en tienda';
    return [
      '🧾 *Pedido ${order.folio}* · ${store.name}',
      '👤 ${order.draft.customerName.trim()} · $items · $delivery',
      '💰 *Total: \$${money(order.totals.totalMxn)} MXN*',
      '',
      'Ver ticket completo:',
      ticketUrl,
      '',
      '_El detalle está en el ticket; este mensaje es solo el aviso._',
    ].join('\n');
  }

  /// `https://wa.me/525512345678?text=…` — solo dígitos en el número, texto
  /// codificado. Sin número, `wa.me/?text=` deja al cliente elegir el chat.
  static Uri waLinkFor(String? phone, String text) {
    final digits = (phone ?? '').replaceAll(RegExp(r'\D'), '');
    return Uri.https('wa.me', digits.isEmpty ? '/' : '/$digits', {
      'text': text,
    });
  }

  /// `1234.5` → `1,234.50` — el `:,.2f` de Python.
  static String money(double value) {
    final fixed = value.toStringAsFixed(2);
    final dot = fixed.indexOf('.');
    final intPart = fixed.substring(0, dot);
    final buffer = StringBuffer();
    for (var i = 0; i < intPart.length; i++) {
      final fromEnd = intPart.length - i;
      buffer.write(intPart[i]);
      if (fromEnd > 1 && fromEnd % 3 == 1 && intPart[i] != '-') {
        buffer.write(',');
      }
    }
    return '$buffer${fixed.substring(dot)}';
  }

  static String _paymentLabel(PaymentMethodPreview method) => switch (method) {
        PaymentMethodPreview.cash => 'Efectivo contra entrega',
        PaymentMethodPreview.transfer => 'Transferencia bancaria / SPEI',
        PaymentMethodPreview.cardOnDelivery =>
          'Tarjeta contra entrega (Terminal TPV)',
      };

  static double _round(double value) => (value * 100).roundToDouble() / 100;
}

/// Folio del pedido: fecha + 4 caracteres derivados del contenido, para que
/// el mismo pedido dé siempre el mismo folio y dos distintos no.
/// `P-260914-3F2A`.
String orderFolio(String formattedText, DateTime issuedAt) {
  var hash = 0x811C9DC5;
  for (final unit in formattedText.codeUnits) {
    hash = ((hash ^ unit) * 0x01000193) & 0xFFFFFFFF;
  }
  final code = (hash & 0xFFFF).toRadixString(16).toUpperCase().padLeft(4, '0');
  String two(int n) => n.toString().padLeft(2, '0');
  final yy = (issuedAt.year % 100).toString().padLeft(2, '0');
  return 'P-$yy${two(issuedAt.month)}${two(issuedAt.day)}-$code';
}
