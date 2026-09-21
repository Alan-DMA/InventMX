import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_app/features/whatsapp_catalog/data/whatsapp_message_formatter.dart';
import 'package:nexus_app/features/whatsapp_catalog/domain/public_catalog.dart';
import 'package:nexus_app/features/whatsapp_catalog/domain/whatsapp_order.dart';

const _store = PublicStoreInfo(
  name: 'Abarrotes Don Pepe',
  slug: 'abarrotes-don-pepe',
  whatsappNumber: '+52 55 1234 5678',
  minOrderAmountMxn: 50,
  deliveryFeeMxn: 20,
);

const _coca = PublicCatalogProduct(
  id: 'p1',
  name: 'Coca-Cola 600ml',
  sku: 'COCA600',
  priceMxn: 18,
);
const _pan = PublicCatalogProduct(
  id: 'p2',
  name: 'Pan Bimbo Grande',
  sku: 'PAN',
  priceMxn: 52,
);
const _agotado = PublicCatalogProduct(
  id: 'p3',
  name: 'Sabritas 45g',
  sku: 'SAB',
  priceMxn: 17,
  inStock: false,
);

WhatsAppOrderDraft _draft({
  DeliveryMethod delivery = DeliveryMethod.pickup,
  String? address,
  PaymentMethodPreview payment = PaymentMethodPreview.cash,
  double? cash,
  String? phone,
  String? notes,
  List<CartLine>? lines,
}) =>
    WhatsAppOrderDraft(
      customerName: 'María González',
      customerPhone: phone,
      deliveryMethod: delivery,
      deliveryAddress: address,
      paymentMethod: payment,
      cashTenderedMxn: cash,
      orderNotes: notes,
      lines: lines ??
          const [
            CartLine(product: _coca, quantity: 6),
            CartLine(product: _pan, quantity: 1, notes: 'el más fresco'),
          ],
    );

