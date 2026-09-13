import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/ocr_helper.dart';
import '../../../core/utils/voice_dictation_helper.dart';
import '../domain/purchase_order.dart';
import '../domain/supplier.dart';
import 'ocr_review_screen.dart';
import 'purchases_provider.dart';
import 'widgets/purchase_items_summary_table.dart';

/// `PurchaseCreateScreen` — Subtarea 11.2.1 (Pantalla de Registro de Compras
/// y Entradas).
///
/// Ajuste de QA de Eduardo: un solo formulario de captura (no un bloque
/// repetido por línea) + botón "Agregar" + tabla de resumen con altura
/// acotada — mismo patrón ya usado en el resto de la app para listas que
/// pueden crecer (`PurchaseItemsSummaryTable`, ver `CashMovementsListBox`).
///
/// Decisión de alcance: el nombre del producto es un campo libre (no un
/// buscador contra `inventoryProvider`) — mantiene la pantalla dentro de las
/// 2h estimadas; una integración con el catálogo existente queda para una
/// iteración posterior si Eduardo la pide en QA.
class PurchaseCreateScreen extends ConsumerStatefulWidget {
  const PurchaseCreateScreen({super.key});

  @override
  ConsumerState<PurchaseCreateScreen> createState() =>
      _PurchaseCreateScreenState();
}

class _PurchaseCreateScreenState extends ConsumerState<PurchaseCreateScreen> {
  Supplier? _supplier;
  DateTime? _expectedDeliveryDate;
  final _notesCtrl = TextEditingController();

  // Formulario único de captura de línea — se limpia después de "Agregar".
  final _nameCtrl = TextEditingController();
  final _qtyCtrl = TextEditingController(text: '1');
  final _costCtrl = TextEditingController();

  final List<PurchaseOrderItem> _items = [];
  int _lineCounter = 0;

  /// ID de la línea recién agregada — dispara el destello de confirmación en
  /// `PurchaseItemsSummaryTable` (ajuste de QA: la acción de "Agregar" no se
  /// notaba sin retroalimentación visual).
  String? _justAddedId;

  bool _isSaving = false;
  String? _error;

  /// Escaneo de factura (12.2.1 / 12.2.2) y dictado (12.2.3).
  bool _isScanning = false;
  bool _isListening = false;
  String _partialTranscript = '';

  @override
  void dispose() {
    _notesCtrl.dispose();
    _nameCtrl.dispose();
    _qtyCtrl.dispose();
    _costCtrl.dispose();
    super.dispose();
  }

  // ── Formulario de captura de línea ──────────────────────────────────────

  int get _entryQuantity => int.tryParse(_qtyCtrl.text) ?? 0;
  double get _entryUnitCost =>
      double.tryParse(_costCtrl.text.replaceAll(',', '')) ?? 0;
  double get _entrySubtotal => _entryQuantity * _entryUnitCost;

  bool get _canAddEntry =>
      _nameCtrl.text.trim().isNotEmpty &&
      _entryQuantity > 0 &&
      _entryUnitCost > 0;

  void _addEntry() {
    if (!_canAddEntry) return;
    final id = 'draft-${++_lineCounter}';
    setState(() {
      // Al inicio — misma convención UX que `CashMovementsNotifier`: el
      // ítem tocado por la acción aparece primero, sin depender de que el
      // usuario haga scroll para notar que la acción tuvo efecto.
      _items.insert(
        0,
        PurchaseOrderItem(
          productId: id,
          productName: _nameCtrl.text.trim(),
          quantity: _entryQuantity,
          unitCostMxn: _entryUnitCost,
        ),
      );
      _justAddedId = id;
      _nameCtrl.clear();
      _qtyCtrl.text = '1';
      _costCtrl.clear();
    });
    // Cierra el teclado — ajuste de QA: con el teclado numérico abierto la
    // fila recién agregada (arriba de la tabla) quedaba tapada y el
    // destello de confirmación no se veía. Se solicita el foco sobre un
    // `FocusNode` desechable (patrón estándar para "quitar el foco de lo
    // que sea que lo tenga") en vez de `unfocus()`, que solo libera el
    // scope y puede dejar el campo de texto hijo con el foco intacto.
    FocusScope.of(context).requestFocus(FocusNode());
  }

