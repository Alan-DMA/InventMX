import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_app/core/utils/voice_dictation_helper.dart';

void main() {
  const parser = VoiceDictationParser();

  group('VoiceDictationParser — formato canónico cantidad→nombre→precio', () {
    test('caso básico', () {
      final input = parser.parse('5 unidades de Coca Cola a 20 pesos');

      expect(input.quantity, 5);
      expect(input.name, 'Coca Cola');
      expect(input.priceMxn, 20);
    });

    test('unidad fuera de cualquier lista fija (posicional, no whitelist)', () {
      final input =
          parser.parse('10 kilos de arroz con un costo de 25 pesos');

      expect(input.quantity, 10);
      expect(input.name, 'arroz');
      expect(input.priceMxn, 25);
    });

    test('variante sin palabra-unidad', () {
      final input = parser.parse('8 chocolates a 8 pesos');

      expect(input.quantity, 8);
      expect(input.name, 'chocolates');
      expect(input.priceMxn, 8);
    });

    test('nombre con "de" interno no se corta a la mitad', () {
      final input = parser.parse('3 piezas de pan de dulce a 15 pesos');

      expect(input.quantity, 3);
      expect(input.name, 'pan de dulce');
      expect(input.priceMxn, 15);
    });

    test('nombre con número adentro (caso que rompía al regex viejo Y al '
        'prototipo CRF)', () {
      final input =
          parser.parse('30 tornillos TOR de 35 mm a 10 pesos cada uno');

      expect(input.quantity, 30);
      expect(input.name, 'tornillos TOR de 35 mm');
      expect(input.priceMxn, 10);
    });

    test('plantilla de precio con "precio" en vez de "costo"/"a"', () {
      final input =
          parser.parse('12 unidades de café al precio de 45 pesos');

      expect(input.quantity, 12);
      expect(input.name, 'café');
      expect(input.priceMxn, 45);
    });

    test('sin cantidad — solo nombre y precio', () {
      final input = parser.parse('figuritas de mario a 20 pesos');

      expect(input.quantity, isNull);
      expect(input.name, 'figuritas de mario');
      expect(input.priceMxn, 20);
    });

    test('acepta coma decimal del motor de voz', () {
      expect(
        parser.parse('2 litros de aceite a 45,90 pesos').priceMxn,
        45.90,
      );
    });
  });

  group('VoiceDictationParser — números deletreados por el motor de voz', () {
    test('cantidad deletreada se reconoce como dígito', () {
      final input = parser.parse('veinte unidades de Coca Cola a 20 pesos');

      expect(input.quantity, 20);
      expect(input.name, 'Coca Cola');
      expect(input.priceMxn, 20);
    });

    test('precio deletreado se reconoce como dígito', () {
      final input = parser.parse('5 unidades de Coca Cola a veinte pesos');

      expect(input.quantity, 5);
      expect(input.priceMxn, 20);
    });

    test('cantidad Y precio deletreados en la misma frase', () {
      final input =
          parser.parse('quince piezas de jabón Zote a doce pesos');

      expect(input.quantity, 15);
      expect(input.name, 'jabón Zote');
      expect(input.priceMxn, 12);
    });

    test('número deletreado con coma pegada (transcripción real del motor)',
        () {
      final input =
          parser.parse('veinte, unidades de Coca Cola a 20 pesos');

      expect(input.quantity, 20);
    });

    test('"un"/"una" NO se interpretan como cantidad 1 (son muletilla)', () {
      final input = parser.parse('pan de dulce con un costo de 20 pesos');

      expect(input.quantity, isNull);
      expect(input.name, 'pan de dulce');
      expect(input.priceMxn, 20);
    });
  });

  group('VoiceDictationParser — signo de pesos en vez de la palabra', () {
    test('signo antes del número', () {
      final input = parser.parse('5 unidades de Coca Cola a \$20');

      expect(input.quantity, 5);
      expect(input.name, 'Coca Cola');
      expect(input.priceMxn, 20);
    });

    test('signo después del número (transcripción real del motor)', () {
      final input = parser.parse('5 unidades de Coca Cola a 20\$');

      expect(input.quantity, 5);
      expect(input.name, 'Coca Cola');
      expect(input.priceMxn, 20);
    });

    test('signo con decimales', () {
      expect(parser.parse('jabón zote a \$21.50').priceMxn, 21.50);
    });
  });

  group('VoiceDictationParser — respaldo sin la palabra "pesos"', () {
    test('patrón original SR-09: nombre, precio, cantidad', () {
      final input = parser.parse('Maruchan Pollo, precio 16, 36 piezas');

      // Bajo el nuevo orden canónico "cantidad primero" ya no se enseña
      // este patrón, pero el respaldo _priceKeyword sigue reconociendo el
      // precio correctamente aunque la cantidad quede mal ubicada (36
      // aparece DESPUÉS del precio, fuera del alcance de la extracción
      // posicional cantidad-primero) — documentado como limitación
      // conocida, no como caso soportado.
      expect(input.priceMxn, 16);
    });

    test('acepta precio con decimales sin "pesos"', () {
      expect(parser.parse('jabón zote precio 21.50').priceMxn, 21.50);
    });
  });

  group('VoiceDictationParser — casos vacíos / ambiguos', () {
    test('un dictado vacío no produce ningún campo', () {
      final input = parser.parse('   ');

      expect(input.isEmpty, isTrue);
      expect(input.name, isNull);
    });

    test('sin ningún número reconocible deja cantidad y precio en null', () {
      final input = parser.parse('leche lala');

      expect(input.quantity, isNull);
      expect(input.priceMxn, isNull);
      expect(input.name, 'leche lala');
    });
  });

  group('DictationSegmenter — dictado corrido de varios productos', () {
    const segmenter = DictationSegmenter();

    test('una sola frase sin conector es un solo segmento', () {
      final segments =
          segmenter.segment('5 unidades de Coca Cola a 20 pesos');

      expect(segments, ['5 unidades de Coca Cola a 20 pesos']);
    });

    test('segmenta 2 productos con "también"', () {
      final segments = segmenter.segment(
        '5 unidades de Coca Cola a 20 pesos también 3 piezas de jabón '
        'Zote a 12 pesos',
      );

      expect(segments, [
        '5 unidades de Coca Cola a 20 pesos',
        '3 piezas de jabón Zote a 12 pesos',
      ]);
    });

    test('segmenta 3 productos combinando conectores distintos', () {
      final segments = segmenter.segment(
        '2 kilos de arroz a 25 pesos, y también 1 litro de aceite a 45 '
        'pesos, además 4 piezas de jabón a 12 pesos',
      );

      expect(segments, [
        '2 kilos de arroz a 25 pesos,',
        '1 litro de aceite a 45 pesos,',
        '4 piezas de jabón a 12 pesos',
      ]);
    });

    test('"y también" no se corta como "y" suelto', () {
      final segments = segmenter.segment(
        '5 unidades de Pepsi a 20 pesos y también 3 piezas de Doritos a '
        '15 pesos',
      );

      expect(segments.length, 2);
      expect(segments[1], '3 piezas de Doritos a 15 pesos');
    });

    test('cada segmento se parsea de forma independiente', () {
      final segments = segmenter.segment(
        '5 unidades de Coca Cola a 20 pesos también 3 piezas de jabón '
        'Zote a 12 pesos',
      );
      final parsed = segments.map(parser.parse).toList();

      expect(parsed[0].name, 'Coca Cola');
      expect(parsed[0].quantity, 5);
      expect(parsed[0].priceMxn, 20);

      expect(parsed[1].name, 'jabón Zote');
      expect(parsed[1].quantity, 3);
      expect(parsed[1].priceMxn, 12);
    });

    test('transcript vacío no produce segmentos', () {
      expect(segmenter.segment(''), isEmpty);
      expect(segmenter.segment('   '), isEmpty);
    });
  });
}
