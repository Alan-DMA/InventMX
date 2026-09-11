import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../domain/banxico_denomination.dart';
import '../../domain/cash_denomination_entry.dart';

/// Color de acento por tipo de denominación — billetes vs. monedas — para
/// identificarlos de un vistazo en el dropdown "Tipo" y en el desglose,
/// ya que ambos conviven mezclados en la misma lista/tabla.
Color kindColor(DenominationKind kind) =>
    kind == DenominationKind.bill ? AppColors.skyBlue : AppColors.warning;

/// Fila de una denominación ya agregada al desglose — hermana de
/// `PaymentRowTile` (Tarea 7.2), mismo patrón visual.
class CashCountRowTile extends StatelessWidget {
  const CashCountRowTile({
    super.key,
    required this.entry,
    required this.onRemove,
  });

  final CashDenominationEntry entry;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final d = entry.denomination;
    final unitsLabel = entry.quantity == 1 ? 'ud' : 'uds';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: kindColor(d.kind).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              d.kind == DenominationKind.bill
                  ? Icons.attach_money_rounded
                  : Icons.circle_outlined,
              size: 20,
              color: kindColor(d.kind),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        d.kind.label,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.onSurfaceMuted),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '\$${d.displayValue}',
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.onSurface,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text.rich(
                  TextSpan(
                    text: 'Cantidad: ',
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.onSurfaceMuted),
                    children: [
                      TextSpan(
                        text: '${entry.quantity} $unitsLabel',
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w700,
                          color: AppColors.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Text(
            '\$${entry.subtotalMxn.toStringAsFixed(2)}',
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.onSurface,
            ),
          ),
          IconButton(
            tooltip: 'Eliminar',
            icon: const Icon(Icons.delete_outline_rounded,
                size: 20, color: AppColors.error),
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}
