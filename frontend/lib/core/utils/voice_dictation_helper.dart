import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Los 3 campos vitales extraídos de un dictado.
///
/// Cualquiera puede venir en `null`: el parser rellena lo que reconoce y deja
/// el resto para que el usuario lo complete a mano — nunca inventa un valor.
class DictatedProductInput {
  const DictatedProductInput({
    required this.transcript,
    this.name,
    this.priceMxn,
    this.quantity,
  });

  final String transcript;
  final String? name;
  final double? priceMxn;
  final int? quantity;

  bool get isEmpty => name == null && priceMxn == null && quantity == null;

  @override
  String toString() =>
      'DictatedProductInput(name: $name, price: $priceMxn, qty: $quantity)';
}

/// Familias de conectores que marcan "aquí empieza un producto nuevo" en un
/// dictado corrido de varios productos — ver
/// `DictationSegmenter.segment()`.
///
/// Ordenados de más a menos específicos: un `RegExp` con alternancia `|`
/// toma la primera opción que calce en cada posición, no la más larga — si
/// "y" fuera la primera de la lista, "y también" nunca llegaría a
/// reconocerse completo, se cortaría en el "y" suelto.
const kDictationConnectors = [
  'y también',
  'también',
  'y de una vez',
  'y de paso',
  'además',
  'y',
];

/// Copy exacta que se le muestra al usuario en el modal de dictado — mismo
/// vocabulario de conectores que `kDictationConnectors`, para que lo que se
/// enseña y lo que el segmentador reconoce nunca queden desincronizados.
const kDictationFormatExample =
    '5 unidades de Coca Cola a 20 pesos, también 3 piezas de jabón Zote a 12 pesos';

/// Divide un dictado corrido en un segmento de texto por producto,
/// cortando en cualquiera de `kDictationConnectors`.
///
/// Reemplaza el enfoque descartado de segmentación por modelo (CRFsuite,
/// ver `prototypes/dictation_crf/` y la bitácora) por reglas: confiable
/// dentro del formato que se le enseña al usuario en el modal, con margen
/// de maniobra en CÓMO lo dice (6 conectores válidos) sin perder la
/// estructura fija que hace la extracción confiable.
class DictationSegmenter {
  const DictationSegmenter();

  static final RegExp _connectorPattern = RegExp(
    r'(?:^|\s)(' +
        kDictationConnectors.map(RegExp.escape).join('|') +
        r')(?=\s|$)',
    caseSensitive: false,
  );

  List<String> segment(String transcript) {
    final normalized = transcript.trim();
    if (normalized.isEmpty) return const [];

    final matches = _connectorPattern.allMatches(normalized).toList();
    if (matches.isEmpty) return [normalized];

    final segments = <String>[];
    var cursor = 0;
    for (final match in matches) {
      final chunk = normalized.substring(cursor, match.start).trim();
      if (chunk.isNotEmpty) segments.add(chunk);
      cursor = match.end;
    }
    final last = normalized.substring(cursor).trim();
    if (last.isNotEmpty) segments.add(last);

    return segments;
  }
}

/// Convierte un dictado en los 3 campos vitales (SR-09).
///
/// Formato enseñado al usuario (modal de dictado, Tarea 12.2.3 —
/// iteración post-exploración CRF): **cantidad → nombre → precio**, ej.
/// *"5 unidades de Coca Cola a 20 pesos"*. Se descartó el orden original
/// "nombre primero" (Maruchan Pollo, precio 16, 36 piezas) porque no
/// generaliza a dictado de varios productos de corrido sin ambigüedad.
///
/// Extracción **posicional**, no por lista fija de palabras-unidad: la
/// cantidad es el primer número de la frase y el precio el número junto a
/// "pesos" (o tras una frase de precio conocida) — así "10 kilos", "8
/// chocolates" o cualquier unidad no prevista funcionan igual, sin
/// necesidad de enumerarlas todas. El nombre es lo que queda entre ambos,
/// recortando muletillas SOLO en los bordes (nunca en medio, para no
/// romper nombres que legítimamente contienen esas palabras, ej.
/// "pan de dulce").
class VoiceDictationParser {
  const VoiceDictationParser();

  static final RegExp _anyNumber = RegExp(r'\d+(?:[.,]\d{1,2})?');

  // Precio junto a "pesos" — cubre todas las plantillas de frase de precio
  // ("con un costo de X pesos", "a X pesos", "por un precio de X pesos"...)
  // porque todas comparten la misma cola "<número> pesos", sin necesidad de
  // enumerar cada plantilla por separado.
  static final RegExp _priceNearPesos =
      RegExp(r'(\d+(?:[.,]\d{1,2})?)\s*pesos', caseSensitive: false);

  // Respaldo para frases sin la palabra "pesos" (patrón original SR-09:
  // "precio 16").
  static final RegExp _priceKeyword = RegExp(
      r'precios?\s+(?:de\s+)?\$?\s*(\d+(?:[.,]\d{1,2})?)',
      caseSensitive: false);

