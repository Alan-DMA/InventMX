import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/ocr_helper.dart';
import '../../inventory/presentation/widgets/column_mapper_row.dart';
import '../data/receipt_line_parser.dart';
import '../domain/receipt_scan.dart';

/// Lo que `OcrColumnMappingScreen` devuelve al cerrarse.
class OcrColumnMappingOutcome {
  const OcrColumnMappingOutcome({
    required this.items,
    required this.mapping,
    this.rescanRequested = false,
  });

  const OcrColumnMappingOutcome.rescan()
      : items = const [],
        mapping = const ReceiptColumnMapping(),
        rescanRequested = true;

  final List<DetectedReceiptItem> items;
  final ReceiptColumnMapping mapping;
  final bool rescanRequested;
}

/// Mapeo interactivo de columnas de la factura escaneada — Tarea 12.2 (QA
/// OCR, decisión de producto de Eduardo).
///
/// El parser heurístico no puede saber qué columna es qué en una factura que
/// nunca ha visto; el dueño sí, mirándola. Esta pantalla muestra la tabla tal
/// como se leyó y le pregunta lo único que la app no puede adivinar: qué
/// columna trae el nombre, la cantidad y el precio. La heurística queda como
/// sugerencia preseleccionada — un toque para confirmar cuando acierta.
///
/// Decisiones de diseño:
///   · Las columnas se etiquetan con una MUESTRA de sus celdas, no con "Col.
///     B": una letra no significa nada en una foto.
///   · El grid marca en color las columnas ya asignadas — el usuario ve el
///     resultado de su elección en los datos, no en un dropdown.
///   · Con proveedor recordado abre ya mapeado y lo dice; confirmar con otro
///     mapeo lo sobrescribe sin diálogo (la confirmación ya es el
///     consentimiento).
///   · Nada se interpreta hasta "Ver productos"; la revisión editable sigue
///     después porque la tabla leída es una lectura, no la verdad.
class OcrColumnMappingScreen extends StatefulWidget {
  const OcrColumnMappingScreen({
    super.key,
    required this.table,
    this.suggested,
    this.remembered,
    this.supplier,
    this.parser = const ReceiptLineParser(),
  });

  final OcrTable table;

  /// Propuesta de la heurística (`ReceiptLineParser.suggestMapping`).
  final ReceiptColumnMapping? suggested;

  /// Mapeo guardado para [supplier] en un escaneo previo — gana sobre
  /// [suggested] si cabe en esta tabla.
  final ReceiptColumnMapping? remembered;

  final String? supplier;
  final ReceiptLineParser parser;

  @override
  State<OcrColumnMappingScreen> createState() => _OcrColumnMappingScreenState();
}

class _OcrColumnMappingScreenState extends State<OcrColumnMappingScreen> {
  late ReceiptColumnMapping _mapping;
  late final bool _startedFromRemembered;

  /// Filas visibles en el grid — suficientes para reconocer la tabla sin
  /// convertir la pantalla en la revisión (que viene después).
  static const _maxPreviewRows = 6;

  @override
  void initState() {
    super.initState();
    final remembered = widget.remembered;
    _startedFromRemembered = remembered != null &&
        remembered.fitsColumnCount(widget.table.columnCount);
    _mapping = _startedFromRemembered
        ? remembered!
        : (widget.suggested ?? const ReceiptColumnMapping());
  }

  List<DetectedReceiptItem> get _items =>
      widget.parser.applyMapping(widget.table, _mapping);

  String? get _missingField {
    if (_mapping.nameCol == null) return 'Nombre';
    if (_mapping.quantityCol == null) return 'Cantidad';
    if (_mapping.priceCol == null) return 'Precio';
    return null;
  }

