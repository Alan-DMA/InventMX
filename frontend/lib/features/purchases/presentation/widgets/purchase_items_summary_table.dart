import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../inventory/domain/product.dart';
import '../../domain/purchase_order.dart';
import 'product_field.dart';

/// A partir de este número de líneas se acota la altura de la tabla y se
/// activa el scroll interno — con 3 líneas o menos se muestran todas.
/// Mismo criterio que `CashMovementsListBox` (Tarea 10.2.2), ajustado al
/// mínimo de 3 filas visibles que pidió Eduardo en QA de esta tarea.
const _kMaxVisibleRows = 3;

/// Alto aproximado de una fila: título + subtítulo (qty × costo) + el renglón
/// de precio de venta que llevan los productos por crear + padding.
const _kRowHeight = 78.0;

/// Duración del destello de confirmación en la fila recién agregada — ajuste
/// de QA: "Agregar" no dejaba clara la acción que se acababa de realizar.
const _kHighlightDuration = Duration(milliseconds: 900);

/// Un renglón de la orden tal como lo ve la pantalla, antes de existir en el
/// backend.
///
/// [item] lleva nombre, cantidad y costo; su `productId` es la **llave local**
/// del renglón (`draft-N`) y se mantiene estable toda la vida de la línea,
/// incluso si el usuario la amarra o la desamarra del catálogo. El producto
/// real se traduce al confirmar la orden.
class PurchaseDraftLine {
  const PurchaseDraftLine({
    required this.item,
    this.resolved,
    this.salePriceMxn,
  });

  final PurchaseOrderItem item;

  /// Producto del catálogo al que está amarrado el renglón; `null` = se creará.
  final Product? resolved;

  /// Precio de venta con el que nacerá el producto nuevo. Sólo aplica cuando
  /// [resolved] es `null`.
  final double? salePriceMxn;

  String get id => item.productId;

  /// Un renglón sólo se va a crear si su llave sigue siendo local (`draft-`)
  /// y nadie lo amarró al catálogo. Editando una orden existente los
  /// renglones ya traen `product_id` real, y confundirlos con productos
  /// nuevos duplicaría el catálogo al guardar.
  bool get willBeCreated =>
      resolved == null && item.productId.startsWith('draft-');
}

/// Tabla de resumen de líneas de producto agregadas en `PurchaseCreateScreen`
/// — un solo formulario de captura arriba, esta tabla abajo. Sin límite de
/// altura, una orden con muchas líneas alargaría indefinidamente el scroll
/// de toda la pantalla; a partir de la 4ª línea se acota a un rango que deja
/// siempre ~3 filas legibles y el resto se revela con scroll propio de la
/// tabla, no de la pantalla — mismo patrón ya validado en `CashMovementsListBox`.
///
/// [justAddedId] resalta brevemente la línea recién agregada — retroalimentación
/// visual de que "Agregar" tuvo efecto.
///
/// Filas editables inline (iteración post-exploración CRF de Tarea 12.2.3,
/// ver bitácora): un producto que llega desde el dictado puede traer campos
/// vacíos/ambiguos (nunca un valor inventado — 0/"" es la señal de "falta
/// revisar"). Tocar una fila la expande in-situ para corregir sin salir de la
/// tabla ni perder de vista las demás filas — decisión de `/intent`: reabrir
/// el formulario de captura hubiera sido un viaje de ida y vuelta innecesario
/// para corregir, por ejemplo, un solo dígito.
///
/// Los renglones que se van a dar de alta lo dicen en la propia fila
/// ("Se creará" + su precio de venta): al confirmar la orden aparecerán
/// productos nuevos en el catálogo y eso no debe ser una sorpresa.
class PurchaseItemsSummaryTable extends StatelessWidget {
  const PurchaseItemsSummaryTable({
    super.key,
    required this.lines,
    required this.onRemove,
    required this.onEdit,
    required this.onResolve,
    required this.onSalePriceChanged,
    required this.marginPercent,
    this.justAddedId,
  });

  final List<PurchaseDraftLine> lines;

  /// Quitar el renglón con esa llave local.
  final ValueChanged<String> onRemove;

  /// Nombre / cantidad / costo corregidos. La llave local no cambia.
  final void Function(String id, PurchaseOrderItem updated) onEdit;

  /// El renglón se amarró a un producto del catálogo, o se soltó (`null`).
  final void Function(String id, Product? product) onResolve;

  final void Function(String id, double salePriceMxn) onSalePriceChanged;

  /// Margen máximo sugerido del comercio — se nombra junto al precio para que
  /// el número no parezca salido de la nada.
  final double marginPercent;

