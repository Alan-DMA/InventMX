import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_colors.dart';
import '../domain/purchase_order.dart';
import '../domain/receipt_scan.dart';

/// Lo que `OcrReviewScreen` devuelve al cerrarse.
///
/// Se usa una clase y no un `bool` suelto porque la pantalla tiene dos
/// salidas distintas de "sin líneas": cancelar y pedir otra foto.
class OcrReviewOutcome {
  const OcrReviewOutcome({required this.items, this.rescanRequested = false});

  const OcrReviewOutcome.rescan()
      : items = const [],
        rescanRequested = true;

  final List<PurchaseOrderItem> items;
  final bool rescanRequested;
}

/// Pantalla de revisión interactiva de la factura escaneada — Subtarea 12.2.2.
///
/// El OCR corre en el dispositivo y acierta la mayoría de los renglones, pero
/// nunca todos: una impresión de matriz de punto convierte un `8` en `0` sin
/// avisar. Esta pantalla existe para que ese error se vea **antes** de entrar
/// al costo del inventario, no semanas después en el margen.
///
/// Decisiones de diseño:
///   · Lo primero que se lee es el cuadre contra el total impreso de la
///     factura — es el único checksum honesto disponible sin backend.
///   · Los renglones dudosos o incompletos se marcan con acción ("Revisar",
///     "Falta precio"), no con un número de confianza que no significa nada
///     para quien está de pie frente al repartidor.
///   · Edición directa en la fila: en la escena real se corrigen una o dos
///     cifras con prisa, y un modal por renglón cuesta más toques.
///   · Nada entra a la orden hasta confirmar; el botón de atrás descarta.
class OcrReviewScreen extends StatefulWidget {
  const OcrReviewScreen({super.key, required this.result});

  final ReceiptParseResult result;

  @override
  State<OcrReviewScreen> createState() => _OcrReviewScreenState();
}

class _OcrReviewScreenState extends State<OcrReviewScreen> {
  late final List<_EditableLine> _lines = [
    for (var i = 0; i < widget.result.items.length; i++)
      _EditableLine(id: 'ocr-${i + 1}', source: widget.result.items[i]),
  ];

  @override
  void dispose() {
    for (final line in _lines) {
      line.dispose();
    }
    super.dispose();
  }

  // ── Estado derivado ───────────────────────────────────────────────────────

  List<_EditableLine> get _validLines =>
      _lines.where((l) => l.isComplete).toList();

  double get _total =>
      _validLines.fold<double>(0, (sum, l) => sum + l.subtotal);

  double? get _printedTotal => widget.result.detectedTotalMxn;

  /// Diferencia contra el total impreso — `null` si la factura no traía total
  /// legible, en cuyo caso no hay nada contra qué cuadrar.
  double? get _difference =>
      _printedTotal == null ? null : _total - _printedTotal!;

  bool get _balances {
    final diff = _difference;
    if (diff == null) return false;
    return diff.abs() <= (_printedTotal! * 0.02).clamp(0.5, double.infinity);
  }

  int get _needsAttentionCount =>
      _lines.where((l) => !l.isComplete || l.source.isLowConfidence).length;

  // ── Acciones ──────────────────────────────────────────────────────────────

  void _removeLine(_EditableLine line) {
    setState(() => _lines.remove(line));
    line.dispose();
  }

  void _accept() {
    final items = [for (final line in _validLines) line.toItem()];
    Navigator.of(context).pop(OcrReviewOutcome(items: items));
  }