  void _confirm() {
    Navigator.of(context).pop(
      OcrColumnMappingOutcome(items: _items, mapping: _mapping),
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    final missing = _missingField;

    return Scaffold(
      backgroundColor: AppColors.darkSlate,
      appBar: AppBar(
        backgroundColor: AppColors.darkSlate,
        title: const Text('Revisar columnas'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                children: [
                  const Text(
                    'Toca qué columna trae cada dato. Los datos del proveedor '
                    '(fecha, teléfono, RFC) se dejan fuera; lo demás lo '
                    'corriges después.',
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.4,
                      color: AppColors.onSurfaceMuted,
                    ),
                  ),
                  if (_startedFromRemembered) ...[
                    const SizedBox(height: 12),
                    _RememberedNotice(supplier: widget.supplier!),
                  ],
                  const SizedBox(height: 14),
                  _TablePreview(
                    table: widget.table,
                    mapping: _mapping,
                    maxRows: _maxPreviewRows,
                  ),
                  if (widget.table.ignoredRows.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    _IgnoredRowsNotice(rows: widget.table.ignoredRows),
                  ],
                  const SizedBox(height: 18),
                  _mapperRow(
                    key: const Key('ocrMappingName'),
                    label: 'Nombre',
                    icon: Icons.label_outline_rounded,
                    selected: _mapping.nameCol,
                    onChanged: (c) => setState(
                        () => _mapping = _mapping.copyWith(nameCol: () => c)),
                  ),
                  const SizedBox(height: 10),
                  _mapperRow(
                    key: const Key('ocrMappingQuantity'),
                    label: 'Cantidad',
                    icon: Icons.numbers_rounded,
                    selected: _mapping.quantityCol,
                    onChanged: (c) => setState(() =>
                        _mapping = _mapping.copyWith(quantityCol: () => c)),
                  ),
                  const SizedBox(height: 10),
                  _mapperRow(
                    key: const Key('ocrMappingPrice'),
                    label: 'Precio',
                    icon: Icons.attach_money_rounded,
                    selected: _mapping.priceCol,
                    onChanged: (c) => setState(
                        () => _mapping = _mapping.copyWith(priceCol: () => c)),
                  ),
                ],
              ),
            ),
            _ConfirmBar(
              itemCount: items.length,
              missingField: missing,
              supplierToRemember:
                  _startedFromRemembered ? null : widget.supplier,
              onConfirm: missing == null && items.isNotEmpty ? _confirm : null,
              onRescan: () => Navigator.of(context)
                  .pop(const OcrColumnMappingOutcome.rescan()),
            ),
          ],
        ),
      ),
    );
  }

  Widget _mapperRow({
    required Key key,
    required String label,
    required IconData icon,
    required int? selected,
    required ValueChanged<int?> onChanged,
  }) {
    final columns = [
      for (var c = 0; c < widget.table.columnCount; c++) '$c',
    ];
    return ColumnMapperRow(
      key: key,
      fieldLabel: label,
      fieldIcon: icon,
      isRequired: true,
      columns: columns,
      selectedColumn: selected?.toString(),
      columnLabel: (c) => widget.table.sampleOf(int.parse(c)),
      helperText: _FieldPalette.of(label).legend,
      onChanged: (c) => onChanged(c == null ? null : int.parse(c)),
    );
  }
}

// ---------------------------------------------------------------------------
// Color por campo — el mismo en el grid, en la leyenda del selector y en el
// chip de la columna, para que "verde = nombre" se lea sin explicación.
// ---------------------------------------------------------------------------

enum _FieldPalette {
  name('Nombre', AppColors.emerald, 'verde'),
  quantity('Cantidad', AppColors.skyBlue, 'azul'),
  price('Precio', AppColors.warning, 'ámbar');

  const _FieldPalette(this.label, this.color, this.colorName);

  final String label;
  final Color color;
  final String colorName;

  String get legend => 'Columna en $colorName';

  static _FieldPalette of(String label) =>
      values.firstWhere((f) => f.label == label);
}

// ---------------------------------------------------------------------------
// La tabla tal como se leyó
// ---------------------------------------------------------------------------

class _TablePreview extends StatelessWidget {
  const _TablePreview({
    required this.table,
    required this.mapping,
    required this.maxRows,
  });

  final OcrTable table;
  final ReceiptColumnMapping mapping;
  final int maxRows;

  static const _cellHeight = 34.0;

