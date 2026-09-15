/// Qué es un renglón leído por el OCR antes de intentar convertirlo en
/// producto.
///
/// El OCR no distingue "tabla de productos" de "hoja": lee el RFC, el
/// teléfono del repartidor, la fecha y la dirección con el mismo entusiasmo
/// que los renglones que sí importan. Tarea 12.2 (QA de ruido, Sep 2026):
/// antes de esta clase el único filtro eran palabras exactas de cabecera, y
/// `Tel. 55 1234 5678` salía como producto "Tel." · cantidad 55 · precio 1234.
enum ReceiptRowKind {
  /// Nada dice que no sea producto — entra a la tabla y al mapeo.
  content,

  /// Cabecera de la tabla ("CANTIDAD DESCRIPCIÓN PRECIO"). Se queda en el
  /// grid porque ayuda al usuario a reconocer las columnas, pero nunca es
  /// producto.
  header,

  /// Renglón del total impreso — checksum de la revisión, nunca producto.
  total,

  /// Fecha u hora de emisión.
  date,

  /// Teléfono, correo, sitio web o dirección.
  contact,

  /// RFC, folio, número de pedido/cliente/vendedor, etc.
  reference,
}

extension ReceiptRowKindX on ReceiptRowKind {
  /// Renglones que se sacan del grid y se anuncian como "ignorados": son
  /// datos del proveedor o del documento, no de la mercancía.
  bool get isNoise =>
      this == ReceiptRowKind.date ||
      this == ReceiptRowKind.contact ||
      this == ReceiptRowKind.reference;

  /// Renglones que no pueden ser producto, se muestren o no en el grid.
  bool get isNeverProduct => this != ReceiptRowKind.content;

  /// Nombre corto para la UI y los tests.
  String get label => switch (this) {
        ReceiptRowKind.content => 'producto',
        ReceiptRowKind.header => 'cabecera',
        ReceiptRowKind.total => 'total',
        ReceiptRowKind.date => 'fecha',
        ReceiptRowKind.contact => 'contacto',
        ReceiptRowKind.reference => 'referencia',
      };
}

/// Clasificador de renglones por patrón — puro, sin Flutter.
///
/// Reglas de diseño:
///   · Los patrones son **estrictos** y todo descarte se anuncia en la UI. Un
///     falso positivo silencioso (borrar "TARJETA TELCEL 100" porque parece
///     teléfono) es peor que un falso negativo visible (una fecha que el
///     usuario quita con un toque en la revisión).
///   · La evidencia de producto gana: un renglón con nombre alfabético y un
///     importe con decimales o `$` no se descarta por parecer contacto o
///     referencia. Una fecha sí descarta siempre — ningún producto es una
///     fecha.
///   · Se trabaja sobre el texto del renglón completo (las celdas unidas),
///     porque "Tel." y el número suelen llegar como celdas separadas.
class ReceiptRowClassifier {
  const ReceiptRowClassifier();

  // ── Fecha / hora ──────────────────────────────────────────────────────────

  static final RegExp _numericDate =
      RegExp(r'(?<!\d)\d{1,2}[/.-]\d{1,2}[/.-](?:\d{2}|\d{4})(?!\d)');
  static final RegExp _isoDate = RegExp(r'(?<!\d)\d{4}-\d{2}-\d{2}(?!\d)');

  /// "3 de septiembre de 2026", "3 SEP 2026", "3/sep/26". Se exige año de 4
  /// cifras o el conector "de": sin eso "6 MAYONESA 45.00" haría match.
  static final RegExp _spelledDate = RegExp(
    r'(?<!\w)\d{1,2}\s*(?:DE\s+|/|-)?'
    r'(?:ENE(?:RO)?|FEB(?:RERO)?|MAR(?:ZO)?|ABR(?:IL)?|MAY(?:O)?|JUN(?:IO)?|'
    r'JUL(?:IO)?|AGO(?:STO)?|SEP(?:T|TIEMBRE)?|SET(?:IEMBRE)?|OCT(?:UBRE)?|'
    r'NOV(?:IEMBRE)?|DIC(?:IEMBRE)?)\b\.?\s*'
    r'(?:DEL?\s+\d{2,4}|/\d{2,4}|-\d{2,4}|\d{4})(?!\d)',
  );
  static final RegExp _timeOfDay = RegExp(
    r'(?<!\d)\d{1,2}:\d{2}(?::\d{2})?\s*(?:AM|PM|HRS|HORAS|H)?\b',
  );
  static final RegExp _dateKeyword =
      RegExp(r'^(?:FECHA|HORA|EMISION|EMITIDO|EXPEDICION|VENCE|VENCIMIENTO)\b');

