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
class PurchaseItemsSummaryTable extends StatelessWidget {
  const PurchaseItemsSummaryTable({
    super.key,
    required this.items,
    required this.onRemove,
    this.justAddedId,
  });

  final List<PurchaseOrderItem> items;
  final ValueChanged<PurchaseOrderItem> onRemove;
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
            isJustAdded: items[i].productId == justAddedId,
          ),
        ),
      ),
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow(
      {super.key,
      required this.item,
      required this.onRemove,
      required this.isJustAdded});

  final PurchaseOrderItem item;
  final VoidCallback onRemove;
  final bool isJustAdded;

  @override
  Widget build(BuildContext context) {
    // TweenAnimationBuilder anima una sola vez al montar la fila (de
    // `begin` a `end`) — perfecto para un destello de "recién agregado" sin
    // necesitar un AnimationController propio.
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: isJustAdded ? 1.0 : 0.0, end: 0.0),
      duration: _kHighlightDuration,
      curve: Curves.easeOut,
      builder: (context, highlight, child) {
        return Container(
          color: Color.lerp(Colors.transparent,
              AppColors.emerald.withValues(alpha: 0.22), highlight),
          child: child,
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.productName,
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.onSurface),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${item.quantity} × \$${item.unitCostMxn.toStringAsFixed(2)}',
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.onSurfaceMuted),
                  ),
                ],
              ),
            ),
            Text(
              '\$${item.subtotalMxn.toStringAsFixed(2)}',
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.skyBlue),
            ),
            IconButton(
              onPressed: onRemove,
              icon: const Icon(Icons.close_rounded, size: 18),
              color: AppColors.error,
              tooltip: 'Quitar',
              padding: const EdgeInsets.only(left: 8),
              constraints: const BoxConstraints(),
            ),
          ],
        ),
      ),
    );
  }
}