  List<_FieldPalette> _fieldsOf(int column) => [
        if (mapping.nameCol == column) _FieldPalette.name,
        if (mapping.quantityCol == column) _FieldPalette.quantity,
        if (mapping.priceCol == column) _FieldPalette.price,
      ];

  /// Ancho por columna desde su celda más larga — acotado para que ni un
  /// nombre largo desborde ni un "5" quede ilegible. Una columna asignada
  /// crece hasta caberle sus chips: "Cantidad" no cabe sobre un "6".
  double _widthOf(int column) {
    var longest = 0;
    for (final row in table.cells) {
      longest = math.max(longest, row[column].length);
    }
    final chips = _fieldsOf(column)
        .fold<double>(0, (sum, f) => sum + f.label.length * 9.0 + 26);
    return math.max(longest * 7.2 + 20, chips + 8).clamp(52.0, 240.0);
  }

  @override
  Widget build(BuildContext context) {
    final rows = table.cells.take(maxRows).toList();
    final hidden = table.rowCount - rows.length;
    final widths = [for (var c = 0; c < table.columnCount; c++) _widthOf(c)];

    return Container(
      key: const Key('ocrMappingGrid'),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Chips de campo sobre cada columna asignada.
                Row(
                  children: [
                    for (var c = 0; c < table.columnCount; c++)
                      SizedBox(
                        width: widths[c],
                        height: 30,
                        child: _ColumnChips(fields: _fieldsOf(c)),
                      ),
                  ],
                ),
                for (var r = 0; r < rows.length; r++)
                  Row(
                    children: [
                      for (var c = 0; c < table.columnCount; c++)
                        _Cell(
                          text: rows[r][c],
                          width: widths[c],
                          height: _cellHeight,
                          tint: _fieldsOf(c).firstOrNull?.color,
                          row: r,
                          column: c,
                          zebra: r.isOdd,
                        ),
                    ],
                  ),
              ],
            ),
          ),
          if (hidden > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
              child: Text(
                hidden == 1 ? 'y 1 fila más' : 'y $hidden filas más',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.onSurfaceMuted,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ColumnChips extends StatelessWidget {
  const _ColumnChips({required this.fields});

  final List<_FieldPalette> fields;

  @override
  Widget build(BuildContext context) {
    if (fields.isEmpty) return const SizedBox.shrink();
    // `scaleDown`: si la columna es más angosta que sus chips (fuente del
    // sistema más ancha de lo estimado), se encogen en vez de desbordar.
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Row(
          children: [
            for (final f in fields)
              Container(
                margin: const EdgeInsets.only(right: 4),
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: f.color.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  f.label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: f.color,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({
    required this.text,
    required this.width,
    required this.height,
    required this.tint,
    required this.row,
    required this.column,
    required this.zebra,
  });

  final String text;
  final double width;
  final double height;
  final Color? tint;
  final int row;
  final int column;
  final bool zebra;

  @override
  Widget build(BuildContext context) {
    final background = tint != null
        ? tint!.withValues(alpha: zebra ? 0.14 : 0.10)
        : zebra
            ? AppColors.surfaceVariant.withValues(alpha: 0.5)
            : Colors.transparent;

    return Semantics(
      label: 'fila ${row + 1}, columna ${column + 1}',
      child: Container(
        width: width,
        height: height,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: background,
          border: const Border(
            right: BorderSide(color: AppColors.border, width: 0.5),
          ),
        ),
        child: Text(
          text.isEmpty ? '·' : text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12.5,
            color: text.isEmpty
                ? AppColors.onSurfaceMuted.withValues(alpha: 0.5)
                : tint != null
                    ? AppColors.onSurface
                    : AppColors.onSurfaceMuted,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Aviso de mapeo recordado
// ---------------------------------------------------------------------------

class _RememberedNotice extends StatelessWidget {
  const _RememberedNotice({required this.supplier});

  final String supplier;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('ocrMappingRememberedNotice'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.skyBlue.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child:
                Icon(Icons.history_rounded, size: 16, color: AppColors.skyBlue),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Usando el mapeo de $supplier — cámbialo si esta factura es '
              'distinta.',
              style: const TextStyle(
                fontSize: 12.5,
                height: 1.4,
                color: AppColors.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Renglones que se dejaron fuera
// ---------------------------------------------------------------------------

/// Anuncia lo que `detectTable` descartó por no ser producto — Tarea 12.2,
/// QA de ruido.
///
/// El descarte nunca es silencioso: el usuario ve exactamente qué renglones
/// se ignoraron ("Tel: 55 1234 5678", "Fecha: 12/09/2026") y, si uno era un
/// producto, lo nota aquí y lo agrega a mano en la revisión. Muestra hasta
/// tres y cuenta el resto — no es una lista para leer, es una comprobación
/// de un vistazo.
class _IgnoredRowsNotice extends StatelessWidget {
  const _IgnoredRowsNotice({required this.rows});

  final List<String> rows;

  static const _maxSamples = 3;

  @override
  Widget build(BuildContext context) {
    final samples = rows.take(_maxSamples).toList();
    final rest = rows.length - samples.length;
    final title = rows.length == 1
        ? 'Se dejó fuera 1 renglón que no es producto'
        : 'Se dejaron fuera ${rows.length} renglones que no son productos';

    return Semantics(
      key: const Key('ocrMappingIgnoredNotice'),
      container: true,
      label: '$title: ${rows.join('; ')}',
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 1),
                    child: Icon(Icons.visibility_off_outlined,
                        size: 16, color: AppColors.onSurfaceMuted),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 12.5,
                        height: 1.4,
                        color: AppColors.onSurfaceMuted,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final row in samples) _IgnoredChip(text: row),
                  if (rest > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        rest == 1 ? 'y 1 más' : 'y $rest más',
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: AppColors.onSurfaceMuted,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _IgnoredChip extends StatelessWidget {
  const _IgnoredChip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 220),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 11.5,
            fontFamily: 'monospace',
            color: AppColors.onSurfaceMuted,
            decoration: TextDecoration.lineThrough,
            decorationColor: AppColors.onSurfaceMuted,
          ),
        ),
      ),
    );
  }
}
// ---------------------------------------------------------------------------
// Barra de confirmación
// ---------------------------------------------------------------------------

class _ConfirmBar extends StatelessWidget {
  const _ConfirmBar({
    required this.itemCount,
    required this.missingField,
    required this.supplierToRemember,
    required this.onConfirm,
    required this.onRescan,
  });

  final int itemCount;
  final String? missingField;
  final String? supplierToRemember;
  final VoidCallback? onConfirm;
  final VoidCallback onRescan;

  @override
  Widget build(BuildContext context) {
    final String status;
    if (missingField != null) {
      status = 'Falta elegir $missingField';
    } else if (itemCount == 0) {
      status = 'Con estas columnas no sale ningún producto — revisa el mapeo '
          'o toma otra foto.';
    } else if (supplierToRemember != null) {
      status = 'Al confirmar se recordará para $supplierToRemember.';
    } else {
      status = itemCount == 1
          ? '1 producto listo para revisar'
          : '$itemCount productos listos para revisar';
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            status,
            key: const Key('ocrMappingStatus'),
            style: TextStyle(
              fontSize: 12.5,
              height: 1.4,
              color: onConfirm == null
                  ? AppColors.warning
                  : AppColors.onSurfaceMuted,
            ),
          ),
          const SizedBox(height: 10),
          ElevatedButton.icon(
            key: const Key('ocrMappingConfirm'),
            onPressed: onConfirm,
            icon: const Icon(Icons.arrow_forward_rounded, size: 18),
            label: Text(
              itemCount > 0 && missingField == null
                  ? (itemCount == 1
                      ? 'Ver 1 producto'
                      : 'Ver $itemCount productos')
                  : 'Ver productos',
            ),
          ),
          TextButton(
            key: const Key('ocrMappingRescan'),
            onPressed: onRescan,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.onSurfaceMuted,
              minimumSize: const Size(0, 44),
            ),
            child: const Text('Tomar otra foto'),
          ),
        ],
      ),
    );
  }
}
