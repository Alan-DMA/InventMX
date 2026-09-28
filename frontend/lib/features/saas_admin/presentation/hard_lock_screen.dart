import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../account/presentation/account_provider.dart';
import '../../auth/presentation/login_provider.dart';
import '../domain/subscription.dart';
import 'saas_provider.dart';
import 'subscription_screen.dart';
import 'widgets/cycle_line.dart';

/// Cuenta suspendida (modelo prepago, P9–P13).
///
/// El router manda aquí cualquier ruta del dashboard mientras el comercio está
/// en HARD_LOCK. Es un usuario en crisis (Cat. 7 del catálogo de
/// anti-patrones): se le dice exactamente qué pasa, qué **no** pierde y cómo
/// salir. Desde P13 el comercio suspendido sí inicia sesión, para poder
/// renovar desde la app el día que exista el cobro con Google Play.
class HardLockScreen extends ConsumerWidget {
  const HardLockScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sub = ref.watch(subscriptionProvider).valueOrNull;
    final isOwner = ref.watch(canSeeSubscriptionProvider);
    final since = sub?.graceUntil;

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
                    child: const Icon(Icons.lock_rounded, color: AppColors.error, size: 28),
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Tu cuenta está suspendida',
                  key: Key('hardLockTitle'),
                  style: TextStyle(
                      fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.onSurface, height: 1.15),
                ),
                const SizedBox(height: 10),
                Text(
                  sub?.paidUntil == null
                      ? 'La suscripción de la tienda no está vigente.'
                      : 'La suscripción venció el ${longDate(sub!.paidUntil!)} y terminaron los días de gracia.',
                  key: const Key('hardLockReason'),
                  style: const TextStyle(fontSize: 15, color: AppColors.onSurface, height: 1.45),
                ),
                const SizedBox(height: 16),
                const _Fact(
                  icon: Icons.inventory_2_outlined,
                  text: 'Tus productos, ventas y reportes siguen guardados. No se borra nada.',
                ),
                const _Fact(
                  icon: Icons.bolt_rounded,
                  text: 'Al renovar, la cuenta se reactiva de inmediato.',
                ),
                if (sub != null && sub.paidUntil != null && since != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: CycleLine(
                      paidUntil: sub.paidUntil!,
                      graceUntil: since,
                      entitlement: Entitlement.vencida,
                      now: ref.watch(clockProvider)(),
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                // Renovar es del Dueño; el empleado sólo puede avisar y cerrar sesión.
                if (isOwner) ...[
                  if (sub?.canRenewInApp ?? false)
                    _PrimaryButton(
                      key: const Key('hardLockRenewButton'),
                      label: 'Renovar por ${mxn(sub!.monthlyFeeMxn)}',
                      icon: Icons.autorenew_rounded,
                      onPressed: () => ref.read(renewalActionProvider)(context),
                    )
                  else
                    const Text(
                      'Muy pronto podrás renovar desde la app. Mientras tanto, escríbenos y la '
                      'reactivamos por ti.',
                      key: Key('hardLockContactUs'),
                      style: TextStyle(fontSize: 14, color: AppColors.onSurfaceMuted, height: 1.4),
                    ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 48,
                    child: OutlinedButton(
                      key: const Key('hardLockSeeSubscription'),
                      onPressed: () => context.push(AppRoutes.subscription),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.onSurface,
                        side: const BorderSide(color: AppColors.border),
                        minimumSize: const Size(0, 48),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('Ver mi suscripción'),
                    ),
                  ),
                ] else
                  const Text(
                    'Avísale a quien administra la tienda para que la renueve.',
                    key: Key('hardLockTellOwner'),
                    style: TextStyle(fontSize: 14, color: AppColors.onSurfaceMuted, height: 1.4),
                  ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 48,
                  child: TextButton(
                    key: const Key('hardLockLogout'),
                    onPressed: () => ref.read(loginProvider.notifier).logout(),
                    style: TextButton.styleFrom(foregroundColor: AppColors.onSurfaceMuted),
                    child: const Text('Cerrar sesión', style: TextStyle(fontSize: 15)),
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

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({super.key, required this.label, required this.icon, required this.onPressed});
  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 52,
        child: FilledButton.icon(
          onPressed: onPressed,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.emerald,
            foregroundColor: AppColors.darkSlate,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          icon: Icon(icon),
          label: Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        ),
      );
}

class _Fact extends StatelessWidget {
  const _Fact({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: AppColors.onSurfaceMuted),
            const SizedBox(width: 10),
            Expanded(
              child: Text(text,
                  style: const TextStyle(fontSize: 14, color: AppColors.onSurface, height: 1.4)),
            ),
          ],
        ),
      );
}
