import 'dart:math' as math;
import 'dart:ui';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// Una línea de texto reconocida por el OCR, con su caja delimitadora.
///
/// La caja es lo que permite reconstruir las filas visuales de una factura:
/// ML Kit devuelve bloques por zona de la imagen, así que la cantidad, la
/// descripción y el importe de un mismo renglón suelen llegar en bloques
/// distintos y solo la geometría los vuelve a unir.
class OcrLine {
  const OcrLine({
    required this.text,
    required this.boundingBox,
    this.confidence,
    this.angle,
    this.direction = const Offset(1, 0),
  });

  final String text;
  final Rect boundingBox;
  final double? confidence;

  /// Rotación de la línea en grados según ML Kit — sirve para saber si la
  /// hoja está chueca antes de disparar la foto. Puede venir nula.
  final double? angle;

  /// Vector unitario de lectura del texto en coordenadas de imagen. (1, 0)
  /// para texto derecho; (0, 1) si la hoja quedó girada y el texto se lee de
  /// arriba hacia abajo. Se calcula desde los `cornerPoints` de ML Kit, que
  /// van en orden horario desde la esquina superior-izquierda DEL TEXTO — por
  /// eso no tiene la ambigüedad de signo de `angle`.
  final Offset direction;

  double get centerY => boundingBox.center.dy;
  double get left => boundingBox.left;
  double get height => boundingBox.height;

  @override
  String toString() => 'OcrLine("$text", $boundingBox)';
}

/// Contrato de reconocimiento de texto — permite inyectar un doble en tests
/// (ML Kit vive detrás de un canal de plataforma y no corre en `flutter test`).
abstract interface class OcrTextRecognizer {
  /// Extrae las líneas de texto de la imagen en [imagePath].
  Future<List<OcrLine>> recognizeLines(String imagePath);

  Future<void> dispose();
}

/// Implementación real: Google ML Kit Text Recognition, 100% en el dispositivo.
///
/// Constitución Art. II (2.1) y Art. VII (7.7): sin APIs cloud de visión de
/// pago; el procesamiento ocurre en el procesador del teléfono, offline y a
/// costo $0 de servidor.
class MlKitOcrTextRecognizer implements OcrTextRecognizer {
  MlKitOcrTextRecognizer({TextRecognizer? recognizer})
      : _recognizer =
            recognizer ?? TextRecognizer(script: TextRecognitionScript.latin);

  final TextRecognizer _recognizer;

  @override
  Future<List<OcrLine>> recognizeLines(String imagePath) async {
    final recognized =
        await _recognizer.processImage(InputImage.fromFilePath(imagePath));

    return [
      for (final block in recognized.blocks)
        for (final line in block.lines)
          OcrLine(
            text: line.text,
            boundingBox: line.boundingBox,
            confidence: line.confidence,
            angle: line.angle,
            direction: _readingDirection(line.cornerPoints),
          ),
    ];
  }

  static Offset _readingDirection(List<math.Point<int>> corners) {
    if (corners.length < 2) return const Offset(1, 0);
    final dx = (corners[1].x - corners[0].x).toDouble();
    final dy = (corners[1].y - corners[0].y).toDouble();
    final length = math.sqrt(dx * dx + dy * dy);
    if (length < 1e-6) return const Offset(1, 0);
    return Offset(dx / length, dy / length);
  }

  @override
  Future<void> dispose() => _recognizer.close();
}

// ---------------------------------------------------------------------------
// Geometría invariante a rotación
// ---------------------------------------------------------------------------
//
// Una foto tomada con el teléfono en horizontal (o con la rotación automática
// apagada) entrega la hoja girada 90° dentro de la imagen. ML Kit sí lee ese
// texto, pero agrupar por la Y de la imagen convierte cada COLUMNA visual en
// un "renglón" (bug real: "11 renglones leídos, ninguno con producto,
// cantidad y precio juntos"). Todo el agrupado trabaja proyectado sobre la
// dirección de lectura dominante: "a lo largo" ordena los tokens de un
// renglón, "a través" separa renglones — igual para una hoja derecha, girada
// a cualquier lado o de cabeza.

class _Projected {
  const _Projected(
      this.line, this.along, this.across, this.extent, this.thickness);

  final OcrLine line;

  /// Coordenada del centro a lo largo de la lectura (izquierda → derecha de
  /// la hoja).
  final double along;

  /// Coordenada del centro perpendicular a la lectura (arriba → abajo de la
  /// hoja).
  final double across;

  /// Largo del texto a lo largo de la lectura.
  final double extent;

  /// Alto del renglón (perpendicular a la lectura).
  final double thickness;

  double get alongStart => along - extent / 2;
  double get alongEnd => along + extent / 2;
}

