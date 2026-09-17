import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../auth/presentation/login_provider.dart';
import '../domain/subscription.dart';
import 'saas_provider.dart';
import 'widgets/cycle_line.dart';

/// Bloqueo total — Tarea 14.2.3 (Constitución Art. VI §6.3, día 11+).
///
/// El router manda aquí cualquier ruta del dashboard mientras el comercio
/// está en HARD_LOCK. Es un usuario en crisis (Cat. 7 del catálogo de
/// anti-patrones): se le dice exactamente qué pasa, qué **no** pierde, cuánto
/// debe y cómo pagar. Dos salidas, ambas honestas: pagar o cerrar sesión.
class HardLockScreen extends ConsumerWidget {
  const HardLockScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sub = ref.watch(subscriptionProvider).valueOrNull;
    final invoice = sub?.pendingInvoice;
    final review = sub?.pendingValidation;

    return Scaffold(
      backgroundColor: AppColors.darkSlate,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
              shrinkWrap: true,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    width: 56,
                    height: 56,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(Icons.lock_rounded,
                        color: AppColors.error, size: 28),
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Tu cuenta está suspendida',
                  key: Key('hardLockTitle'),
                  style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: AppColors.onSurface,
                      height: 1.15),
                ),
                const SizedBox(height: 10),
                Text(
                  invoice == null
                      ? 'Han pasado más de 10 días desde el vencimiento de tu mensualidad.'
                      : 'Tu mensualidad de ${periodLabel(invoice.dueDate)} venció el '
                          '${longDate(invoice.dueDate)} y pasaron más de ${CycleLine.softLockDays} días.',
                  style: const TextStyle(
                      fontSize: 15, color: AppColors.onSurface, height: 1.45),
                ),
                const SizedBox(height: 16),
                const _Fact(
                  icon: Icons.inventory_2_outlined,
                  text:
                      'Tus productos, ventas y reportes siguen guardados. No se borra nada.',
                ),
                const _Fact(
                  icon: Icons.bolt_rounded,
                  text:
                      'En cuanto validemos tu pago, la cuenta se reactiva sola.',
                ),
                if (review != null &&
                    review.status == ValidationStatus.pendiente)
                  _Fact(
                    icon: Icons.hourglass_top_rounded,
                    color: AppColors.skyBlue,
                    text:
                        'Ya recibimos tu aviso de pago (ref. ${review.reference}). Lo estamos validando.',
                  ),
                const SizedBox(height: 20),
                if (invoice != null) ...[
                  Container(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('A pagar',
                            style: TextStyle(
                                fontSize: 12, color: AppColors.onSurfaceMuted)),
                        const SizedBox(height: 4),
                        Text(
                          '${mxn(invoice.amountMxn)} MXN',
                          key: const Key('hardLockAmount'),
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            color: AppColors.onSurface,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                        const SizedBox(height: 12),
                        CycleLine(
                          dueDate: invoice.dueDate,
                          status: SubscriptionStatus.hardLock,
                          now: ref.watch(clockProvider)(),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
                SizedBox(
                  height: 52,
                  child: FilledButton.icon(
                    key: const Key('hardLockPayButton'),
                    onPressed: () => context.push(AppRoutes.subscription),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.emerald,
                      foregroundColor: AppColors.darkSlate,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.account_balance_outlined),
                    label: const Text('Ver cómo pagar',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700)),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 48,
                  child: TextButton(
                    key: const Key('hardLockLogout'),
                    onPressed: () => ref.read(loginProvider.notifier).logout(),
                    style: TextButton.styleFrom(
                        foregroundColor: AppColors.onSurfaceMuted),
                    child: const Text('Cerrar sesión',
                        style: TextStyle(fontSize: 15)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact(
      {required this.icon,
      required this.text,
      this.color = AppColors.onSurfaceMuted});
  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(
                    fontSize: 14, color: AppColors.onSurface, height: 1.4),
              ),
            ),
          ],
        ),
      );
}