  final String? justAddedId;

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      alignment: Alignment.topCenter,
      child: _buildContent(),
    );
  }

  Widget _rowFor(PurchaseDraftLine line) => _ItemRow(
        key: ValueKey(line.id),
        line: line,
        marginPercent: marginPercent,
        onRemove: () => onRemove(line.id),
        onEdit: (updated) => onEdit(line.id, updated),
        onResolve: (product) => onResolve(line.id, product),
        onSalePriceChanged: (price) => onSalePriceChanged(line.id, price),
        isJustAdded: line.id == justAddedId,
      );

  Widget _buildContent() {
    if (lines.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: const Center(
          child: Text(
            'Aún no agregas productos a esta orden.',
            style: TextStyle(fontSize: 13, color: AppColors.onSurfaceMuted),
          ),
        ),
      );
    }

    final decoration = BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppColors.border),
    );

    if (lines.length <= _kMaxVisibleRows) {
      return Container(
        decoration: decoration,
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            for (var i = 0; i < lines.length; i++) ...[
              if (i > 0) const Divider(height: 1, color: AppColors.border),
              _rowFor(lines[i]),
            ],
          ],
        ),
      );
    }

    const maxHeight = _kRowHeight * (_kMaxVisibleRows + 0.5);

    return Container(
      decoration: decoration,
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: maxHeight),
        child: ListView.separated(
          padding: EdgeInsets.zero,
          itemCount: lines.length,
          separatorBuilder: (_, __) =>
              const Divider(height: 1, color: AppColors.border),
          itemBuilder: (_, i) => _rowFor(lines[i]),
        ),
      ),
    );
  }
}

class _ItemRow extends StatefulWidget {
  const _ItemRow({
    super.key,
    required this.line,
    required this.marginPercent,
    required this.onRemove,
    required this.onEdit,
    required this.onResolve,
    required this.onSalePriceChanged,
    required this.isJustAdded,
  });

  final PurchaseDraftLine line;
  final double marginPercent;
  final VoidCallback onRemove;
  final ValueChanged<PurchaseOrderItem> onEdit;
  final ValueChanged<Product?> onResolve;
  final ValueChanged<double> onSalePriceChanged;
  final bool isJustAdded;

  @override
  State<_ItemRow> createState() => _ItemRowState();
}

class _ItemRowState extends State<_ItemRow> {
  bool _isEditing = false;
  late TextEditingController _nameCtrl;
  late TextEditingController _qtyCtrl;
  late TextEditingController _costCtrl;
  late TextEditingController _priceCtrl;

  PurchaseOrderItem get _item => widget.line.item;

  @override
  void initState() {
    super.initState();
    _initControllers();
    _priceCtrl = TextEditingController(text: _formattedSalePrice);
  }

  @override
  void didUpdateWidget(covariant _ItemRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    // El precio sigue al costo mientras el usuario no lo haya tocado: la
    // pantalla recalcula y el campo debe reflejarlo sin pelearse con el
    // texto que el usuario esté escribiendo.
    if (widget.line.salePriceMxn != oldWidget.line.salePriceMxn &&
        _priceCtrl.text != _formattedSalePrice) {
      _priceCtrl.text = _formattedSalePrice;
    }
  }

  String get _formattedSalePrice =>
      widget.line.salePriceMxn == null || widget.line.salePriceMxn! <= 0
          ? ''
          : widget.line.salePriceMxn!.toStringAsFixed(2);

  void _initControllers() {
    _nameCtrl = TextEditingController(text: _item.productName);
    _qtyCtrl =
        TextEditingController(text: _item.quantity > 0 ? '${_item.quantity}' : '');
    _costCtrl = TextEditingController(
        text: _item.unitCostMxn > 0 ? _item.unitCostMxn.toStringAsFixed(2) : '');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _qtyCtrl.dispose();
    _costCtrl.dispose();
    _priceCtrl.dispose();
    super.dispose();
  }

  void _startEditing() {
    _initControllers();
    setState(() => _isEditing = true);
  }

  void _cancelEditing() => setState(() => _isEditing = false);

  void _confirmEditing() {
    final qty = int.tryParse(_qtyCtrl.text) ?? 0;
    final cost = double.tryParse(_costCtrl.text.replaceAll(',', '')) ?? 0;
    widget.onEdit(_item.copyWith(
      productName: _nameCtrl.text.trim(),
      quantity: qty,
      unitCostMxn: cost,
    ));
    setState(() => _isEditing = false);
  }

  void _submitSalePrice(String raw) {
    final price = double.tryParse(raw.replaceAll(',', '')) ?? 0;
    if (price > 0) widget.onSalePriceChanged(price);
  }

