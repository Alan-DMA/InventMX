import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../sales_pos/domain/payment_entry.dart';
import '../../../sales_pos/presentation/widgets/payment_modal.dart' show PaymentMethodIconX;
import '../../domain/cash_session.dart';

/// Paso 2 del wizard de arqueo — "Resumen y Confirmación" (Subtarea 9.2.3).
///
/// Diseño propio (Eduardo dejó este paso a criterio, manteniendo la sintonía
/// visual del Paso 1): mismas tarjetas `surface`/`border`, misma tipografía
/// monoespaciada para montos, mismo lenguaje de acento `skyBlue`.
///
/// Trazabilidad: Doc. Maestro RF-18/RF-19 · HU-15 / CU-18
class DigitalSummaryStep extends StatelessWidget {
  const DigitalSummaryStep({
    super.key,
    required this.digitalTotals,
    required this.expectedCashMxn,
    required this.physicalCashMxn,
  });

  final Map<PaymentMethodMxn, double> digitalTotals;
  final double expectedCashMxn;
  final double physicalCashMxn;

  double get _differenceMxn => physicalCashMxn - expectedCashMxn;

  CashBalanceResult get _balanceResult {
    if (_differenceMxn.abs() < 0.005) return CashBalanceResult.exact;
    return _differenceMxn < 0 ? CashBalanceResult.short : CashBalanceResult.over;
  }

  Color _resultColor() => switch (_balanceResult) {
        CashBalanceResult.exact => AppColors.emerald,
        CashBalanceResult.short => AppColors.error,
        CashBalanceResult.over => AppColors.warning,
      };

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Resumen y Confirmación',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppColors.onSurface,
          ),
        ),
        const SizedBox(height: 2),
        const Text(
          'Coteja los cobros digitales del turno antes de confirmar el cierre',
          style: TextStyle(fontSize: 12, color: AppColors.onSurfaceMuted),
        ),
        const SizedBox(height: 16),
        _buildDigitalPaymentsCard(),
        const SizedBox(height: 20),
        _buildComparisonCard(),
      ],
    );
  }

  Widget _buildDigitalPaymentsCard() {
    if (digitalTotals.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: const Text(
          'Sin cobros digitales registrados en este turno.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: AppColors.onSurfaceMuted),
        ),
      );
    }

    final methods = digitalTotals.keys.toList();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          for (var i = 0; i < methods.length; i++) ...[
            if (i > 0) const Divider(height: 1, color: AppColors.border),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceVariant,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(methods[i].icon, size: 18, color: AppColors.skyBlue),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      methods[i].label,
                      style: const TextStyle(fontSize: 14, color: AppColors.onSurface),
                    ),
                  ),
                  Text(
                    '\$${digitalTotals[methods[i]]!.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.onSurface,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildComparisonCard() {
    final resultColor = _resultColor();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _comparisonRow('Efectivo esperado', expectedCashMxn, AppColors.onSurfaceMuted),
          const SizedBox(height: 8),
          _comparisonRow('Efectivo físico contado', physicalCashMxn, AppColors.onSurface),
          const SizedBox(height: 12),
          const Divider(height: 1, color: AppColors.border),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: resultColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _balanceResult.label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: resultColor,
                  ),
                ),
              ),
              Text(
                '${_differenceMxn >= 0 ? '+' : '-'}\$${_differenceMxn.abs().toStringAsFixed(2)}',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: resultColor,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _comparisonRow(String label, double amountMxn, Color valueColor) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontSize: 14, color: AppColors.onSurfaceMuted),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '\$${amountMxn.toStringAsFixed(2)}',
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: valueColor,
          ),
        ),
      ],
    );
  }
}
