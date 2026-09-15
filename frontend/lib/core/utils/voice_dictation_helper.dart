import 'package:flutter/services.dart';
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

/// Resultado interno de `VoiceDictationParser._findPrice()` — la frase de
/// precio completa y el número en sí pueden empezar en posiciones distintas
/// ("precio 16" matchea desde "precio", el número está más adelante).
class _PriceMatch {
  const _PriceMatch({
    required this.phraseStart,
    required this.numberStart,
    required this.numberText,
  });

  final int phraseStart;
  final int numberStart;
  final String numberText;
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

  // Respaldo cuando el motor de voz transcribe el signo de pesos en vez de
  // la palabra ("$20" o "20$") — encontrado en dictado real, ver bitácora.
  // Dos alternativas porque el motor no es consistente con dónde pone el
  // signo; solo una de las dos captura en cada match.
  static final RegExp _priceWithDollarSign = RegExp(
      r'\$\s*(\d+(?:[.,]\d{1,2})?)|(\d+(?:[.,]\d{1,2})?)\s*\$',
      caseSensitive: false);

  // Respaldo para frases sin "pesos" ni "$" (patrón original SR-09:
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

  // El motor de voz nativo a veces transcribe un número como palabra en vez
  // de dígito ("veinte" en vez de "20") — encontrado en dictado real, ver
  // bitácora. Sin esto, `_anyNumber` (que solo busca `\d+`) nunca lo
  // reconoce y el campo queda vacío aunque el usuario sí haya dicho un
  // número. Deliberadamente SIN "un"/"una": esas palabras ya son muletillas
  // gramaticales frecuentes ("con UN costo de...") — incluirlas como "1"
  // rompería esas frases; alguien que quiere cantidad 1 dice "uno" a secas.
  // Solo números de una palabra (hasta "treinta") — "treinta y cinco"
  // colisionaría con el conector "y" del segmentador.
  static const Map<String, String> _numberWords = {
    'uno': '1', 'dos': '2', 'tres': '3', 'cuatro': '4', 'cinco': '5',
    'seis': '6', 'siete': '7', 'ocho': '8', 'nueve': '9', 'diez': '10',
    'once': '11', 'doce': '12', 'trece': '13', 'catorce': '14',
    'quince': '15', 'dieciséis': '16', 'dieciseis': '16',
    'diecisiete': '17', 'dieciocho': '18', 'diecinueve': '19',
    'veinte': '20', 'veintiuno': '21', 'veintidós': '22',
    'veintidos': '22', 'veintitrés': '23', 'veintitres': '23',
    'veinticuatro': '24', 'veinticinco': '25', 'veintiséis': '26',
    'veintiseis': '26', 'veintisiete': '27', 'veintiocho': '28',
    'veintinueve': '29', 'treinta': '30',
  };

  // `\b` con letras acentuadas no siempre calza bien en Dart/ICU, así que
  // el patrón delimita por espacio/inicio/fin — cubre el caso real (número
  // suelto entre espacios, con o sin coma pegada) sin depender de \b.
  static final RegExp _wordToken = RegExp(r'[a-záéíóúñ]+', caseSensitive: false);

  String _normalizeSpokenNumbers(String text) {
    return text.replaceAllMapped(_wordToken, (m) {
      final replacement = _numberWords[m.group(0)!.toLowerCase()];
      return replacement ?? m.group(0)!;
    });
  }

  /// Precio detectado, ya normalizado: dónde empieza la FRASE completa
  /// (para el límite del nombre) y dónde empieza el DÍGITO en sí (para
  /// desambiguar contra la cantidad) pueden no coincidir — `_priceKeyword`
  /// matchea desde "precio"/"costo", no desde el número.
  _PriceMatch? _findPrice(String text) {
    final nearPesos = _priceNearPesos.firstMatch(text);
    if (nearPesos != null) {
      return _PriceMatch(
        phraseStart: nearPesos.start,
        numberStart: nearPesos.start,
        numberText: nearPesos.group(1)!,
      );
    }

    final dollarSign = _priceWithDollarSign.firstMatch(text);
    if (dollarSign != null) {
      // Grupo 1 = "$20", grupo 2 = "20$" — solo uno de los dos captura.
      final numberText = dollarSign.group(1) ?? dollarSign.group(2)!;
      final numberStart =
          dollarSign.start + dollarSign.group(0)!.indexOf(numberText);
      return _PriceMatch(
        phraseStart: dollarSign.start,
        numberStart: numberStart,
        numberText: numberText,
      );
    }

    final keyword = _priceKeyword.firstMatch(text);
    if (keyword != null) {
      return _PriceMatch(
        phraseStart: keyword.start,
        numberStart:
            keyword.start + keyword.group(0)!.lastIndexOf(keyword.group(1)!),
        numberText: keyword.group(1)!,
      );
    }

    return null;
  }