  // ── Contacto ──────────────────────────────────────────────────────────────

  static final RegExp _contactKeyword = RegExp(
    r'\b(?:TEL|TELS|TELEFONO|TELEFONOS|CEL|CELULAR|WHATSAPP|WHATS|WA|'
    r'LLAMANOS|CONTACTO|E-?MAIL|CORREO|WEB|PAGINA|SITIO)\b',
  );
  static final RegExp _phoneNumber = RegExp(
    r'(?<!\d)(?:\+?52[\s-]?)?\(?\d{2,3}\)?[\s-]?\d{3,4}[\s-]?\d{4}(?!\d)',
  );
  static final RegExp _tenDigits = RegExp(r'(?<!\d)\d{10}(?!\d)');
  static final RegExp _email = RegExp(r'\S+@\S+\.[A-Z]{2,}');
  static final RegExp _url = RegExp(
    r'\b(?:WWW\.|HTTPS?:|[A-Z0-9-]+\.(?:COM|MX|NET|ORG|COM\.MX))\b',
  );
  static final RegExp _addressKeyword = RegExp(
    r'\b(?:CALLE|AV|AVE|AVENIDA|BLVD|BOULEVARD|CALZ|CALZADA|COL|COLONIA|'
    r'C\.?P|CP|ALCALDIA|DELEGACION|MUNICIPIO|CIUDAD|CD|EDO|ESTADO|'
    r'MEXICO|CDMX|INT|EXT|NUM)\b\.?\s*(?:\d|[A-Z]{3,})',
  );
  static final RegExp _postalCode = RegExp(r'\bC\.?\s?P\.?\s*\d{5}\b');

  // ── Referencia del documento ──────────────────────────────────────────────

  static final RegExp _rfcKeyword = RegExp(r'\b(?:RFC|CURP)\b');
  static final RegExp _rfc = RegExp(r'\b[A-ZÑ&]{3,4}\d{6}[A-Z0-9]{2,3}\b');
  static final RegExp _curp =
      RegExp(r'\b[A-Z]{4}\d{6}[HM][A-Z]{5}[A-Z0-9]\d\b');
  static final RegExp _referenceKeyword = RegExp(
    r'^(?:RFC|CURP|FOLIO|NO|NUM|NUMERO|SERIE|PEDIDO|ORDEN|CLIENTE|VENDEDOR|'
    r'RUTA|SUCURSAL|CAJA|CAJERO|TICKET|FACTURA|REMISION|NOTA|CUENTA|'
    r'CLABE|REFERENCIA|REF|ATENDIO|LE ATENDIO|AGENTE|ZONA|ALMACEN)\b',
  );

  // ── Cabecera / total / evidencia de producto ──────────────────────────────

  /// Palabras que solas ya delatan una cabecera o un pie ("IVA", "FIRMA").
  static const _strongHeaderWords = {
    'CANTIDAD',
    'CANT',
    'DESCRIPCION',
    'CONCEPTO',
    'UNIDAD',
    'PRECIO',
    'IMPORTE',
    'SUBTOTAL',
    'IVA',
    'RFC',
    'FOLIO',
    'FACTURA',
    'REMISION',
    'FECHA',
    'CLIENTE',
    'PROVEEDOR',
    'FIRMA',
    'GRACIAS',
    'SUCURSAL',
    'VENDEDOR',
    'RUTA',
  };

  /// Palabras que solo cuentan acompañadas de otra de cabecera: "ARTICULO"
  /// o "PRODUCTO" también son nombres genéricos de renglón.
  static const _weakHeaderWords = {
    'ARTICULO',
    'PRODUCTO',
    'UNIDADES',
    'P.U',
    'PU',
    'CODIGO',
    'CLAVE',
    'DTO',
    'DESCUENTO',
    'TOTAL',
  };

  static final RegExp _hasLetters = RegExp(r'[A-Z]');
  static final RegExp _decimalAmount = RegExp(r'(?<!\d)\d+[.,]\d{2}(?!\d)');
  static final RegExp _currency = RegExp(r'\$\s*\d');