Offset _dominantDirection(List<OcrLine> lines) {
  var dx = 0.0;
  var dy = 0.0;
  for (final line in lines) {
    dx += line.direction.dx;
    dy += line.direction.dy;
  }
  final length = math.sqrt(dx * dx + dy * dy);
  if (length < 1e-6) return const Offset(1, 0);
  return Offset(dx / length, dy / length);
}

List<_Projected> _project(List<OcrLine> lines) {
  final d = _dominantDirection(lines);
  // Perpendicular que apunta "hacia abajo de la hoja" para cualquier giro.
  final n = Offset(-d.dy, d.dx);
  return [
    for (final line in lines)
      _Projected(
        line,
        line.boundingBox.center.dx * d.dx + line.boundingBox.center.dy * d.dy,
        line.boundingBox.center.dx * n.dx + line.boundingBox.center.dy * n.dy,
        (line.boundingBox.width * d.dx).abs() +
            (line.boundingBox.height * d.dy).abs(),
        (line.boundingBox.width * d.dy).abs() +
            (line.boundingBox.height * d.dx).abs(),
      ),
  ];
}

/// Filas visuales, de arriba hacia abajo de la hoja, cada una ordenada en
/// sentido de lectura.
List<List<_Projected>> _groupRows(
  List<OcrLine> lines, {
  required double toleranceFactor,
}) {
  final nonEmpty = lines.where((l) => l.text.trim().isNotEmpty).toList();
  if (nonEmpty.isEmpty) return const [];

  final sorted = _project(nonEmpty)
    ..sort((a, b) => a.across.compareTo(b.across));

  final rows = <List<_Projected>>[];
  var current = <_Projected>[sorted.first];
  for (final cell in sorted.skip(1)) {
    final reference = current.last;
    final tolerance = reference.thickness * toleranceFactor;
    if ((cell.across - reference.across).abs() <= tolerance) {
      current.add(cell);
    } else {
      rows.add(current);
      current = [cell];
    }
  }
  rows.add(current);

  for (final row in rows) {
    row.sort((a, b) => a.along.compareTo(b.along));
  }
  return rows;
}

/// Reagrupa las líneas sueltas del OCR en filas visuales.
///
/// Dos líneas pertenecen a la misma fila si sus centros (perpendiculares a la
/// lectura) están más cerca que [toleranceFactor] veces la altura de la
/// línea — la tolerancia es relativa (no un número fijo de píxeles) para que
/// funcione igual con una foto de 1080p que con una de 4K.
List<String> groupLinesIntoRows(
  List<OcrLine> lines, {
  double toleranceFactor = 0.6,
}) {
  return [
    for (final row in _groupRows(lines, toleranceFactor: toleranceFactor))
      row.map((c) => c.line.text.trim()).join(' '),
  ];
}

/// Tabla reconstruida desde el OCR: filas visuales × columnas visuales, con
/// el texto crudo de cada celda (`''` donde la fila no tiene celda en esa
/// columna). Es lo que el usuario ve en la pantalla de mapeo para decidir
/// qué columna es cada dato.
class OcrTable {
  const OcrTable({
    required this.cells,
    this.ignoredRows = const [],
    List<String>? rowTexts,
  }) : _rowTexts = rowTexts;

  const OcrTable.empty()
      : cells = const [],
        ignoredRows = const [],
        _rowTexts = null;

  /// `cells[fila][columna]`, rectangular.
  final List<List<String>> cells;

  /// Renglones que `detectTable` dejó fuera del grid por no ser de la tabla
  /// (fecha, teléfono, RFC, dirección…), en orden de lectura. Se muestran al
  /// usuario para que sepa qué se descartó — Tarea 12.2, QA de ruido.
  final List<String> ignoredRows;

  final List<String>? _rowTexts;

  int get rowCount => cells.length;
  int get columnCount => cells.isEmpty ? 0 : cells.first.length;
  bool get isEmpty => cells.isEmpty || columnCount == 0;

  /// Texto de cada renglón de la hoja en sentido de lectura, **incluidos los
  /// ignorados** en su posición original — es lo que ve el parser por
  /// renglones (proveedor y total impreso viven justamente en la cabecera y
  /// el pie que el grid no muestra).
  List<String> get rowTexts =>
      _rowTexts ??
      [
        for (final row in cells) row.where((c) => c.isNotEmpty).join(' '),
      ].where((r) => r.isNotEmpty).toList();

  /// Muestra de una columna para etiquetarla ante el usuario: las primeras
  /// celdas no vacías, porque "Col. B" no significa nada en una foto.
  String sampleOf(int column, {int max = 3}) => [
        for (final row in cells)
          if (column < row.length && row[column].isNotEmpty) row[column],
      ].take(max).join(', ');
}

