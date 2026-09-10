import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';

/// Barra fija inferior del POS con subtotal y botón "Cobrar".
///
/// Layout fiel a la referencia:
///   SUBTOTAL:
///   $XX.XX          [  Cobrar $XX.XX MXN  ]
class CartTotalsBar extends StatelessWidget {
  const CartTotalsBar({
    super.key,
    required this.totalMxn,
    required this.isEnabled,
    required this.isProcessing,
    required this.onCobrar,
  });

  final double totalMxn;
  final bool isEnabled;
  final bool isProcessing;
  final VoidCallback onCobrar;

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return Container(
      padding: EdgeInsets.fromLTRB(16, 14, 16, bottomPad + 14),
      decoration: const BoxDecoration(
        color: AppColors.darkSlate,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Label SUBTOTAL
          const Text(
            'SUBTOTAL:',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.onSurfaceMuted,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 2),
          // Monto grande
          Text(
            '\$${totalMxn.toStringAsFixed(2)}',
            style: const TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w800,
              color: AppColors.onSurface,
              height: 1,
            ),
          ),
          const SizedBox(height: 12),
          // Botón Cobrar
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              onPressed: isEnabled && !isProcessing ? onCobrar : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.emerald,
                foregroundColor: AppColors.darkSlate,
                disabledBackgroundColor: AppColors.surfaceVariant,
                disabledForegroundColor: AppColors.onSurfaceMuted,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 0,
              ),
              icon: isProcessing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: AppColors.darkSlate,
                      ),
                    )
                  : const Icon(Icons.point_of_sale_rounded, size: 20),
              label: Text(
                isProcessing
                    ? 'Procesando...'
                    : 'Cobrar \$${totalMxn.toStringAsFixed(2)} MXN',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