  ReceiptRowKind classify(String rowText) {
    final text = normalize(rowText);
    if (text.isEmpty) return ReceiptRowKind.content;

    if (_looksLikeTotal(text)) return ReceiptRowKind.total;

    // Una fecha nunca es producto, tenga o no cifras al lado.
    if (_dateKeyword.hasMatch(text) ||
        _numericDate.hasMatch(text) ||
        _isoDate.hasMatch(text) ||
        _spelledDate.hasMatch(text) ||
        (_timeOfDay.hasMatch(text) && !_hasProductEvidence(text))) {
      return ReceiptRowKind.date;
    }

    final productEvidence = _hasProductEvidence(text);

    // Contacto y referencia antes que cabecera: "Ruta 12" o "Folio A-123"
    // son datos del documento y deben anunciarse como ignorados, no quedar
    // mudos en el grid como si fueran cabecera de tabla.
    if (_looksLikeContact(text, productEvidence)) {
      return ReceiptRowKind.contact;
    }
    if (_looksLikeReference(text, productEvidence)) {
      return ReceiptRowKind.reference;
    }
    if (_isHeader(text)) return ReceiptRowKind.header;
    return ReceiptRowKind.content;
  }

  /// Atajo para `detectTable`: renglones que no deben construir la tabla.
  bool isNoise(String rowText) => classify(rowText).isNoise;

  /// Mayúsculas y sin acentos en vocales (la Ñ se conserva: forma parte del
  /// RFC). Público para que el parser y los tests normalicen igual.
  static String normalize(String raw) => raw
      .trim()
      .toUpperCase()
      .replaceAll(RegExp('[ÁÀÄÂ]'), 'A')
      .replaceAll(RegExp('[ÉÈËÊ]'), 'E')
      .replaceAll(RegExp('[ÍÌÏÎ]'), 'I')
      .replaceAll(RegExp('[ÓÒÖÔ]'), 'O')
      .replaceAll(RegExp('[ÚÙÜÛ]'), 'U');

  // ── Reglas ────────────────────────────────────────────────────────────────

  bool _looksLikeTotal(String text) =>
      text.contains('TOTAL') && !text.contains('SUBTOTAL');

  /// Dos o más palabras de cabecera, o una sola palabra fuerte y ninguna
  /// otra palabra.
  bool _isHeader(String text) {
    final tokens = text.split(RegExp(r'[\s:]+')).map((t) {
      return t.replaceAll(RegExp(r'\.+$'), '');
    }).toList();
    final strong = tokens.where(_strongHeaderWords.contains).length;
    final weak = tokens.where(_weakHeaderWords.contains).length;
    if (strong + weak >= 2) return true;
    final wordy =
        tokens.where((t) => t.isNotEmpty && _hasLetters.hasMatch(t)).length;
    return strong == 1 && wordy == 1;
  }

  /// Nombre con letras + un importe con decimales o `$`: así se ve un renglón
  /// de producto en cualquier formato de factura mexicana.
  bool _hasProductEvidence(String text) {
    final letters = _hasLetters.allMatches(text).length;
    return letters >= 3 &&
        (_decimalAmount.hasMatch(text) || _currency.hasMatch(text));
  }

  bool _looksLikeContact(String text, bool productEvidence) {
    if (_email.hasMatch(text) || _url.hasMatch(text)) return true;
    if (_postalCode.hasMatch(text)) return true;
    if (productEvidence) return false;

    if (_contactKeyword.hasMatch(text)) {
      // "Tel." solo, o "Tel. 55 1234 5678": ambos son contacto.
      return true;
    }
    if (_addressKeyword.hasMatch(text)) return true;

    // Número telefónico sin palabra clave: solo si el renglón es
    // prácticamente eso ("55 1234 5678", "(55) 1234-5678", "5512345678").
    if (_tenDigits.hasMatch(text)) return true;
    final phone = _phoneNumber.firstMatch(text);
    if (phone == null) return false;
    final rest = text.replaceRange(phone.start, phone.end, '').trim();
    return _hasLetters.allMatches(rest).length < 3;
  }

  bool _looksLikeReference(String text, bool productEvidence) {
    // La palabra clave manda: "RFC: XAXX010101000" es referencia aunque el
    // OCR haya pegado un importe al lado.
    if (_rfcKeyword.hasMatch(text)) return true;
    if (productEvidence) return false;
    // El patrón suelto de RFC/CURP se parece a un SKU largo — solo cuenta
    // cuando el renglón no tiene evidencia de producto.
    if (_rfc.hasMatch(text) || _curp.hasMatch(text)) return true;
    return _referenceKeyword.hasMatch(text);
  }
}
