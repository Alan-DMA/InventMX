import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../domain/account_payable.dart';
import '../purchase_format.dart';

/// Tarjeta de cuenta por pagar con semáforo de vencimiento — Subtarea
/// 11.2.3. Verde: a tiempo · Amarillo: vence en ≤3 días · Rojo: vencida.
class AccountPayableCard extends StatelessWidget {
  const AccountPayableCard({
    super.key,
    required this.payable,
    required this.onPay,
  });

  final AccountPayable payable;

  /// `null` cuando el rol no puede abonar (`purchases.pay_credit`): el botón
  /// no se pinta (Permisos por rol, Fase A).
  final VoidCallback? onPay;

  Color get _urgencyColor => switch (payable.urgency) {
        PayableUrgency.onTime => AppColors.success,
        PayableUrgency.dueSoon => AppColors.warning,
        PayableUrgency.overdue => AppColors.error,
      };

  String get _urgencyLabel => switch (payable.urgency) {
        PayableUrgency.onTime => 'A tiempo',
        PayableUrgency.dueSoon => 'Vence pronto',
        PayableUrgency.overdue => 'Vencida',
      };

  @override
  Widget build(BuildContext context) {
    final color = _urgencyColor;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 4,
            height: 64,
            decoration: BoxDecoration(
                color: color, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        payable.supplierName,
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: AppColors.onSurface),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        _urgencyLabel,
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: color),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Vence: ${formatPurchaseDate(payable.dueDate)}',
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.onSurfaceMuted),
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'SALDO',
                            style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: AppColors.onSurfaceMuted,
                                letterSpacing: 0.5),
                          ),
                          Text(
                            '\$${payable.balanceMxn.toStringAsFixed(2)} MXN',
                            style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: AppColors.onSurface),
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (payable.paidAmountMxn > 0)
                            Text(
                              'Abonado: \$${payable.paidAmountMxn.toStringAsFixed(2)}',
                              style: const TextStyle(
                                  fontSize: 11,
                                  color: AppColors.onSurfaceMuted),
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
                    ),
                    if (onPay != null) ...[
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: onPay,
                        style: ElevatedButton.styleFrom(
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10),
                          textStyle: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                        child: const Text('Registrar abono'),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
