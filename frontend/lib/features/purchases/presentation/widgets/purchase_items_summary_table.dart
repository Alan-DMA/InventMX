import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../domain/purchase_order.dart';

/// A partir de este número de líneas se acota la altura de la tabla y se
/// activa el scroll interno — con 3 líneas o menos se muestran todas.
/// Mismo criterio que `CashMovementsListBox` (Tarea 10.2.2), ajustado al
/// mínimo de 3 filas visibles que pidió Eduardo en QA de esta tarea.
const _kMaxVisibleRows = 3;

/// Alto aproximado de una fila: título + subtítulo (qty × costo) + padding.
const _kRowHeight = 58.0;

/// Duración del destello de confirmación en la fila recién agregada — ajuste
/// de QA: "Agregar" no dejaba clara la acción que se acababa de realizar.
const _kHighlightDuration = Duration(milliseconds: 900);

/// Tabla de resumen de líneas de producto agregadas en `PurchaseCreateScreen`
/// — un solo formulario de captura arriba, esta tabla abajo. Sin límite de
/// altura, una orden con muchas líneas alargaría indefinidamente el scroll
/// de toda la pantalla; a partir de la 4ª línea se acota a un rango que deja
/// siempre ~3 filas legibles y el resto se revela con scroll propio de la
/// tabla, no de la pantalla — mismo patrón ya validado en `CashMovementsListBox`.
///
/// [justAddedId] resalta brevemente la línea con ese `productId` al montarse
/// — retroalimentación visual de que "Agregar" tuvo efecto.
///
/// Filas editables inline (iteración post-exploración CRF de Tarea 12.2.3,
/// ver bitácora): un producto que llega desde el dictado puede traer campos
/// vacíos/ambiguos (nunca un valor inventado — 0/"" es la señal de "falta
/// revisar", mismo criterio que ya usaba `_canAddEntry` en la pantalla).
/// Tocar una fila la expande in-situ para corregir sin salir de la tabla ni
/// perder de vista las demás filas — decisión de `/intent`: reabrir el
/// formulario de captura hubiera sido un viaje de ida y vuelta innecesario
/// para corregir, por ejemplo, un solo dígito.
class PurchaseItemsSummaryTable extends StatelessWidget {
  const PurchaseItemsSummaryTable({
    super.key,
    required this.items,
    required this.onRemove,
    required this.onEdit,
    this.justAddedId,
  });

  final List<PurchaseOrderItem> items;
  final ValueChanged<PurchaseOrderItem> onRemove;
  final ValueChanged<PurchaseOrderItem> onEdit;
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

  Widget _buildContent() {
    if (items.isEmpty) {
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

    if (items.length <= _kMaxVisibleRows) {
      return Container(
        decoration: decoration,
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0) const Divider(height: 1, color: AppColors.border),
              _ItemRow(
                key: ValueKey(items[i].productId),
                item: items[i],
                onRemove: () => onRemove(items[i]),
                onEdit: onEdit,
                isJustAdded: items[i].productId == justAddedId,
              ),
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
          itemCount: items.length,
          separatorBuilder: (_, __) =>
              const Divider(height: 1, color: AppColors.border),
          itemBuilder: (_, i) => _ItemRow(
            key: ValueKey(items[i].productId),
            item: items[i],
            onRemove: () => onRemove(items[i]),
            onEdit: onEdit,
            isJustAdded: items[i].productId == justAddedId,
          ),
        ),
      ),
    );
  }
}

class _ItemRow extends StatefulWidget {
  const _ItemRow({
    super.key,
    required this.item,
    required this.onRemove,
    required this.onEdit,
    required this.isJustAdded,
  });

  final PurchaseOrderItem item;
  final VoidCallback onRemove;
  final ValueChanged<PurchaseOrderItem> onEdit;
  final bool isJustAdded;

  @override
  State<_ItemRow> createState() => _ItemRowState();
}

class _ItemRowState extends State<_ItemRow> {
  bool _isEditing = false;
  late TextEditingController _nameCtrl;
  late TextEditingController _qtyCtrl;
  late TextEditingController _costCtrl;

  @override
  void initState() {
    super.initState();
    _initControllers();
  }

  void _initControllers() {
    _nameCtrl = TextEditingController(text: widget.item.productName);
    _qtyCtrl = TextEditingController(
        text: widget.item.quantity > 0 ? '${widget.item.quantity}' : '');
    _costCtrl = TextEditingController(
        text: widget.item.unitCostMxn > 0
            ? widget.item.unitCostMxn.toStringAsFixed(2)
            : '');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _qtyCtrl.dispose();
    _costCtrl.dispose();
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
    widget.onEdit(widget.item.copyWith(
      productName: _nameCtrl.text.trim(),
      quantity: qty,
      unitCostMxn: cost,
    ));
    setState(() => _isEditing = false);
  }

  /// Campos incompletos/ambiguos tras un dictado — nunca se rellenan con un
  /// valor inventado (0/"" es la señal explícita de "falta revisar"), así
  /// que se le avisa al usuario exactamente qué falta en vez de dejar que
  /// un $0.00 pase desapercibido.
  List<String> get _warnings {
    final w = <String>[];
    if (widget.item.productName.trim().isEmpty) w.add('falta nombre');
    if (widget.item.quantity <= 0) w.add('falta cantidad');
    if (widget.item.unitCostMxn <= 0) w.add('falta precio');
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

    return InkWell(
      key: Key('purchaseItemRow-${widget.item.productId}'),
      onTap: _startEditing,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.item.productName.isEmpty
                            ? '(sin nombre)'
                            : widget.item.productName,
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: widget.item.productName.isEmpty
                                ? AppColors.onSurfaceMuted
                                : AppColors.onSurface),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${widget.item.quantity} × '
                        '\$${widget.item.unitCostMxn.toStringAsFixed(2)}',
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.onSurfaceMuted),
                      ),
                    ],
                  ),
                ),
                Text(
                  '\$${widget.item.subtotalMxn.toStringAsFixed(2)}',
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
            if (warnings.isNotEmpty) ...[
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final w in warnings) _WarningChip(label: w),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildEditingRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: Key('purchaseItemEditName-${widget.item.productId}'),
            controller: _nameCtrl,
            autofocus: true,
            style: const TextStyle(color: AppColors.onSurface, fontSize: 14),
            decoration: const InputDecoration(
                labelText: 'Nombre del producto', isDense: true),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: Key('purchaseItemEditQty-${widget.item.productId}'),
                  controller: _qtyCtrl,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(
                      color: AppColors.onSurface, fontSize: 14),
                  decoration: const InputDecoration(
                      labelText: 'Cantidad', isDense: true),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  key: Key('purchaseItemEditCost-${widget.item.productId}'),
                  controller: _costCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  style: const TextStyle(
                      color: AppColors.onSurface, fontSize: 14),
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
                key: Key('purchaseItemEditCancel-${widget.item.productId}'),
                onPressed: _cancelEditing,
                icon: const Icon(Icons.close_rounded, size: 20),
                color: AppColors.onSurfaceMuted,
                tooltip: 'Cancelar',
              ),
              const SizedBox(width: 4),
              IconButton(
                key: Key('purchaseItemEditConfirm-${widget.item.productId}'),
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
