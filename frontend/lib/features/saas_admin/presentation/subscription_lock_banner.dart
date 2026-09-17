import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../domain/subscription.dart';
import 'saas_provider.dart';
import 'widgets/cycle_line.dart';

/// Banner de Soft Lock — Tarea 14.2.3 (Constitución Art. VI §6.3).
///
/// Vive en el shell del dashboard, encima de cualquier pestaña, solo cuando
/// el comercio está en solo lectura. Dice el día N de 10, la fecha exacta del
/// bloqueo total y lleva directo a pagar. Ámbar hasta que el bloqueo esté a
/// ≤ 3 días; entonces rojo. Sin contador, sin urgencia fabricada: es un hecho
/// del sistema, y la misma línea del ciclo de "Mi suscripción", comprimida.
class SubscriptionLockBanner extends ConsumerWidget {
  const SubscriptionLockBanner({super.key, this.now});

  final DateTime? now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sub = ref.watch(subscriptionProvider).valueOrNull;
    final status = ref.watch(subscriptionStatusProvider);
    if (status != SubscriptionStatus.softLock) return const SizedBox.shrink();

    final due = sub?.pendingInvoice?.dueDate;
    final today = now ?? ref.watch(clockProvider)();
    final hardAt = sub?.hardLockAt ?? due?.add(const Duration(days: 11));
    final daysToHard = hardAt == null
        ? null
        : DateTime(hardAt.year, hardAt.month, hardAt.day)
            .difference(DateTime(today.year, today.month, today.day))
            .inDays;
    final urgent = daysToHard != null && daysToHard <= 3;
    final color = urgent ? AppColors.error : AppColors.warning;
    final day = sub?.daysOverdue ?? 0;

    return Material(
      key: const Key('softLockBanner'),
      color: color.withValues(alpha: 0.14),
      child: SafeArea(
        bottom: false,
        child: InkWell(
          onTap: () => context.push(AppRoutes.subscription),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.lock_outline_rounded, size: 18, color: color),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Solo lectura · día ${day.clamp(1, CycleLine.softLockDays)} de ${CycleLine.softLockDays}',
                        key: const Key('softLockBannerTitle'),
                        style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: color),
                      ),
                    ),
                    TextButton(
                      key: const Key('softLockPayNow'),
                      onPressed: () => context.push(AppRoutes.subscription),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.onSurface,
                        backgroundColor: color.withValues(alpha: 0.22),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 6),
                        minimumSize: const Size(0, 44),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                      child: const Text('Pagar ahora',
                          style: TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  hardAt == null
                      ? 'Puedes consultar inventario y reportes; no puedes cobrar ni comprar hasta pagar.'
                      : 'Puedes consultar, no cobrar ni comprar. Bloqueo total el ${longDate(hardAt)}.',
                  style: const TextStyle(
                      fontSize: 12.5, color: AppColors.onSurface, height: 1.3),
                ),
                if (due != null) ...[
                  const SizedBox(height: 8),
                  CycleLine(
                      dueDate: due, status: status, now: today, compact: true),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Guarda de escritura para Soft Lock (D5) — "Cobrar" y "Nueva compra".
///
/// Devuelve `true` si la acción puede continuar. Si no, explica por qué y
/// ofrece ir a pagar. El backend también lo bloquea (403 TENANT_SOFT_LOCK):
/// esto evita abrir un flujo que va a fallar al final.
Future<bool> requireWriteAccess(BuildContext context, WidgetRef ref) async {
  final status = ref.read(subscriptionStatusProvider);
  if (!status.isLocked) return true;

  final goPay = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.surface,
      title: const Text('Tu cuenta está en solo lectura'),
      content: const Text(
        'Puedes consultar todo, pero no registrar ventas ni compras hasta '
        'ponerte al corriente con la mensualidad.',
        style: TextStyle(height: 1.4),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Entendido')),
        FilledButton(
          key: const Key('writeGatePayNow'),
          onPressed: () => Navigator.pop(ctx, true),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.emerald,
            foregroundColor: AppColors.darkSlate,
          ),
          child: const Text('Ir a pagar'),
        ),
      ],
    ),
  );
  if (goPay == true && context.mounted) {
    context.push(AppRoutes.subscription);
  }
  return false;
}