  /// Campos incompletos/ambiguos tras un dictado — nunca se rellenan con un
  /// valor inventado (0/"" es la señal explícita de "falta revisar"), así
  /// que se le avisa al usuario exactamente qué falta en vez de dejar que
  /// un $0.00 pase desapercibido.
  List<String> get _warnings {
    final w = <String>[];
    if (_item.productName.trim().isEmpty) w.add('falta nombre');
    if (_item.quantity <= 0) w.add('falta cantidad');
    if (_item.unitCostMxn <= 0) w.add('falta precio');
    return w;
  }

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: widget.isJustAdded ? 1.0 : 0.0, end: 0.0),
      duration: _kHighlightDuration,
      curve: Curves.easeOut,
      builder: (context, highlight, child) {
        return Container(
          color: Color.lerp(Colors.transparent,
              AppColors.emerald.withValues(alpha: 0.22), highlight),
          child: child,
        );
      },
      child: _isEditing ? _buildEditingRow() : _buildReadRow(),
    );
  }

  Widget _buildReadRow() {
    final warnings = _warnings;
    final willCreate = widget.line.willBeCreated && _item.productName.trim().isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Sólo la parte de arriba abre la edición: el precio de venta de abajo
        // se escribe en sitio, sin entrar al modo de edición completo.
        InkWell(
          key: Key('purchaseItemRow-${_item.productId}'),
          onTap: _startEditing,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              _item.productName.isEmpty
                                  ? '(sin nombre)'
                                  : _item.productName,
                              style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: _item.productName.isEmpty
                                      ? AppColors.onSurfaceMuted
                                      : AppColors.onSurface),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (willCreate) ...[
                            const SizedBox(width: 6),
                            const _WillCreateTag(),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${_item.quantity} × '
                        '\$${_item.unitCostMxn.toStringAsFixed(2)}',
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.onSurfaceMuted),
                      ),
                    ],
                  ),
                ),
                Text(
                  '\$${_item.subtotalMxn.toStringAsFixed(2)}',
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.skyBlue),
                ),
                IconButton(
                  onPressed: widget.onRemove,
                  icon: const Icon(Icons.close_rounded, size: 18),
                  color: AppColors.error,
                  tooltip: 'Quitar',
                  padding: const EdgeInsets.only(left: 8),
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),
        ),
        if (willCreate)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
            child: _SalePriceRow(
              controller: _priceCtrl,
              productId: _item.productId,
              marginPercent: widget.marginPercent,
              onSubmitted: _submitSalePrice,
            ),
          ),
        if (warnings.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final w in warnings) _WarningChip(label: w),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildEditingRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ProductField(
            fieldKey: Key('purchaseItemEditName-${_item.productId}'),
            controller: _nameCtrl,
            resolved: widget.line.resolved,
            onResolvedChanged: widget.onResolve,
            autofocus: true,
            dense: true,
            onChanged: () => setState(() {}),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: Key('purchaseItemEditQty-${_item.productId}'),
                  controller: _qtyCtrl,
                  keyboardType: TextInputType.number,
                  style:
                      const TextStyle(color: AppColors.onSurface, fontSize: 14),
                  decoration: const InputDecoration(
                      labelText: 'Cantidad', isDense: true),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  key: Key('purchaseItemEditCost-${_item.productId}'),
                  controller: _costCtrl,
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
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              IconButton(
                key: Key('purchaseItemEditCancel-${_item.productId}'),
                onPressed: _cancelEditing,
                icon: const Icon(Icons.close_rounded, size: 20),
                color: AppColors.onSurfaceMuted,
                tooltip: 'Cancelar',
              ),
              const SizedBox(width: 4),
              IconButton(
                key: Key('purchaseItemEditConfirm-${_item.productId}'),
                onPressed: _confirmEditing,
                icon: const Icon(Icons.check_rounded, size: 20),
                color: AppColors.emerald,
                tooltip: 'Confirmar',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Precio con el que nacerá un producto nuevo
// ---------------------------------------------------------------------------

class _SalePriceRow extends StatelessWidget {
  const _SalePriceRow({
    required this.controller,
    required this.productId,
    required this.marginPercent,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final String productId;
  final double marginPercent;
  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            'Precio de venta · margen ${marginPercent.toStringAsFixed(0)}%',
            style: const TextStyle(
                fontSize: 11, color: AppColors.onSurfaceMuted),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 104,
          child: TextField(
            key: Key('purchaseItemSalePrice-$productId'),
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textAlign: TextAlign.right,
            onChanged: onSubmitted,
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.onSurface),
            decoration: const InputDecoration(
              isDense: true,
              prefixText: '\$ ',
              prefixStyle: TextStyle(
                  fontSize: 13, color: AppColors.onSurfaceMuted),
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Etiquetas
// ---------------------------------------------------------------------------

class _WillCreateTag extends StatelessWidget {
  const _WillCreateTag();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('purchaseItemWillCreateTag'),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.skyBlue.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Text(
        'Se creará',
        style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: AppColors.skyBlue),
      ),
    );
  }
}

class _WarningChip extends StatelessWidget {
  const _WarningChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.warning_amber_rounded,
              size: 12, color: AppColors.warning),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.warning),
          ),
        ],
      ),
    );
  }
}
