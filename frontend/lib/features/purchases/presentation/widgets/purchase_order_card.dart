import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../domain/purchase_order.dart';
import '../purchase_format.dart';
import 'purchase_status_pill.dart';

/// Tarjeta de orden de compra — Subtarea 11.2.1, Figma nodo `1:51`.
///
/// Traduce la estructura del diseño (folio, pill de estado, proveedor,
/// metadata, total y CTA) a `AppColors`; la paleta clara del Figma es
/// referencial.
class PurchaseOrderCard extends StatelessWidget {
  const PurchaseOrderCard({
    super.key,
    required this.order,
    required this.onTap,
    required this.onReceive,
  });

  final PurchaseOrder order;
  final VoidCallback onTap;
  final VoidCallback onReceive;

  bool get _isReceived => order.status == PurchaseOrderStatus.received;

  /// Qué fecha le sirve al tendero según dónde está la orden, siempre con su
  /// etiqueta: antes mostraba `createdAt` sin nombre, así que la fecha de
  /// entrega que el usuario elegía al crear la orden nunca se veía por ningún
  /// lado y parecía que no se guardaba (hallazgo de QA, Sep 19).
  (String, DateTime) get _dateInfo {
    if (_isReceived && order.receivedDate != null) {
      return ('Recibida', order.receivedDate!);
    }
    if (order.expectedDeliveryDate != null) {
      return ('Llega', order.expectedDeliveryDate!);
    }
    // Parcial sin fecha esperada: lo último que se sabe es cuándo llegó algo.
    if (order.receivedDate != null) {
      return ('Última entrega', order.receivedDate!);
    }
    return ('Creada', order.createdAt);
  }

  @override
  Widget build(BuildContext context) {
    final (dateCaption, date) = _dateInfo;
    final dateLabel = '$dateCaption: ${formatPurchaseDate(date)}';

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    order.folio,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.onSurfaceMuted,
                      letterSpacing: -0.3,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                PurchaseStatusPill(status: order.status),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              order.supplierName,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppColors.onSurface,
              ),
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.calendar_today_rounded, size: 13, color: AppColors.onSurfaceMuted),
                const SizedBox(width: 4),
                // Flexible: la fecha ahora va etiquetada ("Llega: …") y en un
                // teléfono angosto es lo primero que se queda sin ancho.
                Flexible(
                  child: Text(
                    dateLabel,
                    style: const TextStyle(fontSize: 12, color: AppColors.onSurfaceMuted),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 10),
                const Text('•', style: TextStyle(fontSize: 12, color: AppColors.onSurfaceMuted)),
                const SizedBox(width: 10),
                const Icon(Icons.inventory_2_outlined, size: 13, color: AppColors.onSurfaceMuted),
                const SizedBox(width: 4),
                Text(
                  '${order.itemCount} producto${order.itemCount == 1 ? '' : 's'}',
                  style: const TextStyle(fontSize: 12, color: AppColors.onSurfaceMuted),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1, color: AppColors.border),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'TOTAL',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: AppColors.onSurfaceMuted,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          '\$${order.totalMxn.toStringAsFixed(0)}',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppColors.skyBlue,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Text('MXN', style: TextStyle(fontSize: 12, color: AppColors.onSurfaceMuted)),
                      ],
                    ),
                  ],
                ),
                _isReceived
                    ? const _WarehouseBadge()
                    : ElevatedButton.icon(
                        onPressed: onReceive,
                        icon: const Icon(Icons.check_rounded, size: 16),
                        label: const Text('Recibir'),
                        // Botón sólido estándar de la app (mismo look que
                        // "Crear orden de compra", "Confirmar abono", etc.
                        // — hereda color de `AppTheme.elevatedButtonTheme`),
                        // solo se ajusta el tamaño para que quepa inline.
                        style: ElevatedButton.styleFrom(
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      ),
              ],
            ),
          ],
        ),
      ),
    );
  }

}

class _WarehouseBadge extends StatelessWidget {
  const _WarehouseBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle_rounded, size: 14, color: AppColors.onSurfaceMuted),
          SizedBox(width: 6),
          Text('En almacén', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.onSurfaceMuted)),
        ],
      ),
    );
  }
}
