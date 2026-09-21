import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';

/// Monedas soportadas para visualización rápida en el Centro de Mando.
enum DisplayCurrency {
  mxn('MXN', 'Pesos Mexicanos'),
  usd('USD', 'Dólar Estadounidense');

  const DisplayCurrency(this.code, this.label);
  final String code;
  final String label;
}

/// Provider para la moneda activa de visualización en el Dashboard.
final activeCurrencyProvider = StateProvider<DisplayCurrency>((ref) {
  return DisplayCurrency.mxn;
});

/// Selector de moneda estilo dropdown / pill para el AppBar superior.
class CurrencySelector extends ConsumerWidget {
  const CurrencySelector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(activeCurrencyProvider);

    return PopupMenuButton<DisplayCurrency>(
      key: const Key('homeCurrencySelector'),
      initialValue: current,
      onSelected: (currency) {
        ref.read(activeCurrencyProvider.notifier).state = currency;
      },
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.border),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              current.code,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: AppColors.onSurface,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 16,
              color: AppColors.onSurfaceMuted,
            ),
          ],
        ),
      ),
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: DisplayCurrency.mxn,
          child: Text(
            'MXN · Peso Mexicano',
            style: TextStyle(color: AppColors.onSurface, fontSize: 13),
          ),
        ),
        const PopupMenuItem(
          value: DisplayCurrency.usd,
          child: Text(
            'USD · Dólar (USD)',
            style: TextStyle(color: AppColors.onSurface, fontSize: 13),
          ),
        ),
      ],
    );
  }
}
