import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_app/features/purchases/data/receipt_row_classifier.dart';

void main() {
  const classifier = ReceiptRowClassifier();

  ReceiptRowKind kind(String row) => classifier.classify(row);

  group('ReceiptRowClassifier — ruido del proveedor y del documento', () {
    test('fechas y horas, en cualquier formato mexicano', () {
      expect(kind('Fecha: 12/09/2026'), ReceiptRowKind.date);
      expect(kind('12-09-26'), ReceiptRowKind.date);
      expect(kind('2026-09-12 14:35'), ReceiptRowKind.date);
      expect(kind('12 de septiembre de 2026'), ReceiptRowKind.date);
      expect(kind('3 SEP 2026'), ReceiptRowKind.date);
      expect(kind('Hora 14:35 hrs'), ReceiptRowKind.date);
      expect(kind('Vence 30/09/2026'), ReceiptRowKind.date);
    });

    test('teléfonos, con y sin palabra clave', () {
      expect(kind('Tel. 55 1234 5678'), ReceiptRowKind.contact);
      expect(kind('Tel.'), ReceiptRowKind.contact);
      expect(kind('55 1234 5678'), ReceiptRowKind.contact);
      expect(kind('(55) 1234-5678'), ReceiptRowKind.contact);
      expect(kind('5512345678'), ReceiptRowKind.contact);
      expect(kind('WhatsApp +52 55 1234 5678'), ReceiptRowKind.contact);
      expect(kind('Cel: 33 9876 5432'), ReceiptRowKind.contact);
    });

    test('correo, web y dirección', () {
      expect(kind('ventas@abarrotes.com'), ReceiptRowKind.contact);
      expect(kind('www.abarroteslopez.com.mx'), ReceiptRowKind.contact);
      expect(kind('Av. Insurgentes Sur 1234'), ReceiptRowKind.contact);
      expect(kind('Col. Centro, C.P. 06600'), ReceiptRowKind.contact);
      expect(kind('CP 44100 Guadalajara'), ReceiptRowKind.contact);
    });

    test('RFC, CURP, folio y referencias del documento', () {
      expect(kind('RFC: XAXX010101000'), ReceiptRowKind.reference);
      expect(kind('XAXX010101000'), ReceiptRowKind.reference);
      expect(kind('ABC123456XY9'), ReceiptRowKind.reference);
      expect(kind('Folio: A-00123'), ReceiptRowKind.reference);
      expect(kind('Pedido 45678'), ReceiptRowKind.reference);
      expect(kind('Cliente: TIENDA LA ESPERANZA'), ReceiptRowKind.reference);
      expect(kind('Vendedor Juan Pérez'), ReceiptRowKind.reference);
      expect(kind('Ruta 12'), ReceiptRowKind.reference);
    });

    test('cabecera de tabla y total', () {
      expect(kind('CANTIDAD DESCRIPCIÓN PRECIO IMPORTE'), ReceiptRowKind.header);
      expect(kind('Artículo Descripción Unidades Precio unitario'),
          ReceiptRowKind.header);
      expect(kind('IVA 42.40'), ReceiptRowKind.header);
      expect(kind('SUBTOTAL 265.00'), ReceiptRowKind.header);
      expect(kind('TOTAL \$307.40'), ReceiptRowKind.total);
      expect(kind('Total a pagar 307.40'), ReceiptRowKind.total);
    });
  });

  group('ReceiptRowClassifier — lo que SÍ es producto', () {
    test('renglones típicos de remisión mexicana', () {
      expect(kind('6 COCA COLA 600ML 18.50 111.00'), ReceiptRowKind.content);
      expect(kind('2 PZ PAN BIMBO GDE \$52.00 \$104.00'), ReceiptRowKind.content);
      expect(kind('CLORALEX 950ML 3 34.00 102.00'), ReceiptRowKind.content);
      expect(kind('1 ARTICULO 1 20 5 0 0,00 100,00'), ReceiptRowKind.content);
      expect(kind('ARTICULO 7'), ReceiptRowKind.content);
    });

    test('nombres con cifras dentro no son fecha ni teléfono', () {
      expect(kind('COCA 600ML'), ReceiptRowKind.content);
      expect(kind('12 PZ SABRITAS 45G'), ReceiptRowKind.content);
      expect(kind('6 MAYONESA 45.00 270.00'), ReceiptRowKind.content);
      expect(kind('2 MARINELA 10 20'), ReceiptRowKind.content);
      expect(kind('CABLE 2M'), ReceiptRowKind.content);
    });

    test('la evidencia de producto vence al patrón de contacto o referencia',
        () {
      // Una tienda que vende tiempo aire: "TELCEL" no es "Tel."
      expect(kind('TARJETA TELCEL 100 5 100.00 500.00'),
          ReceiptRowKind.content);
      // Col morada (la verdura), no "Col." (la colonia).
      expect(kind('COL MORADA 3 12.50 37.50'), ReceiptRowKind.content);
      // SKU largo que se parece a un RFC, pero con precio con decimales.
      expect(kind('PAN123456ABC BOLILLO 10 2.50 25.00'),
          ReceiptRowKind.content);
      // Tres cifras enteras que juntas suman diez dígitos.
      expect(kind('12 1850 3700 CABLE HDMI'), ReceiptRowKind.content);
    });

    test('la palabra clave RFC manda aunque haya cifras con decimales', () {
      expect(kind('RFC ABC123456XY9 100.00'), ReceiptRowKind.reference);
    });

    test('vacío y renglones sin patrón', () {
      expect(kind(''), ReceiptRowKind.content);
      expect(kind('ABARROTES LÓPEZ S.A. DE C.V.'), ReceiptRowKind.content);
    });
  });

  group('ReceiptRowKind', () {
    test('isNoise saca del grid solo fecha, contacto y referencia', () {
      expect(ReceiptRowKind.date.isNoise, isTrue);
      expect(ReceiptRowKind.contact.isNoise, isTrue);
      expect(ReceiptRowKind.reference.isNoise, isTrue);
      expect(ReceiptRowKind.header.isNoise, isFalse);
      expect(ReceiptRowKind.total.isNoise, isFalse);
      expect(ReceiptRowKind.content.isNoise, isFalse);
    });

    test('normalize quita acentos y conserva la Ñ', () {
      expect(ReceiptRowClassifier.normalize('Descripción año'),
          'DESCRIPCION AÑO');
    });
  });
}
