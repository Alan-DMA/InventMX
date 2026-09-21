import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_app/features/inventory/domain/product.dart';
import 'package:nexus_app/features/purchases/data/product_name_matcher.dart';

Product _product(String id, String name) => Product(
      id: id,
      sku: id.toUpperCase(),
      name: name,
      category: 'General',
      priceMxn: 20,
      costMxn: 10,
      stock: 5,
      reservedStock: 0,
      availableStock: 5,
      isActive: true,
      isOnCatalog: false,
      createdAt: DateTime(2026, 1, 1),
    );

void main() {
  const matcher = ProductNameMatcher();

  group('normalize', () {
    test('minúsculas, sin acentos, espacios/puntuación colapsados', () {
      expect(matcher.normalize('  Coca-Cola   600ML  '), 'coca cola 600ml');
      expect(matcher.normalize('Jabón Zote®'), 'jabon zote');
      expect(matcher.normalize('Piña Colada'), 'pina colada');
      expect(matcher.normalize('Ñame'), 'name');
    });

    test('dos formas del mismo nombre normalizan igual', () {
      expect(
        matcher.normalize('COCA COLA 600ML'),
        matcher.normalize('  Cóca-Colá,  600ml  '),
      );
    });
  });

  group('match — coincidencia exacta', () {
    test('normaliza antes de comparar (mayúsculas, acentos, espacios)', () {
      final catalog = [_product('p1', 'Coca Cola 600ml')];
      final result = matcher.match('COCA   COLA 600ML', catalog);

      expect(result.hasExact, isTrue);
      expect(result.exact!.id, 'p1');
      expect(result.hasCandidates, isFalse);
    });

    test('sin match exacto no marca exact aunque el texto sea parecido', () {
      final catalog = [_product('p1', 'Coca Cola 600ml')];
      final result = matcher.match('Coca Cola 1L', catalog);

      expect(result.hasExact, isFalse);
    });
  });

  group('match — candidatos por similitud', () {
    test('nombres muy parecidos se ofrecen como candidatos, no como exact', () {
      final catalog = [
        _product('p1', 'Refresco Manzanita Sol'),
        _product('p2', 'Jabon Zote'),
      ];
      final result = matcher.match('Refresco Manzanita', catalog);

      expect(result.hasExact, isFalse);
      expect(result.candidates.map((p) => p.id), contains('p1'));
      expect(result.candidates.map((p) => p.id), isNot(contains('p2')));
    });

    test('nunca ofrece más de 3 candidatos', () {
      final catalog = [
        _product('p1', 'Refresco Manzana Verde'),
        _product('p2', 'Refresco Manzanita'),
        _product('p3', 'Refresco de Manzana'),
        _product('p4', 'Refresco Manzanilla Extra'),
      ];
      final result = matcher.match('Refresco Manzana', catalog);

      expect(result.candidates.length, lessThanOrEqualTo(3));
      expect(result.candidates, isNotEmpty);
    });

    test('el candidato más parecido va primero', () {
      final catalog = [
        _product('p1', 'Jabon Zote'), // muy distinto — descartado por umbral
        _product('p2', 'Refresco de Uva'), // comparte menos con el target
        _product('p3', 'Refresco Manzanita'), // comparte casi todo
      ];
      final result = matcher.match('Refresco Manzana', catalog);

      expect(result.candidates.first.id, 'p3');
    });

    test('sin candidatos por debajo del umbral — nunca engancha algo distinto',
        () {
      final catalog = [_product('p1', 'Jabon Zote')];
      final result = matcher.match('Producto Rarisimo XY123', catalog);

      expect(result.hasExact, isFalse);
      expect(result.hasCandidates, isFalse);
    });

    test('texto vacío no produce match ni candidatos', () {
      final catalog = [_product('p1', 'Jabon Zote')];
      final result = matcher.match('   ', catalog);

      expect(result.hasExact, isFalse);
      expect(result.hasCandidates, isFalse);
    });

    test('catálogo vacío nunca produce match ni candidatos', () {
      final result = matcher.match('Coca Cola 600ml', const []);

      expect(result.hasExact, isFalse);
      expect(result.hasCandidates, isFalse);
    });
  });
}
