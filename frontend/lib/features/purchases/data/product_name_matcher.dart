import '../../inventory/domain/product.dart';

/// Resultado de comparar un nombre (de OCR o captura manual) contra el
/// catálogo — ver `ProductNameMatcher.match`.
class ProductMatch {
  const ProductMatch({this.exact, this.candidates = const []});

  /// Coincidencia exacta normalizada — se resuelve sola, sin acción del
  /// usuario.
  final Product? exact;

  /// Hasta [ProductNameMatcher.maxCandidates] productos parecidos — nunca se
  /// auto-asignan, sólo se ofrecen como sugerencia tocable.
  final List<Product> candidates;

  bool get hasExact => exact != null;
  bool get hasCandidates => candidates.isNotEmpty;
}

/// Normaliza y compara nombres de producto contra `inventoryProvider.products`
/// — usado por la captura manual (`ProductPickerField`) y por la revisión de
/// factura escaneada (`OcrReviewScreen`) para resolver renglones a un
/// `product_id` real sin que el usuario tenga que buscarlo a mano cada vez.
///
/// Sin dependencia externa (Constitución Art. IV, Bootstrap): normalización
/// manual de acentos + similitud por bigramas de caracteres (coeficiente de
/// Dice), ambas suficientes para nombres cortos de producto de abarrotes.
class ProductNameMatcher {
  const ProductNameMatcher({this.candidateThreshold = 0.5, this.maxCandidates = 3});

  /// Similitud mínima (0..1) para ofrecer un nombre como sugerencia —
  /// calibrado para no enganchar por error productos distintos con nombres
  /// cortos parecidos (decisión explícita de Eduardo: prefiere "a crear" de
  /// más antes que una sugerencia incorrecta).
  final double candidateThreshold;

  final int maxCandidates;

  static const Map<String, String> _accents = {
    'á': 'a',
    'é': 'e',
    'í': 'i',
    'ó': 'o',
    'ú': 'u',
    'ü': 'u',
    'ñ': 'n',
  };

  /// Minúsculas, sin acentos, espacios/puntuación colapsados a un solo
  /// espacio y recortados — dos formas del mismo nombre normalizan igual
  /// aunque difieran en mayúsculas, acentos o espacios extra.
  String normalize(String raw) {
    var text = raw.toLowerCase();
    for (final entry in _accents.entries) {
      text = text.replaceAll(entry.key, entry.value);
    }
    text = text.replaceAll(RegExp(r'[^a-z0-9\s]'), ' ');
    text = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return text;
  }

  /// Compara [rawName] contra [catalog]. Devuelve una coincidencia exacta si
  /// existe; si no, hasta [maxCandidates] sugerencias por similitud.
  ProductMatch match(String rawName, List<Product> catalog) {
    final target = normalize(rawName);
    if (target.isEmpty) return const ProductMatch();

    for (final product in catalog) {
      if (normalize(product.name) == target) {
        return ProductMatch(exact: product);
      }
    }

    final scored = <MapEntry<Product, double>>[
      for (final product in catalog)
        MapEntry(product, _similarity(target, normalize(product.name))),
    ]..sort((a, b) => b.value.compareTo(a.value));

    final candidates = scored
        .where((entry) => entry.value >= candidateThreshold)
        .take(maxCandidates)
        .map((entry) => entry.key)
        .toList();

    return ProductMatch(candidates: candidates);
  }

  /// Coeficiente de Dice sobre bigramas de caracteres — 0 si algún texto no
  /// llega a dos caracteres (sin bigramas que comparar).
  double _similarity(String a, String b) {
    final bigramsA = _bigrams(a);
    final bigramsB = List<String>.from(_bigrams(b));
    if (bigramsA.isEmpty || bigramsB.isEmpty) return 0;

    var overlap = 0;
    for (final bigram in bigramsA) {
      final i = bigramsB.indexOf(bigram);
      if (i != -1) {
        overlap++;
        bigramsB.removeAt(i);
      }
    }
    return (2 * overlap) / (bigramsA.length + bigramsB.length);
  }

  List<String> _bigrams(String text) {
    final noSpaces = text.replaceAll(' ', '');
    if (noSpaces.length < 2) return const [];
    return [
      for (var i = 0; i < noSpaces.length - 1; i++) noSpaces.substring(i, i + 2),
    ];
  }
}
