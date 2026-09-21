import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/ocr_helper.dart';
import '../../account/presentation/account_provider.dart';
import '../../inventory/domain/product.dart';
import '../../inventory/presentation/inventory_provider.dart'
    hide suppliersProvider;
import '../data/purchases_repository.dart' show PurchasesException;
import '../data/receipt_line_parser.dart';
import '../domain/purchase_order.dart';
import '../domain/receipt_scan.dart';
import '../domain/supplier.dart';
import 'ocr_column_mapping_screen.dart';
import 'ocr_review_screen.dart';
import 'purchases_provider.dart';
import 'widgets/dictation_modal.dart';
import 'widgets/product_field.dart';
import 'widgets/purchase_items_summary_table.dart';

/// `PurchaseCreateScreen` — Subtarea 11.2.1 (Pantalla de Registro de Compras
/// y Entradas).
///
/// Ajuste de QA de Eduardo: un solo formulario de captura (no un bloque
/// repetido por línea) + botón "Agregar" + tabla de resumen con altura
/// acotada — mismo patrón ya usado en el resto de la app para listas que
/// pueden crecer (`PurchaseItemsSummaryTable`, ver `CashMovementsListBox`).
///
/// Con [initial] abre en **modo edición** (mismo criterio que
/// `AddSupplierModal`): mismos campos y las mismas herramientas de captura,
/// prellenados con la orden, y `PUT /purchase-orders/{id}` al guardar. El
/// backend sólo lo permite mientras la orden no haya recibido mercancía.
class PurchaseCreateScreen extends ConsumerStatefulWidget {
  const PurchaseCreateScreen({super.key, this.initial});

  /// Orden a corregir; `null` = alta.
  final PurchaseOrder? initial;

  bool get isEditing => initial != null;

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

  /// Producto del catálogo al que quedó amarrada la línea que se captura, o
  /// `null` si se dará de alta con el texto tal cual — ese es el camino
  /// normal, no el excepcional (ver `ProductField`).
  Product? _selectedProduct;

  final List<PurchaseOrderItem> _items = [];
  int _lineCounter = 0;

  /// Producto del catálogo al que está amarrado cada renglón, por llave local.
  /// Un renglón ausente de este mapa es uno que se va a crear.
  final Map<String, Product> _resolvedRows = {};

  /// Precio de venta con el que se dará de alta cada renglón sin resolver:
  /// sugerido como costo × (1 + margen) y editable en la tabla de resumen.
  /// Vive aquí y no en `PurchaseOrderItem` porque no viaja al backend — la
  /// orden de compra sólo manda producto, cantidad y costo.
  final Map<String, double> _salePrices = {};

  /// Renglones cuyo precio de venta ya tocó el usuario: dejan de seguir al
  /// costo cuando éste se corrige.
  final Set<String> _touchedPrices = {};

  /// ID de la línea recién agregada — dispara el destello de confirmación en
  /// `PurchaseItemsSummaryTable` (ajuste de QA: la acción de "Agregar" no se
  /// notaba sin retroalimentación visual).
  String? _justAddedId;

  bool _isSaving = false;
  String? _error;