void main() {
  const formatter = WhatsAppMessageFormatter();

  group('WhatsAppMessageFormatter — paridad con el backend', () {
    test('recoger en tienda, efectivo sin cambio', () {
      final build = formatter.build(store: _store, draft: _draft());

      expect(build.formattedText, '''
🛒 *¡NUEVO PEDIDO WEB - ABARROTES DON PEPE!*
--------------------------------------------
👤 *Cliente:* María González

📋 *DETALLE DE PRODUCTOS:*
1. *Coca-Cola 600ml* x6 - \$108.00 MXN
2. *Pan Bimbo Grande* x1 - \$52.00 MXN _(Nota: el más fresco)_
--------------------------------------------
💵 *Subtotal:* \$160.00 MXN
🏪 *Entrega:* Recoger en tienda
💰 *TOTAL A PAGAR:* \$160.00 MXN
--------------------------------------------
💳 *Forma de Pago:* Efectivo contra entrega

_Pedido generado vía InventMX Catálogo Digital_''');
      expect(build.subtotalMxn, 160);
      expect(build.deliveryFeeMxn, 0);
      expect(build.totalMxn, 160);
      expect(build.changeMxn, isNull);
      expect(build.itemCount, 2);
    });

    test('a domicilio suma el envío y escribe la dirección', () {
      final build = formatter.build(
        store: _store,
        draft: _draft(
          delivery: DeliveryMethod.delivery,
          address: 'Av. Insurgentes 123, Col. Centro',
        ),
      );

      expect(build.deliveryFeeMxn, 20);
      expect(build.totalMxn, 180);
      expect(
          build.formattedText, contains('🛵 *Envío a domicilio:* \$20.00 MXN'));
      expect(build.formattedText,
          contains('📍 *Dirección:* Av. Insurgentes 123, Col. Centro'));
      expect(build.formattedText, isNot(contains('Recoger en tienda')));
    });

    test('efectivo con "paga con" calcula el cambio', () {
      final build = formatter.build(
        store: _store,
        draft: _draft(cash: 200, phone: '55 9876 5432', notes: 'tocar timbre'),
      );

      expect(build.changeMxn, 40);
      expect(build.formattedText, contains('📱 *Teléfono:* 55 9876 5432'));
      expect(build.formattedText, contains('💵 *Paga con:* \$200.00 MXN'));
      expect(
          build.formattedText, contains('🪙 *Cambio a devolver:* \$40.00 MXN'));
      expect(build.formattedText, contains('📝 *Observaciones:* tocar timbre'));
    });

    test('transferencia y tarjeta usan las etiquetas del backend', () {
      expect(
        formatter
            .build(
                store: _store,
                draft: _draft(payment: PaymentMethodPreview.transfer))
            .formattedText,
        contains('💳 *Forma de Pago:* Transferencia bancaria / SPEI'),
      );
      expect(
        formatter
            .build(
                store: _store,
                draft: _draft(payment: PaymentMethodPreview.cardOnDelivery))
            .formattedText,
        contains('💳 *Forma de Pago:* Tarjeta contra entrega (Terminal TPV)'),
      );
    });

    test('el enlace wa.me lleva solo dígitos y el texto codificado', () {
      final build = formatter.build(store: _store, draft: _draft());

      expect(build.waLink.host, 'wa.me');
      expect(build.waLink.path, '/525512345678');
      expect(build.waLink.queryParameters['text'], build.formattedText);
    });

    test('sin número de tienda el enlace deja elegir el chat', () {
      final build = formatter.build(
        store: const PublicStoreInfo(name: 'X', slug: 'x'),
        draft: _draft(),
      );

      expect(build.waLink.path, '/');
      expect(build.waLink.queryParameters['text'], isNotEmpty);
    });

    test('miles con coma, como el :,.2f de Python', () {
      expect(WhatsAppMessageFormatter.money(1234.5), '1,234.50');
      expect(WhatsAppMessageFormatter.money(1234567), '1,234,567.00');
      expect(WhatsAppMessageFormatter.money(18), '18.00');
      expect(WhatsAppMessageFormatter.money(0.5), '0.50');
    });
  });

  group('WhatsAppMessageFormatter — reglas de la tienda (422)', () {
    test('pedido vacío', () {
      expect(
        () => formatter.build(store: _store, draft: _draft(lines: const [])),
        throwsA(isA<OrderRejected>()),
      );
    });

    test('producto agotado en el pedido', () {
      expect(
        () => formatter.build(
          store: _store,
          draft:
              _draft(lines: const [CartLine(product: _agotado, quantity: 1)]),
        ),
        throwsA(isA<OrderRejected>()
            .having((e) => e.message, 'message', contains('Sabritas 45g'))),
      );
    });

    test('pedido mínimo', () {
      expect(
        () => formatter.build(
          store: _store,
          draft: _draft(lines: const [CartLine(product: _coca, quantity: 1)]),
        ),
        throwsA(isA<OrderRejected>().having(
          (e) => e.message,
          'message',
          'El subtotal (\$18.00 MXN) es menor al pedido mínimo requerido '
              '(\$50.00 MXN).',
        )),
      );
    });

    test('a domicilio sin dirección', () {
      expect(
        () => formatter.build(
          store: _store,
          draft: _draft(delivery: DeliveryMethod.delivery, address: 'x'),
        ),
        throwsA(isA<OrderRejected>()
            .having((e) => e.message, 'message', contains('dirección'))),
      );
    });

    test('a domicilio cuando la tienda no entrega', () {
      const noDelivery = PublicStoreInfo(
        name: 'X',
        slug: 'x',
        deliveryEnabled: false,
      );
      expect(
        () => formatter.build(
          store: noDelivery,
          draft:
              _draft(delivery: DeliveryMethod.delivery, address: 'Calle 1 #2'),
        ),
        throwsA(isA<OrderRejected>()),
      );
    });

    test('efectivo menor al total', () {
      expect(
        () => formatter.build(store: _store, draft: _draft(cash: 100)),
        throwsA(isA<OrderRejected>().having(
          (e) => e.message,
          'message',
          'El efectivo con el que pagará (\$100.00 MXN) no puede ser menor '
              'al total (\$160.00 MXN).',
        )),
      );
    });
  });

  group('orderLinkText / orderFolio — aviso corto con enlace', () {
    test('lleva folio, cliente, conteo, entrega, total y enlace; no el detalle',
        () {
      final totals = formatter.build(store: _store, draft: _draft());
      final order = SavedOrder(
        folio: 'P-260914-AB6F',
        slug: 'abarrotes-don-pepe',
        issuedAt: DateTime(2026, 9, 14),
        draft: _draft(),
        totals: totals,
      );
      final text = WhatsAppMessageFormatter.orderLinkText(
        store: _store,
        order: order,
        ticketUrl:
            'https://nexus.com/tienda/abarrotes-don-pepe/pedido/P-260914-AB6F',
      );

      expect(text, '''
🧾 *Pedido P-260914-AB6F* · Abarrotes Don Pepe
👤 María González · 7 artículos · recoger en tienda
💰 *Total: \$160.00 MXN*

Ver ticket completo:
https://nexus.com/tienda/abarrotes-don-pepe/pedido/P-260914-AB6F

_El detalle está en el ticket; este mensaje es solo el aviso._''');
      expect(text, isNot(contains('Coca-Cola')));
    });

    test('el folio es determinista por contenido y fecha', () {
      final a = orderFolio('hola', DateTime(2026, 9, 14));
      final b = orderFolio('hola', DateTime(2026, 9, 14));
      final c = orderFolio('adiós', DateTime(2026, 9, 14));

      expect(a, b);
      expect(a, isNot(c));
      expect(a, matches(RegExp(r'^P-260914-[0-9A-F]{4}$')));
    });
  });

  group('readyText — "Avisar al cliente" (QA 20 sep 2026)', () {
    SavedOrder saved(DeliveryMethod method) => SavedOrder(
          folio: 'P-260920-AB12',
          slug: 'tiendita-nexus',
          issuedAt: DateTime(2026, 9, 20, 12),
          draft: WhatsAppOrderDraft(
            customerName: 'Laura Jiménez',
            deliveryMethod: method,
            lines: const [],
          ),
          totals: WhatsAppOrderBuild(
            waLink: Uri.parse('https://wa.me/'),
            formattedText: '',
            subtotalMxn: 1234.5,
            totalMxn: 1234.5,
            itemCount: 0,
          ),
        );

    test('recoger: nombre de pila, folio, total y tienda', () {
      final text = WhatsAppMessageFormatter.readyText(
          order: saved(DeliveryMethod.pickup), storeName: 'Tiendita Nexus');
      expect(text, contains('Hola Laura'));
      expect(text, contains('*P-260920-AB12*'));
      expect(text, contains('listo para recoger'));
      expect(text, contains('\$1,234.50 MXN'));
      expect(text, endsWith('— Tiendita Nexus'));
    });

    test('a domicilio: "va en camino"', () {
      final text = WhatsAppMessageFormatter.readyText(
          order: saved(DeliveryMethod.delivery), storeName: 'T');
      expect(text, contains('va en camino'));
    });
  });
}
