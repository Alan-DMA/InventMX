import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../data/saas_repository.dart';
import '../domain/subscription.dart';
import 'saas_provider.dart';
import 'widgets/cycle_line.dart';

/// Punto de conexión de la renovación dentro de la app (P13).
///
/// Hoy el servidor responde `renewal_channel: NONE` y el botón ni aparece. El
/// día que se integre Google Play, el servidor cambia a `GOOGLE_PLAY` y aquí se
/// sobrescribe esta función con el flujo de compra de Play: la pantalla no
/// cambia. Hasta entonces, si el canal llega sin la integración, lo dice.
final renewalActionProvider =
    Provider<Future<void> Function(BuildContext context)>((ref) {
  return (context) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Renovación en camino'),
        content: const Text(
          'Muy pronto podrás renovar desde aquí. Mientras tanto, escríbenos '
          'y lo resolvemos por ti.',
          style: TextStyle(height: 1.4),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Entendido')),
        ],
      ),
    );
  };
});

/// Mi suscripción — informativa (P9–P13, Sep 2026).
///
/// Dirección "Línea del ciclo": plan y estado → la línea con fechas exactas →
/// renovar (sólo cuando exista el cobro en la app) → uso del plan → lo que
/// soporte hizo en su cuenta y por qué (P8). **Sin formas de pago**: hasta
/// integrar Google Play la app no ofrece ninguna (política de Play).
///
/// Se alcanza también desde la suspensión: la ruta vive fuera del shell del
/// dashboard y el redirect de HARD_LOCK la deja pasar.
class MySubscriptionScreen extends ConsumerWidget {
  const MySubscriptionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subAsync = ref.watch(subscriptionProvider);

    return Scaffold(
      backgroundColor: AppColors.darkSlate,
      appBar: AppBar(
        backgroundColor: AppColors.darkSlate,
        elevation: 0,
        title: const Text(
          'Mi suscripción',
          style: TextStyle(
              fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.onSurface),
        ),
      ),
      body: subAsync.when(
        loading: () => const _Skeleton(),
        error: (e, _) => _ErrorState(
          message: e is SaasException ? e.message : 'No pudimos cargar tu suscripción.',
          onRetry: () => ref.read(subscriptionProvider.notifier).refresh(),
        ),
        data: (sub) {
          if (sub == null) {
            return const _ErrorState(message: 'Inicia sesión para ver tu suscripción.');
          }
          final now = ref.watch(clockProvider)();
          return RefreshIndicator(
            color: AppColors.emerald,
            onRefresh: () async {
              ref.invalidate(supportActivityProvider);
              await ref.read(subscriptionProvider.notifier).refresh();
            },
            child: ListView(
              // Columna acotada en tablet (regla de clases de tamaño de Android).
              padding: EdgeInsets.fromLTRB(_gutter(context), 4, _gutter(context),
                  32 + MediaQuery.of(context).padding.bottom),
              children: [
                _PlanHeader(sub: sub),
                const SizedBox(height: 14),
                if (sub.paidUntil != null && sub.graceUntil != null) ...[
                  _Card(
                    child: CycleLine(
                      paidUntil: sub.paidUntil!,
                      graceUntil: sub.graceUntil!,
                      entitlement: sub.entitlement,
                      now: now,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                _RenewalCard(sub: sub),
                const SizedBox(height: 12),
                _UsageCard(sub: sub),
                const SizedBox(height: 24),
                const Text(
                  'Actividad de soporte',
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.onSurface),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Lo que el equipo de Nexus cambió en tu suscripción, y por qué.',
                  style: TextStyle(fontSize: 12.5, color: AppColors.onSurfaceMuted),
                ),
                const SizedBox(height: 10),
                const _SupportActivityList(),
              ],
            ),
          );
        },
      ),
    );
  }

  static double _gutter(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    return w > 632 ? (w - 600) / 2 : 16;
  }
}

// ---------------------------------------------------------------------------
// Piezas
// ---------------------------------------------------------------------------

class _PlanHeader extends StatelessWidget {
  const _PlanHeader({required this.sub});
  final Subscription sub;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch ((sub.status, sub.entitlement)) {
      (SubscriptionStatus.hardLock, _) => ('Suspendida', AppColors.error),
      (SubscriptionStatus.softLock, _) => ('Solo lectura', AppColors.warning),
      (_, Entitlement.gracia) => ('En gracia', AppColors.warning),
      _ => ('Activa', AppColors.emerald),
    };
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Plan ${sub.plan.label}',
                key: const Key('subscriptionPlanName'),
                style: const TextStyle(
                    fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.onSurface),
              ),
              const SizedBox(height: 2),
              Text(
                '${mxn(sub.monthlyFeeMxn)} MXN al mes',
                style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.onSurfaceMuted,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
        Container(
          key: const Key('subscriptionStatusChip'),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(label,
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: color)),
        ),
      ],
    );
  }
}