  DictatedProductInput parse(String transcript) {
    final normalized = _normalizeSpokenNumbers(transcript.trim());
    if (normalized.isEmpty) {
      return DictatedProductInput(transcript: transcript);
    }

    final price = _findPrice(normalized);
    final allNumbers = _anyNumber.allMatches(normalized).toList();

    // Cantidad = primer número de la frase, salvo que sea el mismo número
    // que ya se tomó como precio (frase sin cantidad, solo nombre+precio —
    // caso real encontrado al validar con dictado real, ver bitácora).
    RegExpMatch? qtyMatch;
    for (final n in allNumbers) {
      final isPriceNumber = n.start == price?.numberStart;
      if (!isPriceNumber) {
        qtyMatch = n;
        break;
      }
    }

    final nameStart = qtyMatch?.end ?? 0;
    final nameEnd = price?.phraseStart ?? normalized.length;
    final rawName = nameStart < nameEnd
        ? normalized.substring(nameStart, nameEnd)
        : '';

    return DictatedProductInput(
      transcript: normalized,
      name: _cleanName(rawName),
      priceMxn: price == null
          ? null
          : double.tryParse(price.numberText.replaceAll(',', '.')),
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
  /// cuál es la definitiva. [onError] avisa si el motor cortó por un error
  /// de plataforma (red, timeout del reconocedor, etc.) — sin esto el
  /// caller no tiene forma de saber que la escucha murió en silencio y
  /// quedaría esperando resultados que nunca llegan. [onListening] avisa el
  /// instante en que el micrófono está de verdad captando audio — entre
  /// llamar `listen()` y eso hay un hueco (arranque del reconocedor, tono
  /// del sistema) en el que lo dicho se pierde.
  Future<void> listen({
    required void Function(String transcript, bool isFinal) onResult,
    void Function()? onError,
    void Function()? onListening,
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

  /// Callback de error del `listen()` EN CURSO — se reasigna en cada
  /// llamada porque `SpeechToText.initialize()` solo se corre una vez
  /// (cacheado en `_initialized`) pero `listen()` se llama muchas veces
  /// (una por cada "Volver a grabar" de `DictationModal`).
  void Function()? _currentOnError;

  static const _localeId = 'es_MX';

  @override
  bool get isListening => _speech.isListening;

  @override
  Future<bool> initialize() async {
    if (_initialized) return true;
    _initialized = await _speech.initialize(
      onError: (_) => _currentOnError?.call(),
    );
    return _initialized;
  }

  /// Canal hacia `MainActivity.kt` para silenciar el tono que el
  /// reconocedor de Google emite en cada arranque — el plugin no lo expone.
  static const _audioChannel = MethodChannel('nexus/dictation_audio');
  bool _beepMuted = false;

  @override
  Future<void> listen({
    required void Function(String transcript, bool isFinal) onResult,
    void Function()? onError,
    void Function()? onListening,
  }) async {
    _currentOnError = onError;
    // Tras un resultado final, el plugin sigue marcado como "listening" en
    // Android hasta que vence un temporizador interno de `pauseFor` ms
    // (SpeechToTextPlugin.kt, onEndOfSpeech). Si el usuario toca "Volver a
    // grabar" en esa ventana, Kotlin devuelve `false` y el arranque falla EN
    // SILENCIO — sin error ni callback (bug real: "digo cosas y no
    // transcribe"). `stop()` baja el flag y cancela ese temporizador.
    if (_speech.isListening) await _speech.stop();
    await _setBeepMuted(true);

    // El plugin no notifica `onReadyForSpeech`; el primer evento de nivel de
    // sonido es la señal real de que el micrófono ya está captando.
    var announcedListening = false;
    await _speech.listen(
      onResult: (SpeechRecognitionResult result) =>
          onResult(result.recognizedWords, result.finalResult),
      onSoundLevelChange: (_) {
        if (announcedListening) return;
        announcedListening = true;
        onListening?.call();
      },
      listenOptions: SpeechListenOptions(
        localeId: _localeId,
        listenMode: ListenMode.dictation,
        partialResults: true,
        // false: un error NO debe cancelar la sesión en silencio — se
        // maneja explícitamente vía `onError` para poder reintentar (bug
        // real encontrado en dictado: con `true` y sin `onError` conectado,
        // un error de plataforma mataba la escucha sin que el modal se
        // enterara, sintiéndose como que "se cae sola" sin explicación).
        cancelOnError: false,
        // Un segmento por toque: al callar este tiempo el motor cierra y
        // `DictationModal` queda en "detenido" hasta que el usuario vuelva a
        // grabar — sin reinicio automático (pedido explícito de Eduardo: el
        // bucle de bips no le dejaba pensar qué decir). Es un máximo, no un
        // mínimo: el reconocedor de Google tiene su propio corte interno
        // (~1-2s) que a veces ignora este valor.
        pauseFor: const Duration(seconds: 4),
        listenFor: const Duration(seconds: 55),
      ),
    );
  }

  @override
  Future<void> stop() async {
    await _speech.stop();
    await _setBeepMuted(false);
  }

  @override
  void dispose() {
    if (_speech.isListening) _speech.cancel();
    _setBeepMuted(false);
  }

  Future<void> _setBeepMuted(bool muted) async {
    if (_beepMuted == muted) return;
    _beepMuted = muted;
    try {
      await _audioChannel.invokeMethod<bool>('setRecognizerBeepMuted', muted);
    } on PlatformException {
      // El OEM rechazó tocar el volumen: se oye el tono, nada más.
    } on MissingPluginException {
      // Web / plataformas sin MainActivity propia.
    }
  }
}
