import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../account/presentation/account_provider.dart';
import '../domain/subscription.dart';
import 'saas_provider.dart';
import 'widgets/cycle_line.dart';

/// Banner de la suscripción, encima de cualquier pestaña del dashboard.
///
/// Aparece en dos casos (modelo prepago, P9–P13):
/// - **Gracia**: venció, pero todo funciona hasta el último día de gracia
///   (P10). Ámbar; rojo cuando faltan ≤ 3 días. Dice la fecha exacta de la
///   suspensión — un hecho del sistema, sin contador ni urgencia fabricada.
/// - **Sólo lectura**: soporte la dejó así a mano desde el panel.
class SubscriptionLockBanner extends ConsumerWidget {
  const SubscriptionLockBanner({super.key, this.now});

  final DateTime? now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sub = ref.watch(subscriptionProvider).valueOrNull;
    final status = ref.watch(subscriptionStatusProvider);
    final inGrace = status == SubscriptionStatus.active &&
        sub?.entitlement == Entitlement.gracia;
    if (!inGrace && status != SubscriptionStatus.softLock) {
      return const SizedBox.shrink();
    }

    final today = now ?? ref.watch(clockProvider)();
    final graceLeft = sub?.daysOfGraceLeft(today);
    final urgent = inGrace && graceLeft != null && graceLeft <= 3;
    final color = urgent ? AppColors.error : AppColors.warning;
    // Renovar es cosa del Dueño: a un empleado no se le manda a una pantalla
    // que el router le rebotaría.
    final isOwner = ref.watch(canSeeSubscriptionProvider);

    final title = inGrace
        ? (graceLeft != null && graceLeft > 1
            ? 'Suscripción vencida · $graceLeft días de gracia'
            : 'Suscripción vencida · último día de gracia')
        : 'Solo lectura';
    final body = inGrace
        ? (isOwner
            ? 'Todo funciona normal hasta el ${longDate(sub!.graceUntil!)}; después la cuenta se suspende hasta renovar.'
            : 'Todo funciona normal hasta el ${longDate(sub!.graceUntil!)}. Avísale a quien administra la tienda.')
        : (isOwner
            ? 'Puedes consultar inventario y reportes, pero no cobrar ni comprar. Revisa tu suscripción.'
            : 'Puedes consultar, no cobrar ni comprar. Avísale a quien administra la tienda.');

    return Material(
      key: const Key('softLockBanner'),
      color: color.withValues(alpha: 0.14),
      child: SafeArea(
        bottom: false,
        child: InkWell(
          onTap: isOwner ? () => context.push(AppRoutes.subscription) : null,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(inGrace ? Icons.schedule_rounded : Icons.lock_outline_rounded,
                        size: 18, color: color),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        title,
                        key: const Key('softLockBannerTitle'),
                        style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: color),
                      ),
                    ),
                    if (isOwner)
                      TextButton(
                        key: const Key('softLockPayNow'),
                        onPressed: () => context.push(AppRoutes.subscription),
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.onSurface,
                          backgroundColor: color.withValues(alpha: 0.22),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                          minimumSize: const Size(0, 44),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        child: const Text('Ver',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  body,
                  key: const Key('softLockBannerBody'),
                  style: const TextStyle(fontSize: 12.5, color: AppColors.onSurface, height: 1.3),
                ),
                if (inGrace && sub!.paidUntil != null && sub.graceUntil != null) ...[
                  const SizedBox(height: 8),
                  CycleLine(
                    paidUntil: sub.paidUntil!,
                    graceUntil: sub.graceUntil!,
                    entitlement: Entitlement.gracia,
                    now: today,
                    compact: true,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Guarda de escritura para "Cobrar" y "Nueva compra" cuando la cuenta está
/// en sólo lectura o suspendida. Devuelve `true` si la acción puede seguir.
/// En gracia no bloquea nada (P10). El backend también lo impide (403/402):
/// esto evita abrir un flujo que va a fallar al final.
Future<bool> requireWriteAccess(BuildContext context, WidgetRef ref) async {
  final status = ref.read(subscriptionStatusProvider);
  if (!status.isLocked) return true;
  final isOwner = ref.read(canSeeSubscriptionProvider);

  final goSee = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.surface,
      title: const Text('Tu cuenta está en solo lectura'),
      content: Text(
        isOwner
            ? 'Puedes consultar todo, pero no registrar ventas ni compras por ahora. '
                'En tu suscripción verás qué pasó y cómo resolverlo.'
            : 'Puedes consultar todo, pero no registrar ventas ni compras por ahora. '
                'Avísale a quien administra la tienda.',
        style: const TextStyle(height: 1.4),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Entendido')),
        if (isOwner)
          FilledButton(
            key: const Key('writeGatePayNow'),
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.emerald,
              foregroundColor: AppColors.darkSlate,
            ),
            child: const Text('Ver mi suscripción'),
          ),
      ],
    ),
  );
  if (goSee == true && context.mounted) {
    context.push(AppRoutes.subscription);
  }
  return false;
}