class _Column {
  _Column(this.start, this.end);

  double start;
  double end;
  final cells = <int, String>{};

  double get extent => end - start;
  double get center => (start + end) / 2;
}

/// Fracción del ancho de la hoja a partir de la cual una celda se considera
/// "de ancho completo" (título, dirección, leyenda del pie) y no debe
/// definir columnas.
const double _kSpanningCellFraction = 0.45;

/// Reconstruye la tabla de la factura: filas por [groupLinesIntoRows] y
/// columnas por solapamiento de intervalos a lo largo de la lectura.
///
/// Cada celda entra a la columna existente con la que más se solapa
/// (relativo a su propio largo) y que aún no tenga celda de esa fila; si no
/// se solapa con ninguna, abre columna nueva. Los números impresos van
/// alineados a la derecha y los nombres a la izquierda, así que comparar
/// intervalos completos — no solo el inicio — es lo que mantiene "5" y "150"
/// en la misma columna.
///
/// Dos defensas contra el ruido de la hoja (Tarea 12.2, QA de ruido):
///   · [ignoreRow] recibe el texto de cada renglón; los que devuelvan `true`
///     no construyen la tabla y salen en [OcrTable.ignoredRows].
///   · Las celdas que abarcan casi todo el ancho de la hoja (nombre del
///     proveedor, dirección, "GRACIAS POR SU COMPRA") se colocan en una
///     segunda pasada, sobre las columnas que ya definieron las celdas
///     normales, sin ensancharlas — antes una sola cabecera ancha estiraba
///     una columna al ancho completo y el resto de celdas caía dentro.
OcrTable detectTable(
  List<OcrLine> lines, {
  double toleranceFactor = 0.6,
  bool Function(String rowText)? ignoreRow,
}) {
  final allRows = _groupRows(lines, toleranceFactor: toleranceFactor);
  if (allRows.isEmpty) return const OcrTable.empty();

  final rowTexts = <String>[];
  final ignored = <String>[];
  final rows = <List<_Projected>>[];
  for (final row in allRows) {
    final text = row.map((c) => c.line.text.trim()).join(' ');
    rowTexts.add(text);
    if (ignoreRow != null && ignoreRow(text)) {
      ignored.add(text);
    } else {
      rows.add(row);
    }
  }
  if (rows.isEmpty) {
    return OcrTable(cells: const [], ignoredRows: ignored, rowTexts: rowTexts);
  }

  var sheetStart = double.infinity;
  var sheetEnd = double.negativeInfinity;
  for (final row in rows) {
    for (final cell in row) {
      sheetStart = math.min(sheetStart, cell.alongStart);
      sheetEnd = math.max(sheetEnd, cell.alongEnd);
    }
  }
  final spanningExtent = (sheetEnd - sheetStart) * _kSpanningCellFraction;

  final columns = <_Column>[];

  _Column? bestColumnFor(_Projected cell, int r) {
    _Column? best;
    var bestRatio = 0.0;
    for (final col in columns) {
      if (col.cells.containsKey(r)) continue;
      final overlap = math.min(cell.alongEnd, col.end) -
          math.max(cell.alongStart, col.start);
      if (overlap <= 0) continue;
      final ratio = overlap /
          math.min(cell.extent, col.extent).clamp(1e-6, double.infinity);
      if (ratio > bestRatio) {
        bestRatio = ratio;
        best = col;
      }
    }
    return best;
  }

  // Pasada 1: celdas normales definen y ensanchan columnas.
  final deferred = <(int, _Projected)>[];
  for (var r = 0; r < rows.length; r++) {
    for (final cell in rows[r]) {
      if (cell.extent >= spanningExtent) {
        deferred.add((r, cell));
        continue;
      }
      var best = bestColumnFor(cell, r);
      if (best == null) {
        best = _Column(cell.alongStart, cell.alongEnd);
        columns.add(best);
      } else {
        best.start = math.min(best.start, cell.alongStart);
        best.end = math.max(best.end, cell.alongEnd);
      }
      best.cells[r] = cell.line.text.trim();
    }
  }

  // Pasada 2: celdas anchas se acomodan sin mover las columnas.
  for (final (r, cell) in deferred) {
    var best = bestColumnFor(cell, r);
    if (best == null) {
      best = _Column(cell.alongStart, cell.alongEnd);
      columns.add(best);
    }
    best.cells[r] = cell.line.text.trim();
  }
  columns.sort((a, b) => a.center.compareTo(b.center));

  return OcrTable(
    cells: [
      for (var r = 0; r < rows.length; r++)
        [for (final col in columns) col.cells[r] ?? ''],
    ],
    ignoredRows: ignored,
    rowTexts: rowTexts,
  );
}