/// Renovar: sólo si el servidor anuncia un canal (P13). Sin él no hay botón,
/// ni instrucciones de pago, ni enlaces: sólo qué pasa y a quién acudir.
class _RenewalCard extends ConsumerWidget {
  const _RenewalCard({required this.sub});
  final Subscription sub;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(clockProvider)();
    final message = switch (sub.entitlement) {
      Entitlement.gracia =>
        'Tu suscripción venció el ${longDate(sub.paidUntil!)}. Conservas acceso completo '
            'hasta el ${longDate(sub.graceUntil!)}; después la cuenta se suspende hasta renovar.',
      Entitlement.vencida =>
        'Tu cuenta está suspendida. Tus productos, ventas y reportes siguen guardados: '
            'al renovar, todo vuelve como estaba.',
      _ when sub.paidUntil != null =>
        'Tu plan está pagado hasta el ${longDate(sub.paidUntil!)}'
            '${(sub.daysUntilDue(now) ?? 0) > 0 ? ' (${sub.daysUntilDue(now)} días)' : ''}.',
      _ => 'Tu plan está activo.',
    };

    return _Card(
      key: const Key('subscriptionRenewalCard'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(message,
              style: const TextStyle(fontSize: 14, color: AppColors.onSurface, height: 1.45)),
          const SizedBox(height: 12),
          if (sub.canRenewInApp)
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton(
                key: const Key('subscriptionRenewButton'),
                onPressed: () => ref.read(renewalActionProvider)(context),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.emerald,
                  foregroundColor: AppColors.darkSlate,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text('Renovar por ${mxn(sub.monthlyFeeMxn)}',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              ),
            )
          else
            const Text(
              'Muy pronto podrás renovar desde la app. Si necesitas renovar o cambiar '
              'de plan antes, escríbenos y lo resolvemos por ti.',
              key: Key('subscriptionRenewalSoon'),
              style: TextStyle(fontSize: 12.5, color: AppColors.onSurfaceMuted, height: 1.4),
            ),
        ],
      ),
    );
  }
}

class _UsageCard extends StatelessWidget {
  const _UsageCard({required this.sub});
  final Subscription sub;

  @override
  Widget build(BuildContext context) {
    final ratio = sub.usersLimit == 0 ? 0.0 : (sub.usersCount / sub.usersLimit).clamp(0.0, 1.0);
    return _Card(
      child: Row(
        children: [
          const Icon(Icons.people_alt_outlined, size: 20, color: AppColors.onSurfaceMuted),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${sub.usersCount} de ${sub.usersLimit} usuarios',
                  key: const Key('subscriptionUsers'),
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.onSurface),
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: ratio,
                    minHeight: 4,
                    backgroundColor: AppColors.surfaceVariant,
                    color: ratio >= 1 ? AppColors.warning : AppColors.emerald,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SupportActivityList extends ConsumerWidget {
  const _SupportActivityList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activity = ref.watch(supportActivityProvider);
    return activity.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator(color: AppColors.emerald, strokeWidth: 2)),
      ),
      error: (e, _) => Text(
        e is SaasException ? e.message : 'No pudimos cargar la actividad de soporte.',
        style: const TextStyle(color: AppColors.onSurfaceMuted),
      ),
      data: (items) => items.isEmpty
          ? const _Card(
              key: Key('supportActivityEmpty'),
              child: Text(
                'Soporte no ha hecho cambios en tu suscripción.',
                style: TextStyle(color: AppColors.onSurfaceMuted),
              ),
            )
          : Column(children: [for (final item in items) _ActivityRow(item: item)]),
    );
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.item});
  final SupportActivity item;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(item.summary,
              style: const TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.onSurface, height: 1.35)),
          if (item.reason != null && item.reason!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('Motivo: ${item.reason}',
                style: const TextStyle(fontSize: 13, color: AppColors.onSurface, height: 1.4)),
          ],
          const SizedBox(height: 6),
          Text('${item.by} · ${longDate(item.occurredAt)}',
              style: const TextStyle(fontSize: 11.5, color: AppColors.onSurfaceMuted)),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: child,
      );
}

class _Skeleton extends StatelessWidget {
  const _Skeleton();

  @override
  Widget build(BuildContext context) =>
      const Center(child: CircularProgressIndicator(color: AppColors.emerald));
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, this.onRetry});
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.onSurfaceMuted)),
              if (onRetry != null) ...[
                const SizedBox(height: 12),
                TextButton(onPressed: onRetry, child: const Text('Reintentar')),
              ],
            ],
          ),
        ),
      );
}