  @override
  Widget build(BuildContext context) {
    final isEmpty = _lines.isEmpty;

    return Scaffold(
      backgroundColor: AppColors.darkSlate,
      appBar: AppBar(
        backgroundColor: AppColors.darkSlate,
        title: const Text('Revisar factura'),
      ),
      body: SafeArea(
        child: isEmpty
            ? _EmptyScanState(
                rowsRead: widget.result.rowsRead,
                onRescan: () => Navigator.of(context)
                    .pop(const OcrReviewOutcome.rescan()),
                onManual: () => Navigator.of(context).pop(null),
              )
            : Column(
                children: [
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                      children: [
                        _ScanSummary(
                          supplier: widget.result.detectedSupplier,
                          lineCount: _lines.length,
                          needsAttention: _needsAttentionCount,
                        ),
                        const SizedBox(height: 12),
                        _BalanceStrip(
                          total: _total,
                          printedTotal: _printedTotal,
                          difference: _difference,
                          balances: _balances,
                        ),
                        const SizedBox(height: 16),
                        for (final line in _lines) ...[
                          _LineEditor(
                            key: ValueKey(line.id),
                            line: line,
                            onChanged: () => setState(() {}),
                            onRemove: () => _removeLine(line),
                          ),
                          const SizedBox(height: 10),
                        ],
                      ],
                    ),
                  ),
                  _AcceptBar(
                    count: _validLines.length,
                    total: _total,
                    onAccept: _validLines.isEmpty ? null : _accept,
                  ),
                ],
              ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Resumen del escaneo
// ---------------------------------------------------------------------------

class _ScanSummary extends StatelessWidget {
  const _ScanSummary({
    required this.supplier,
    required this.lineCount,
    required this.needsAttention,
  });

  final String? supplier;
  final int lineCount;
  final int needsAttention;

  @override
  Widget build(BuildContext context) {
    final detail = needsAttention == 0
        ? 'Todos los renglones se leyeron completos.'
        : needsAttention == 1
            ? '1 renglón necesita tu revisión.'
            : '$needsAttention renglones necesitan tu revisión.';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          lineCount == 1
              ? '1 producto detectado'
              : '$lineCount productos detectados',
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppColors.onSurface,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          supplier == null ? detail : '$supplier · $detail',
          style: const TextStyle(fontSize: 13, color: AppColors.onSurfaceMuted),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Cuadre contra el total impreso
// ---------------------------------------------------------------------------

class _BalanceStrip extends StatelessWidget {
  const _BalanceStrip({
    required this.total,
    required this.printedTotal,
    required this.difference,
    required this.balances,
  });

  final double total;
  final double? printedTotal;
  final double? difference;
  final bool balances;

  @override
  Widget build(BuildContext context) {
    final (color, icon, message) = switch ((printedTotal, balances)) {
      (null, _) => (
          AppColors.onSurfaceMuted,
          Icons.receipt_long_outlined,
          'No se leyó el total impreso de la factura. Compara tú el importe.',
        ),
      (_, true) => (
          AppColors.emerald,
          Icons.check_circle_outline_rounded,
          'Cuadra con el total impreso de \$${printedTotal!.toStringAsFixed(2)}.',
        ),
      (_, false) => (
          AppColors.warning,
          Icons.error_outline_rounded,
          difference! > 0
              ? 'Sobran \$${difference!.abs().toStringAsFixed(2)} contra el total impreso de \$${printedTotal!.toStringAsFixed(2)}.'
              : 'Faltan \$${difference!.abs().toStringAsFixed(2)} contra el total impreso de \$${printedTotal!.toStringAsFixed(2)}.',
        ),
    };

    // El único momento animado de la pantalla: al corregir una cifra, el
    // cuadre cambia a la vista y confirma que la corrección sirvió.
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      switchInCurve: Curves.easeOut,
      child: Container(
        key: ValueKey(message),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.30)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: TextStyle(fontSize: 13, height: 1.4, color: color),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Fila editable
// ---------------------------------------------------------------------------

class _LineEditor extends StatelessWidget {
  const _LineEditor({
    super.key,
    required this.line,
    required this.onChanged,
    required this.onRemove,
  });

  final _EditableLine line;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final flag = line.attentionLabel;
    final highlighted = flag != null;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 12),
      decoration: BoxDecoration(
        color: highlighted
            ? AppColors.warning.withValues(alpha: 0.06)
            : AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: highlighted
              ? AppColors.warning.withValues(alpha: 0.35)
              : AppColors.border,
        ),
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: TextField(
                  controller: line.nameCtrl,
                  onChanged: (_) => onChanged(),
                  textCapitalization: TextCapitalization.sentences,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.onSurface,
                  ),
                  decoration: const InputDecoration(
                    filled: false,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    hintText: 'Nombre del producto',
                  ),
                ),
              ),
              // 48 dp de área táctil — mínimo de Material en Android.
              SizedBox(
                width: 48,
                height: 48,
                child: IconButton(
                  tooltip: 'Quitar este renglón',
                  onPressed: onRemove,
                  icon: const Icon(Icons.close_rounded,
                      size: 20, color: AppColors.onSurfaceMuted),
                ),
              ),
            ],
          ),
          if (flag != null) ...[
            const SizedBox(height: 2),
            Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  flag,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.warning,
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _NumberField(
                  controller: line.qtyCtrl,
                  label: 'Cantidad',
                  decimal: false,
                  onChanged: onChanged,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _NumberField(
                  controller: line.priceCtrl,
                  label: 'Costo unitario',
                  decimal: true,
                  onChanged: onChanged,
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 84,
                child: Text(
                  line.isComplete
                      ? '\$${line.subtotal.toStringAsFixed(2)}'
                      : '—',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: line.isComplete
                        ? AppColors.onSurface
                        : AppColors.onSurfaceMuted,
                  ),
                ),
              ),
              const SizedBox(width: 6),
            ],
          ),
        ],
      ),
    );
  }
}