  /// Escaneo de factura — Subtareas 12.2.1 / 12.2.2.
  bool _isScanning = false;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    if (initial == null) return;
    // Los renglones de una orden existente ya traen `product_id` real, así
    // que conservan su llave: `_materializeLines()` los deja pasar tal cual y
    // no intenta darlos de alta otra vez.
    _items.addAll(initial.items);
    _expectedDeliveryDate = initial.expectedDeliveryDate;
    _notesCtrl.text = initial.notes ?? '';
  }

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

  /// Precio de venta sugerido para un producto que aún no existe: el costo de
  /// esta compra más el margen máximo configurado en Preferencias.
  double _suggestedSalePrice(double unitCost) =>
      unitCost * (1 + _marginPercent / 100);

  double get _marginPercent =>
      ref.read(maxMarginPercentProvider).valueOrNull ?? 40.0;

  /// Inserta un renglón con una llave local estable (`draft-N`) — se mantiene
  /// aunque después se amarre o se suelte del catálogo, y sólo se traduce a
  /// `product_id` real al confirmar la orden.
  void _insertLine({
    required String name,
    required int quantity,
    required double unitCostMxn,
    Product? resolved,
  }) {
    final id = 'draft-${++_lineCounter}';
    // Al inicio — misma convención UX que `CashMovementsNotifier`: el ítem
    // tocado por la acción aparece primero, sin depender de que el usuario
    // haga scroll para notar que la acción tuvo efecto.
    _items.insert(
      0,
      PurchaseOrderItem(
        productId: id,
        productName: resolved?.name ?? name,
        quantity: quantity,
        unitCostMxn: unitCostMxn,
      ),
    );
    if (resolved != null) {
      _resolvedRows[id] = resolved;
    } else if (unitCostMxn > 0) {
      _salePrices[id] = _suggestedSalePrice(unitCostMxn);
    }
    _justAddedId = id;
  }

  void _addEntry() {
    if (!_canAddEntry) return;
    setState(() {
      _insertLine(
        name: _nameCtrl.text.trim(),
        quantity: _entryQuantity,
        unitCostMxn: _entryUnitCost,
        resolved: _selectedProduct,
      );
      _selectedProduct = null;
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

  void _removeLine(String id) {
    setState(() {
      _items.removeWhere((it) => it.productId == id);
      _resolvedRows.remove(id);
      _salePrices.remove(id);
      _touchedPrices.remove(id);
    });
  }

  /// Nombre, cantidad o costo corregidos desde la tabla. La llave local no
  /// cambia; el precio sugerido sigue al costo mientras el usuario no lo haya
  /// tocado a mano.
  void _editLine(String id, PurchaseOrderItem updated) {
    setState(() {
      final i = _items.indexWhere((it) => it.productId == id);
      if (i == -1) return;
      _items[i] = updated;
      if (!_resolvedRows.containsKey(id) &&
          !_touchedPrices.contains(id) &&
          updated.unitCostMxn > 0) {
        _salePrices[id] = _suggestedSalePrice(updated.unitCostMxn);
      }
    });
  }

  /// El renglón se amarró a un producto del catálogo (o se soltó). Al
  /// amarrarlo toma el nombre canónico; al soltarlo recupera su precio
  /// sugerido, porque vuelve a ser un producto por crear.
  void _resolveLine(String id, Product? product) {
    setState(() {
      final i = _items.indexWhere((it) => it.productId == id);
      if (i == -1) return;
      if (product == null) {
        _resolvedRows.remove(id);
        if (!_touchedPrices.contains(id) && _items[i].unitCostMxn > 0) {
          _salePrices[id] = _suggestedSalePrice(_items[i].unitCostMxn);
        }
        return;
      }
      _resolvedRows[id] = product;
      _salePrices.remove(id);
      _touchedPrices.remove(id);
      _items[i] = _items[i].copyWith(productName: product.name);
    });
  }

  void _setSalePrice(String id, double price) {
    _touchedPrices.add(id);
    _salePrices[id] = price;
  }

  // ── Escaneo de factura — Subtareas 12.2.1 y 12.2.2 (+ Q-01 / Q-03) ──────

  /// Foto → ML Kit (on-device) → tabla → mapeo de columnas → revisión.
  ///
  /// La lectura corre en el procesador del teléfono: ni la imagen ni el texto
  /// salen del dispositivo (Constitución Art. IV, 4.2).
  Future<void> _scanReceipt() async {
    if (_isScanning) return;
    final messenger = ScaffoldMessenger.of(context);

    final ReceiptCapture? capture;
    try {
      capture = await ref.read(receiptPhotoSourceProvider).capture(context);
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
    if (capture == null) return; // El usuario canceló la captura.
    await _processCapture(capture, onRescan: _scanReceipt);
  }

  /// Archivo (PDF o imagen) → mismo pipeline que la foto — Q-03. Las páginas
  /// del PDF se apilan en una sola tabla; el mapeo se hace una vez.
  Future<void> _uploadReceipt() async {
    if (_isScanning) return;
    final messenger = ScaffoldMessenger.of(context);

    setState(() => _isScanning = true);
    final ReceiptCapture? capture;
    try {
      capture = await ref.read(receiptFileSourceProvider).pick();
    } catch (_) {
      if (!mounted) return;
      setState(() => _isScanning = false);
      messenger.showSnackBar(
        const SnackBar(
          content: Text('No se pudo abrir el archivo. Prueba con un PDF o '
              'una imagen de la factura.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    if (!mounted) return;
    setState(() => _isScanning = false);
    if (capture == null) return; // El usuario canceló el selector.
    await _processCapture(capture, onRescan: _uploadReceipt);
  }

  /// OCR → `detectTable` (sin renglones de ruido) → parser por renglones
  /// (proveedor, total) → mapeo recordado → `OcrColumnMappingScreen` →
  /// `OcrReviewScreen` → orden.
  ///
  /// [onRescan] es la salida "tomar otra foto" / "elegir otro archivo" de
  /// las pantallas intermedias — vuelve al origen del que vino la captura.
  Future<void> _processCapture(
    ReceiptCapture capture, {
    required Future<void> Function() onRescan,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    setState(() => _isScanning = true);
    try {
      final lines = await ref.read(receiptReaderProvider).read(capture);
      // Fecha, teléfono, RFC y dirección se quedan fuera del grid y se
      // anuncian en el mapeo (Tarea 12.2, QA de ruido). El proveedor y el
      // total impreso siguen saliendo del parser por renglones, que sí ve
      // la hoja completa.
      const parser = ReceiptLineParser();
      final table = detectTable(lines, ignoreRow: parser.classifier.isNoise);
      final parsed = await ref
          .read(purchasesRepositoryProvider)
          .parseReceiptRows(table.rowTexts);

      final mappingStore = ref.read(receiptMappingStoreProvider);
      final supplier = parsed.detectedSupplier;
      final remembered =
          supplier == null ? null : await mappingStore.load(supplier);

      if (!mounted) return;
      setState(() => _isScanning = false);

      var result = parsed.copyWith(
        items: const [],
        ignoredRows: table.ignoredRows,
      );
      if (!table.isEmpty) {
        final mappingOutcome = await navigator.push<OcrColumnMappingOutcome>(
          MaterialPageRoute(
            builder: (_) => OcrColumnMappingScreen(
              table: table,
              suggested: parser.suggestMapping(table),
              remembered: remembered,
              supplier: supplier,
            ),
          ),
        );
        if (!mounted || mappingOutcome == null) return;
        if (mappingOutcome.rescanRequested) {
          await onRescan();
          return;
        }
        if (supplier != null) {
          await mappingStore.save(supplier, mappingOutcome.mapping);
        }
        result = result.copyWith(items: mappingOutcome.items);
      }

      if (!mounted) return;
      final outcome = await navigator.push<OcrReviewOutcome>(
        MaterialPageRoute(builder: (_) => OcrReviewScreen(result: result)),
      );
      if (!mounted || outcome == null) return;

      if (outcome.rescanRequested) {
        await onRescan();
        return;
      }
      if (outcome.items.isEmpty) return;

      // `OcrReviewScreen` ya resolvió lo que pudo contra el catálogo: un
      // renglón resuelto trae el `product_id` real y aquí se convierte en el
      // producto amarrado de la línea; el resto entra como producto por crear.
      final catalog = {
        for (final p in ref.read(inventoryProvider).products) p.id: p,
      };
      setState(() {
        for (final item in outcome.items) {
          _insertLine(
            name: item.productName,
            quantity: item.quantity,
            unitCostMxn: item.unitCostMxn,
            resolved: catalog[item.productId],
          );
        }
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

  // ── Dictado de voz — Subtarea 12.2.3, iteración post-exploración CRF ────
  //
  // Reemplaza el botón embebido en el campo "nombre" por un modal a nivel
  // de sección (DictationModal) — un solo producto o varios de corrido,
  // separados por un conector de la familia enseñada en el propio modal.
  // Ver docs/architecture/registro_implementacion.md (Tarea 12.2.3) y
  // prototypes/dictation_crf/ para el porqué se descartó CRFsuite.

  Future<void> _openDictationModal() async {
    final parsedItems = await showDictationModal(context);
    if (!mounted || parsedItems == null || parsedItems.isEmpty) return;

    setState(() {
      for (final parsed in parsedItems) {
        // "" / 0 son la señal explícita de "falta revisar" — nunca se inventa
        // un valor; PurchaseItemsSummaryTable las muestra con el chip de
        // advertencia correspondiente.
        _insertLine(
          name: parsed.name ?? '',
          quantity: parsed.quantity ?? 0,
          unitCostMxn: parsed.priceMxn ?? 0,
        );
      }
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(parsedItems.length == 1
              ? '1 producto agregado por dictado'
              : '${parsedItems.length} productos agregados por dictado'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  double get _total => _items.fold<double>(0, (sum, i) => sum + i.subtotalMxn);

  /// Al confirmar pueden aparecer productos nuevos en el catálogo; el botón
  /// lo dice antes del toque, no después.
  String get _submitLabel {
    final verb = widget.isEditing ? 'Guardar cambios' : 'Crear orden de compra';
    if (_toCreateCount == 0) return verb;
    final tail = _toCreateCount == 1
        ? '1 producto nuevo'
        : '$_toCreateCount productos nuevos';
    return widget.isEditing
        ? 'Guardar cambios y $tail'
        : 'Crear orden y $tail';
  }

  /// Renglones que van a dar de alta un producto nuevo al confirmar.
  int get _toCreateCount => _items
      .where((i) =>
          i.productId.startsWith('draft-') &&
          !_resolvedRows.containsKey(i.productId))
      .length;

  /// Editando una orden existente los renglones traen `product_id` real pero
  /// no pasaron por `_resolvedRows`: se resuelven contra el catálogo para que
  /// el campo compartido los muestre amarrados y no como productos nuevos.
  List<PurchaseDraftLine> _linesFor(List<Product> catalog) => [
        for (final item in _items)
          PurchaseDraftLine(
            item: item,
            resolved: _resolvedRows[item.productId] ??
                (item.productId.startsWith('draft-')
                    ? null
                    : catalog
                        .where((p) => p.id == item.productId)
                        .firstOrNull),
            salePriceMxn: _salePrices[item.productId],
          ),
      ];

  /// Además de requerir proveedor y al menos un producto, ningún producto
  /// puede quedar a medias (nombre vacío, cantidad o precio en 0) — el chip
  /// de advertencia de la tabla no es solo decorativo, bloquea el envío
  /// hasta que el usuario lo revise.
  bool get _isValid =>
      _supplier != null &&
      _items.isNotEmpty &&
      _items.every((i) =>
          i.productName.trim().isNotEmpty &&
          i.quantity > 0 &&
          i.unitCostMxn > 0);

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _expectedDeliveryDate ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime(2030),
    );
    if (picked != null) setState(() => _expectedDeliveryDate = picked);
  }

  /// Traduce las llaves locales a `product_id` reales: los renglones amarrados
  /// al catálogo usan el suyo, y los que se van a crear se dan de alta aquí,
  /// con el precio de venta que quedó en su fila (sugerido como costo ×
  /// (1 + margen máximo de Preferencias), o el que el usuario haya escrito).
  /// Un solo toque de "Crear orden de compra", sin pasos extra por producto.
  Future<List<PurchaseOrderItem>> _materializeLines() async {
    double margin;
    try {
      margin = await ref.read(maxMarginPercentProvider.future);
    } catch (_) {
      margin = 40.0; // Mismo default que AuthRepositoryImpl.fetchMaxMarginPercent.
    }

    final items = <PurchaseOrderItem>[];
    for (final item in _items) {
      // Renglón que ya viene de una orden guardada: su `product_id` es real,
      // no una llave local. Darlo de alta otra vez duplicaría el catálogo.
      if (!item.productId.startsWith('draft-')) {
        items.add(item);
        continue;
      }
      final product = _resolvedRows[item.productId] ??
          await ref.read(inventoryProvider.notifier).addProduct(
                name: item.productName,
                costMxn: item.unitCostMxn,
                priceMxn: _salePrices[item.productId] ??
                    item.unitCostMxn * (1 + margin / 100),
                stock: 0,
              );
      items.add(PurchaseOrderItem(
        productId: product.id,
        productName: product.name,
        productSku: product.sku,
        quantity: item.quantity,
        unitCostMxn: item.unitCostMxn,
      ));
    }
    return items;
  }

  Future<void> _submit() async {
    if (!_isValid || _isSaving) return;
    setState(() {
      _isSaving = true;
      _error = null;
    });

    try {
      final items = await _materializeLines();
      final notes =
          _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim();
      final notifier = ref.read(purchaseOrdersProvider.notifier);

      if (widget.isEditing) {
        await notifier.updateOrder(
          purchaseOrderId: widget.initial!.id,
          supplierId: _supplier!.id,
          items: items,
          expectedDeliveryDate: _expectedDeliveryDate,
          notes: notes,
        );
      } else {
        await notifier.createOrder(
          supplierId: _supplier!.id,
          items: items,
          expectedDeliveryDate: _expectedDeliveryDate,
          notes: notes,
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() {
        _isSaving = false;
        // El 422 de "ya recibió mercancía" trae su propio mensaje; se respeta
        // en vez de taparlo con uno genérico.
        _error = e is PurchasesException
            ? e.message
            : widget.isEditing
                ? 'No se pudieron guardar los cambios.'
                : 'No se pudo crear la orden de compra.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final suppliers = ref.watch(suppliersProvider).suppliers;
    final catalog = ref.watch(inventoryProvider).products;

    // Editando: el proveedor llega por id, y la lista puede seguir cargando
    // cuando se abre la pantalla.
    final initialSupplierId = widget.initial?.supplierId;
    _supplier ??= initialSupplierId == null
        ? null
        : suppliers.where((s) => s.id == initialSupplierId).firstOrNull;

    return Scaffold(
      backgroundColor: AppColors.darkSlate,
      appBar: AppBar(
        backgroundColor: AppColors.darkSlate,
        title: Text(widget.isEditing
            ? 'Editar orden de compra'
            : 'Nueva orden de compra'),
        actions: [
          // Factura en PDF o imagen — Tarea 12.2, Q-03. Mismo pipeline que
          // la foto; deshabilitado mientras corre cualquiera de los dos.
          IconButton(
            key: const Key('uploadReceiptButton'),
            tooltip: 'Subir factura (PDF o imagen)',
            onPressed: _isScanning ? null : _uploadReceipt,
            icon: const Icon(Icons.upload_file_outlined,
                color: AppColors.skyBlue),
          ),
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
          _sectionLabelWithDictation('Agregar producto'),
          _buildEntryForm(),
          const SizedBox(height: 16),
          _sectionLabel('Productos en esta orden  *'),
          PurchaseItemsSummaryTable(
            lines: _linesFor(catalog),
            marginPercent: _marginPercent,
            onRemove: _removeLine,
            onEdit: _editLine,
            onResolve: _resolveLine,
            onSalePriceChanged: _setSalePrice,
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
                // Al confirmar aparecerán productos nuevos en el catálogo; el
                // botón lo dice antes del toque, no después.
                : Text(_submitLabel),
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

  /// Título de sección + ícono de dictado — a nivel de sección, no de un
  /// solo campo, para comunicar que llena uno o varios productos a la vez
  /// (Tarea 12.2.3, iteración post-exploración CRF; ver DictationModal).
  Widget _sectionLabelWithDictation(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            Expanded(
              child: Text(text,
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: AppColors.onSurface)),
            ),
            SizedBox(
              width: 36,
              height: 36,
              child: Material(
                color: Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: const BorderSide(color: AppColors.skyBlue),
                ),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  key: const Key('dictationModalOpenButton'),
                  onTap: _openDictationModal,
                  child: const Icon(Icons.mic_none_rounded,
                      size: 18, color: AppColors.skyBlue),
                ),
              ),
            ),
          ],
        ),
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
          ProductField(
            fieldKey: const Key('purchaseEntryNameField'),
            controller: _nameCtrl,
            resolved: _selectedProduct,
            onResolvedChanged: (product) =>
                setState(() => _selectedProduct = product),
            onChanged: () => setState(() {}),
          ),
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