  // Muletillas recortadas SOLO en los bordes del nombre — unión de unidades
  // y preposiciones de precio ya validadas con dictado real (ver
  // prototypes/dictation_crf/generate_dataset.py, UNIT_SINGULAR/PRODUCTS).
  static final List<String> _edgeFillers = [
    'unidades', 'unidad', 'piezas', 'pieza', 'pzas', 'pzs', 'pza', 'pz',
    'kilos', 'kilo', 'litros', 'litro', 'paquetes', 'paquete',
    'bolsas', 'bolsa', 'cajas', 'caja', 'latas', 'lata',
    'botellas', 'botella', 'frascos', 'frasco',
    'cajetillas', 'cajetilla', 'botes', 'bote',
    'de', 'del', 'con', 'un', 'una', 'al', 'la', 'el', 'a', 'por',
    'costo', 'precio', 'cuestan', 'cuesta', 'cada', 'uno', 'unos', 'unas',
    'mexicano', 'mexicanos',
  ];

  DictatedProductInput parse(String transcript) {
    final normalized = transcript.trim();
    if (normalized.isEmpty) {
      return DictatedProductInput(transcript: transcript);
    }

    final priceMatch = _priceNearPesos.firstMatch(normalized) ??
        _priceKeyword.firstMatch(normalized);

    final allNumbers = _anyNumber.allMatches(normalized).toList();
    // Posición del DÍGITO del precio, no del match completo — `_priceKeyword`
    // matchea desde "precio"/"costo", no desde el número, así que comparar
    // contra `priceMatch.start` (match completo) nunca coincidiría con la
    // posición real del número y la cantidad tomaría el número de precio
    // por error. `Match` en Dart no expone la posición de un grupo
    // capturado directamente, así que se ubica dentro del texto del match
    // completo (el grupo del número es lo último que matchea en ambos
    // patrones de precio, `lastIndexOf` es seguro aquí).
    final priceNumberStart = priceMatch == null
        ? null
        : priceMatch.start +
            priceMatch.group(0)!.lastIndexOf(priceMatch.group(1)!);

    // Cantidad = primer número de la frase, salvo que sea el mismo número
    // que ya se tomó como precio (frase sin cantidad, solo nombre+precio —
    // caso real encontrado al validar con dictado real, ver bitácora).
    RegExpMatch? qtyMatch;
    for (final n in allNumbers) {
      final isPriceNumber = n.start == priceNumberStart;
      if (!isPriceNumber) {
        qtyMatch = n;
        break;
      }
    }

    final nameStart = qtyMatch?.end ?? 0;
    final nameEnd = priceMatch?.start ?? normalized.length;
    final rawName = nameStart < nameEnd
        ? normalized.substring(nameStart, nameEnd)
        : '';

    return DictatedProductInput(
      transcript: normalized,
      name: _cleanName(rawName),
      priceMxn: priceMatch == null
          ? null
          : double.tryParse(priceMatch.group(1)!.replaceAll(',', '.')),
      quantity: qtyMatch == null
          ? null
          : int.tryParse(qtyMatch.group(0)!.split('.').first),
    );
  }

  String? _cleanName(String raw) {
    var tokens = raw
        .replaceAll(RegExp(r'[,;]+'), ' ')
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .toList();

    bool isFiller(String t) => _edgeFillers.contains(t.toLowerCase());

    while (tokens.isNotEmpty && isFiller(tokens.first)) {
      tokens.removeAt(0);
    }
    while (tokens.isNotEmpty && isFiller(tokens.last)) {
      tokens.removeLast();
    }

    final cleaned = tokens.join(' ').trim();
    return cleaned.isEmpty ? null : cleaned;
  }
}

/// Contrato del dictado — permite inyectar un doble en tests (el motor de voz
/// vive detrás de un canal de plataforma y no corre en `flutter test`).
abstract interface class VoiceDictationService {
  /// Prepara el motor y pide el permiso de micrófono. `false` si el equipo no
  /// tiene reconocimiento de voz o el usuario negó el permiso.
  Future<bool> initialize();

  /// Escucha hasta que el usuario calla o llama a [stop].
  ///
  /// [onResult] recibe transcripciones parciales y la final; [isFinal] indica
  /// cuál es la definitiva.
  Future<void> listen({
    required void Function(String transcript, bool isFinal) onResult,
  });

  Future<void> stop();

  bool get isListening;

  void dispose();
}

/// Implementación real: motor de voz nativo del sistema operativo
/// (Android SpeechRecognizer / Web Speech API), sin APIs de pago —
/// Constitución Art. VII (7.7).
class NativeVoiceDictationService implements VoiceDictationService {
  NativeVoiceDictationService({SpeechToText? speech})
      : _speech = speech ?? SpeechToText();

  final SpeechToText _speech;
  bool _initialized = false;

  static const _localeId = 'es_MX';

  @override
  bool get isListening => _speech.isListening;

  @override
  Future<bool> initialize() async {
    if (_initialized) return true;
    _initialized = await _speech.initialize();
    return _initialized;
  }

  @override
  Future<void> listen({
    required void Function(String transcript, bool isFinal) onResult,
  }) async {
    await _speech.listen(
      onResult: (SpeechRecognitionResult result) =>
          onResult(result.recognizedWords, result.finalResult),
      listenOptions: SpeechListenOptions(
        localeId: _localeId,
        listenMode: ListenMode.dictation,
        partialResults: true,
        cancelOnError: true,
        // Un dictado de varios productos toma más que una sola línea —
        // ventana más amplia que la original (Tarea 12.2.3 solo cubría un
        // producto a la vez). El corte por silencio sigue en 3s.
        pauseFor: const Duration(seconds: 3),
        listenFor: const Duration(seconds: 45),
      ),
    );
  }

  @override
  Future<void> stop() => _speech.stop();

  @override
  void dispose() {
    if (_speech.isListening) _speech.cancel();
  }
}