class _NumberField extends StatelessWidget {
  const _NumberField({
    required this.controller,
    required this.label,
    required this.decimal,
    required this.onChanged,
  });

  final TextEditingController controller;
  final String label;
  final bool decimal;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: (_) => onChanged(),
      keyboardType: TextInputType.numberWithOptions(decimal: decimal),
      inputFormatters: [
        FilteringTextInputFormatter.allow(
          decimal ? RegExp(r'[\d.]') : RegExp(r'\d'),
        ),
      ],
      style: const TextStyle(
        fontFamily: 'monospace',
        fontSize: 14,
        color: AppColors.onSurface,
      ),
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Barra de confirmación
// ---------------------------------------------------------------------------

class _AcceptBar extends StatelessWidget {
  const _AcceptBar({
    required this.count,
    required this.total,
    required this.onAccept,
  });

  final int count;
  final double total;
  final VoidCallback? onAccept;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Expanded(
                child: Text(
                  'Total a agregar',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.onSurfaceMuted,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '\$${total.toStringAsFixed(2)} MXN',
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.skyBlue,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ElevatedButton.icon(
            onPressed: onAccept,
            icon: const Icon(Icons.playlist_add_rounded, size: 18),
            label: Text(
              count == 1
                  ? 'Agregar 1 producto a la orden'
                  : 'Agregar $count productos a la orden',
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Estado vacío — se leyó la factura pero ningún renglón parecía un producto
// ---------------------------------------------------------------------------

class _EmptyScanState extends StatelessWidget {
  const _EmptyScanState({
    required this.rowsRead,
    required this.onRescan,
    required this.onManual,
  });

  final int rowsRead;
  final VoidCallback onRescan;
  final VoidCallback onManual;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.document_scanner_outlined,
                  size: 42, color: AppColors.warning),
            ),
            const SizedBox(height: 20),
            const Text(
              'No se reconocieron productos',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.onSurface,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              rowsRead == 0
                  ? 'La foto no tenía texto legible. Acerca la cámara a la\ntabla de productos y evita sombras.'
                  : 'Se leyeron $rowsRead renglones, pero ninguno tenía\nproducto, cantidad y precio juntos. Toma la foto\nmás de cerca o captura la compra a mano.',
              style: const TextStyle(
                fontSize: 13,
                height: 1.5,
                color: AppColors.onSurfaceMuted,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
            ElevatedButton.icon(
              onPressed: onRescan,
              icon: const Icon(Icons.photo_camera_outlined, size: 18),
              label: const Text('Tomar otra foto'),
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: onManual,
              child: const Text('Capturar a mano'),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Modelo de edición
// ---------------------------------------------------------------------------

/// Estado editable de un renglón. Los campos que el OCR no leyó quedan
/// **vacíos**, nunca en `0` ni en `1`: un valor inventado que parece leído es
/// peor que un campo en blanco cuando lo que entra es el costo del inventario.
class _EditableLine {
  _EditableLine({required this.id, required this.source})
      : nameCtrl = TextEditingController(text: source.name),
        qtyCtrl =
            TextEditingController(text: source.quantity?.toString() ?? ''),
        priceCtrl = TextEditingController(
          text: source.unitPriceMxn == null
              ? ''
              : source.unitPriceMxn!.toStringAsFixed(2),
        );

  final String id;
  final DetectedReceiptItem source;
  final TextEditingController nameCtrl;
  final TextEditingController qtyCtrl;
  final TextEditingController priceCtrl;

  int get quantity => int.tryParse(qtyCtrl.text.trim()) ?? 0;
  double get unitPrice => double.tryParse(priceCtrl.text.trim()) ?? 0;
  double get subtotal => quantity * unitPrice;

  bool get isComplete =>
      nameCtrl.text.trim().isNotEmpty && quantity > 0 && unitPrice > 0;

  /// Qué hacer con esta fila, en lugar de un número de confianza que no le
  /// dice nada a quien está frente al repartidor.
  String? get attentionLabel {
    if (nameCtrl.text.trim().isEmpty) return 'Falta el nombre';
    if (quantity <= 0) return 'Falta la cantidad';
    if (unitPrice <= 0) return 'Falta el costo';
    if (source.isLowConfidence) return 'Revisar contra la factura';
    return null;
  }

  PurchaseOrderItem toItem() => PurchaseOrderItem(
        productId: id,
        productName: nameCtrl.text.trim(),
        quantity: quantity,
        unitCostMxn: unitPrice,
      );

  void dispose() {
    nameCtrl.dispose();
    qtyCtrl.dispose();
    priceCtrl.dispose();
  }
}
