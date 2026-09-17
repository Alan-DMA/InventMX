/// Modelo de dominio — Resultado de consulta EAN en el motor de dos niveles.
///
/// Anclado a `SeedProductLookup` y `EanSource` de docs/api/components.yaml
/// (`GET /inventory/lookup-ean/{barcode}`, docs/api/inventory.yaml).
///
/// Privacidad sagrada (Constitución Art. VII, 7.5): este modelo NUNCA lleva
/// precio, costo, existencias ni identidad de los comercios que aportaron el
/// nombre. Solo el nombre canónico, la categoría y cuántos comercios coinciden.
library;

// ---------------------------------------------------------------------------
// Origen de la coincidencia
// ---------------------------------------------------------------------------

enum EanSource {
  /// Tier 1 — catálogo semilla oficial GS1 México.
  seedCatalog,

  /// Tier 2 — verificado por consenso automático de ≥ 3 comercios.
  communityVerified,

  /// No existe en ningún catálogo: el tendero lo registra desde cero.
  notFound;

  static EanSource fromApi(String? raw) {
    switch (raw?.toUpperCase()) {
      case 'SEED_CATALOG':
        return EanSource.seedCatalog;
      case 'COMMUNITY_VERIFIED':
        return EanSource.communityVerified;
      default:
        return EanSource.notFound;
    }
  }

  String get apiValue => switch (this) {
        EanSource.seedCatalog => 'SEED_CATALOG',
        EanSource.communityVerified => 'COMMUNITY_VERIFIED',
        EanSource.notFound => 'NOT_FOUND',
      };
}

// ---------------------------------------------------------------------------
// Resultado
// ---------------------------------------------------------------------------

class EanLookupResult {
  const EanLookupResult({
    required this.barcode,
    required this.source,
    this.name,
    this.category,
    this.confidenceScore,
  });

  /// Resultado "no encontrado" — el único que puede construirse sin nombre.
  const EanLookupResult.notFound(this.barcode)
      : source = EanSource.notFound,
        name = null,
        category = null,
        confidenceScore = null;

  final String barcode;
  final EanSource source;

  /// Nombre canónico sugerido. Null solo cuando `source == notFound`.
  final String? name;

  /// Categoría sugerida. Puede venir vacía aunque haya nombre.
  final String? category;

  /// Cuántos comercios independientes coinciden. Solo en Tier 2, mínimo 3.
  /// Se muestra como cifra ("3 comercios coinciden"), nunca como estrellas
  /// ni porcentaje — no es una calificación, es un conteo.
  final int? confidenceScore;

  bool get isFound => source != EanSource.notFound && (name?.isNotEmpty ?? false);

  factory EanLookupResult.fromJson(Map<dynamic, dynamic> json) {
    final source = EanSource.fromApi(json['source']?.toString());
    final rawScore = json['confidence_score'];
    return EanLookupResult(
      barcode: (json['barcode'] ?? '').toString(),
      source: source,
      name: json['name']?.toString(),
      category: json['category']?.toString(),
      confidenceScore: rawScore is num ? rawScore.toInt() : int.tryParse('$rawScore'),
    );
  }

  Map<String, dynamic> toJson() => {
        'barcode': barcode,
        'name': name,
        'category': category,
        'source': source.apiValue,
        'confidence_score': confidenceScore,
      };
}

/// ¿El texto parece un código de barras estándar (EAN-8/13, UPC-A, GTIN-14)?
///
/// Solo dígitos, entre 8 y 14. Es la señal que dispara la consulta al motor
/// de dos niveles desde el buscador del POS: un nombre tecleado nunca la
/// dispara, un escaneo (lector de teclado o cámara) siempre.
bool looksLikeBarcode(String text) {
  final t = text.trim();
  if (t.length < 8 || t.length > 14) return false;
  return RegExp(r'^\d+$').hasMatch(t);
}