  void _removeItem(PurchaseOrderItem item) =>
      setState(() => _items.remove(item));

  // ── Escaneo de factura — Subtareas 12.2.1 y 12.2.2 ──────────────────────

  /// Foto → ML Kit (on-device) → parser → pantalla de revisión.
  ///
  /// La lectura corre en el procesador del teléfono: ni la imagen ni el texto
  /// salen del dispositivo (Constitución Art. IV, 4.2).
  Future<void> _scanReceipt() async {
    if (_isScanning) return;

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    final String? photoPath;
    try {
      photoPath = await ref.read(receiptPhotoSourceProvider).capture(context);
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('No se pudo abrir la cámara. Revisa el permiso en '
              'los ajustes del teléfono.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    if (photoPath == null) return; // El usuario canceló la captura.

    setState(() => _isScanning = true);
    try {
      final lines =
          await ref.read(ocrTextRecognizerProvider).recognizeLines(photoPath);
      final parsed = await ref
          .read(purchasesRepositoryProvider)
          .parseReceiptRows(groupLinesIntoRows(lines));

      if (!mounted) return;
      setState(() => _isScanning = false);

      final outcome = await navigator.push<OcrReviewOutcome>(
        MaterialPageRoute(builder: (_) => OcrReviewScreen(result: parsed)),
      );
      if (!mounted || outcome == null) return;

      if (outcome.rescanRequested) {
        await _scanReceipt();
        return;
      }
      if (outcome.items.isEmpty) return;

      setState(() {
        for (final item in outcome.items) {
          _items.insert(
            0,
            PurchaseOrderItem(
              productId: 'draft-${++_lineCounter}',
              productName: item.productName,
              quantity: item.quantity,
              unitCostMxn: item.unitCostMxn,
            ),
          );
        }
        _justAddedId = _items.first.productId;
      });
      messenger.showSnackBar(
        SnackBar(
          content: Text(outcome.items.length == 1
              ? '1 producto agregado desde la factura'
              : '${outcome.items.length} productos agregados desde la factura'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _isScanning = false);
      messenger.showSnackBar(
        const SnackBar(
          content: Text('No se pudo leer la factura. Vuelve a tomar la foto '
              'con más luz y de más cerca.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  // ── Dictado de voz — Subtarea 12.2.3 (SR-09) ───────────────────────────

  /// Escucha una frase del tipo *"Maruchan Pollo, precio 16, 36 piezas"* y
  /// rellena los campos que reconozca. Lo que no entiende lo deja en blanco:
  /// nunca completa un costo a ciegas.
  Future<void> _toggleDictation() async {
    final service = ref.read(voiceDictationServiceProvider);
    final messenger = ScaffoldMessenger.of(context);

    if (_isListening) {
      await service.stop();
      if (mounted) setState(() => _isListening = false);
      return;
    }

    final ready = await service.initialize();
    if (!mounted) return;
    if (!ready) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('El dictado no está disponible. Revisa el permiso de '
              'micrófono en los ajustes del teléfono.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() {
      _isListening = true;
      _partialTranscript = '';
    });

    await service.listen(
      onResult: (transcript, isFinal) {
        if (!mounted) return;
        setState(() => _partialTranscript = transcript);
        if (isFinal) _applyDictation(transcript, messenger);
      },
    );
  }

  void _applyDictation(String transcript, ScaffoldMessengerState messenger) {
    final parsed = const VoiceDictationParser().parse(transcript);

    setState(() {
      _isListening = false;
      _partialTranscript = '';
      if (parsed.name != null) _nameCtrl.text = parsed.name!;
      if (parsed.quantity != null) _qtyCtrl.text = parsed.quantity!.toString();
      if (parsed.priceMxn != null) {
        _costCtrl.text = parsed.priceMxn!.toStringAsFixed(2);
      }
    });

    if (parsed.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('No se entendió. Prueba así: "Maruchan pollo, '
              'precio 16, 36 piezas".'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  double get _total => _items.fold<double>(0, (sum, i) => sum + i.subtotalMxn);

  bool get _isValid => _supplier != null && _items.isNotEmpty;

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _expectedDeliveryDate ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime(2030),
    );
    if (picked != null) setState(() => _expectedDeliveryDate = picked);
  }

  Future<void> _submit() async {
    if (!_isValid || _isSaving) return;
    setState(() {
      _isSaving = true;
      _error = null;
    });

    try {
      await ref.read(purchaseOrdersProvider.notifier).createOrder(
            supplierId: _supplier!.id,
            items: _items,
            expectedDeliveryDate: _expectedDeliveryDate,
            notes:
                _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
          );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() {
        _isSaving = false;
        _error = 'No se pudo crear la orden de compra.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final suppliers = ref.watch(suppliersProvider).suppliers;

    return Scaffold(
      backgroundColor: AppColors.darkSlate,
      appBar: AppBar(
        backgroundColor: AppColors.darkSlate,
        title: const Text('Nueva orden de compra'),
        actions: [
          // Escaneo OCR de la factura del repartidor — Tarea 12.2.
          IconButton(
            key: const Key('scanReceiptButton'),
            tooltip: 'Escanear factura',
            onPressed: _isScanning ? null : _scanReceipt,
            icon: _isScanning
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.2, color: AppColors.skyBlue),
                  )
                : const Icon(Icons.document_scanner_outlined,
                    color: AppColors.skyBlue),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
        children: [
          _sectionLabel('Proveedor  *'),
          DropdownButtonFormField<Supplier>(
            initialValue: _supplier,
            isExpanded: true,
            items: suppliers
                .map((s) => DropdownMenuItem(value: s, child: Text(s.name)))
                .toList(),
            onChanged: (s) => setState(() => _supplier = s),
            hint: const Text('Selecciona un proveedor'),
            decoration: const InputDecoration(
                prefixIcon: Icon(Icons.local_shipping_outlined, size: 18)),
          ),
          const SizedBox(height: 16),
          _sectionLabel('Fecha esperada de entrega'),
          InkWell(
            onTap: _pickDate,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  const Icon(Icons.event_outlined,
                      size: 18, color: AppColors.onSurfaceMuted),
                  const SizedBox(width: 10),
                  Text(
                    _expectedDeliveryDate == null
                        ? 'Sin definir'
                        : '${_expectedDeliveryDate!.day}/${_expectedDeliveryDate!.month}/${_expectedDeliveryDate!.year}',
                    style: const TextStyle(
                        color: AppColors.onSurface, fontSize: 14),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          _sectionLabel('Agregar producto'),
          _buildEntryForm(),
          const SizedBox(height: 16),
          _sectionLabel('Productos en esta orden  *'),
          PurchaseItemsSummaryTable(
            items: _items,
            onRemove: _removeItem,
            justAddedId: _justAddedId,
          ),
          const SizedBox(height: 16),
          _sectionLabel('Notas'),
          TextFormField(
            controller: _notesCtrl,
            maxLines: 2,
            style: const TextStyle(color: AppColors.onSurface, fontSize: 14),
            decoration: const InputDecoration(hintText: 'Opcional'),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Total',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.onSurfaceMuted)),
                Text(
                  '\$${_total.toStringAsFixed(2)} MXN',
                  style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppColors.skyBlue),
                ),
              ],
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border:
                    Border.all(color: AppColors.error.withValues(alpha: 0.3)),
              ),
              child: Text(_error!,
                  style: const TextStyle(fontSize: 13, color: AppColors.error)),
            ),
          ],
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _isValid && !_isSaving ? _submit : null,
            child: _isSaving
                ? const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.5, color: AppColors.darkSlate),
                  )
                : const Text('Crear orden de compra'),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text,
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppColors.onSurface)),
      );

  // ── Formulario único de captura de línea + botón Agregar ────────────────

  Widget _buildEntryForm() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  key: const Key('purchaseEntryNameField'),
                  controller: _nameCtrl,
                  onChanged: (_) => setState(() {}),
                  style: const TextStyle(
                      color: AppColors.onSurface, fontSize: 14),
                  decoration: const InputDecoration(
                      hintText: 'Nombre del producto', isDense: true),
                ),
              ),
              const SizedBox(width: 8),
              _DictationButton(
                isListening: _isListening,
                onPressed: _toggleDictation,
              ),
            ],
          ),
          if (_isListening) ...[
            const SizedBox(height: 8),
            _ListeningHint(transcript: _partialTranscript),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  key: const Key('purchaseEntryQtyField'),
                  controller: _qtyCtrl,
                  onChanged: (_) => setState(() {}),
                  keyboardType: TextInputType.number,
                  style:
                      const TextStyle(color: AppColors.onSurface, fontSize: 14),
                  decoration: const InputDecoration(
                      labelText: 'Cantidad', isDense: true),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextFormField(
                  key: const Key('purchaseEntryCostField'),
                  controller: _costCtrl,
                  onChanged: (_) => setState(() {}),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  style:
                      const TextStyle(color: AppColors.onSurface, fontSize: 14),
                  decoration: const InputDecoration(
                      labelText: 'Costo unitario', isDense: true),
                ),
              ),
            ],
          ),
          if (_entrySubtotal > 0) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                'Subtotal: \$${_entrySubtotal.toStringAsFixed(2)}',
                style: const TextStyle(
                    fontSize: 12, color: AppColors.onSurfaceMuted),
              ),
            ),
          ],
          const SizedBox(height: 10),
          // Botón sólido de ancho completo — mismo tamaño que el resto de
          // los CTA de la app (hereda `AppTheme.elevatedButtonTheme`); ajuste
          // de QA: antes era un botón compacto en línea con el subtotal.
          ElevatedButton.icon(
            onPressed: _canAddEntry ? _addEntry : null,
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Agregar'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Dictado de voz — Subtarea 12.2.3
// ---------------------------------------------------------------------------

/// Botón de micrófono del formulario de captura.
///
/// Relleno mientras escucha y contorneado en reposo: el estado se lee sin
/// depender del color, que en una tienda con mala luz no siempre se distingue.
class _DictationButton extends StatelessWidget {
  const _DictationButton({required this.isListening, required this.onPressed});

  final bool isListening;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 48,
      height: 48,
      child: Material(
        color: isListening ? AppColors.skyBlue : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: isListening ? AppColors.skyBlue : AppColors.border,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: const Key('dictationButton'),
          onTap: onPressed,
          child: Icon(
            isListening ? Icons.stop_rounded : Icons.mic_none_rounded,
            size: 22,
            color: isListening ? AppColors.darkSlate : AppColors.skyBlue,
          ),
        ),
      ),
    );
  }
}

/// Lo que el motor de voz va entendiendo, en vivo.
///
/// Sin esto el usuario no sabe si el micrófono lo está tomando o si habla
/// contra una pantalla muda.
class _ListeningHint extends StatelessWidget {
  const _ListeningHint({required this.transcript});

  final String transcript;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.skyBlue.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(Icons.graphic_eq_rounded,
              size: 16, color: AppColors.skyBlue),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              transcript.isEmpty
                  ? 'Escuchando… di "Maruchan pollo, precio 16, 36 piezas"'
                  : transcript,
              style: const TextStyle(fontSize: 12.5, color: AppColors.skyBlue),
            ),
          ),
        ],
      ),
    );
  }
}
