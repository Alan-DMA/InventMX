import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../data/saas_repository.dart';
import '../domain/subscription.dart';
import 'saas_provider.dart';
import 'widgets/cycle_line.dart';
import 'widgets/payment_cards.dart';
import 'widgets/plan_card.dart';
import 'widgets/report_payment_sheet.dart';

/// Mi suscripción — Tarea 14.2.1 (HU-22 / CU-28, Constitución Art. V y VI).
///
/// Dirección "Línea del ciclo": el mes se ve antes que el cobro. Orden de la
/// pantalla: plan y estado → línea del ciclo con fechas exactas → monto a
/// pagar → SPEI | OXXO → "Ya pagué" → cambiar plan → historial.
///
/// Se alcanza también desde el bloqueo total: la ruta vive fuera del shell
/// del dashboard y el redirect de HARD_LOCK la deja pasar.
class SubscriptionCheckoutScreen extends ConsumerStatefulWidget {
  const SubscriptionCheckoutScreen({super.key});

  @override
  ConsumerState<SubscriptionCheckoutScreen> createState() =>
      _SubscriptionCheckoutScreenState();
}

class _SubscriptionCheckoutScreenState
    extends ConsumerState<SubscriptionCheckoutScreen> {
  SaasPaymentMethod _method = SaasPaymentMethod.spei;
  bool _changingPlan = false;

  Future<void> _reportPayment(Subscription sub) async {
    final invoice = sub.pendingInvoice;
    if (invoice == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final validation = await showReportPaymentSheet(
      context,
      amountMxn: invoice.amountMxn,
      initialMethod: _method == SaasPaymentMethod.oxxo && sub.oxxo == null
          ? SaasPaymentMethod.spei
          : _method,
    );
    if (validation == null || !mounted) return;
    messenger.showSnackBar(const SnackBar(
      content: Text('Recibimos tu aviso. Te avisamos cuando esté validado.'),
      behavior: SnackBarBehavior.floating,
    ));
  }

  Future<void> _changePlan(Subscription sub, SaasPlan plan) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Cambiar a ${plan.name}'),
        content: Text(
          sub.pendingInvoice == null
              ? 'Tu próxima mensualidad será de ${mxn(plan.priceMxn)} MXN.'
              : 'Tu factura pendiente pasa a ${mxn(plan.priceMxn)} MXN '
                  '(antes ${mxn(sub.pendingInvoice!.amountMxn)}). '
                  'El vencimiento no cambia.',
          style: const TextStyle(height: 1.4),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
            key: const Key('confirmChangePlan'),
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.emerald,
              foregroundColor: AppColors.darkSlate,
            ),
            child: const Text('Cambiar plan'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _changingPlan = true);
    try {
      await ref.read(subscriptionProvider.notifier).changePlan(plan.id);
      messenger.showSnackBar(SnackBar(
        content: Text('Ahora tienes el plan ${plan.name}.'),
        behavior: SnackBarBehavior.floating,
      ));
    } on SaasException catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text(e.message),
        behavior: SnackBarBehavior.floating,
      ));
    } catch (_) {
      messenger.showSnackBar(const SnackBar(
        content: Text('No se pudo cambiar el plan. Inténtalo de nuevo.'),
        behavior: SnackBarBehavior.floating,
      ));
    } finally {
      if (mounted) setState(() => _changingPlan = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final subAsync = ref.watch(subscriptionProvider);

    return Scaffold(
      backgroundColor: AppColors.darkSlate,
      appBar: AppBar(
        backgroundColor: AppColors.darkSlate,
        elevation: 0,
        title: const Text(
          'Mi suscripción',
          style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppColors.onSurface),
        ),
      ),
      body: subAsync.when(
        loading: () => const _Skeleton(),
        error: (e, _) => _ErrorState(
          message: e is SaasException
              ? e.message
              : 'No pudimos cargar tu suscripción.',
          onRetry: () => ref.read(subscriptionProvider.notifier).refresh(),
        ),
        data: (sub) {
          if (sub == null) {
            return const _ErrorState(
                message: 'Inicia sesión para ver tu suscripción.');
          }
          return RefreshIndicator(
            color: AppColors.emerald,
            onRefresh: () => ref.read(subscriptionProvider.notifier).refresh(),
            child: ListView(
              // Columna acotada en tablet (regla de clases de tamaño de Android).
              padding: EdgeInsets.fromLTRB(_gutter(context), 4,
                  _gutter(context), 32 + MediaQuery.of(context).padding.bottom),
              children: [
                _PlanHeader(sub: sub),
                const SizedBox(height: 14),
                if (sub.pendingInvoice != null) ...[
                  _Card(
                    child: CycleLine(
                      dueDate: sub.pendingInvoice!.dueDate,
                      status: sub.status,
                      now: ref.watch(clockProvider)(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _AmountCard(sub: sub),
                  const SizedBox(height: 16),
                  _sectionTitle('Cómo pagar'),
                  const SizedBox(height: 8),
                  SegmentedButton<SaasPaymentMethod>(
                    key: const Key('paymentMethodSegment'),
                    segments: const [
                      ButtonSegment(
                        value: SaasPaymentMethod.spei,
                        label: Text('SPEI'),
                        icon: Icon(Icons.account_balance_outlined, size: 18),
                      ),
                      ButtonSegment(
                        value: SaasPaymentMethod.oxxo,
                        label: Text('OXXO'),
                        icon: Icon(Icons.storefront_outlined, size: 18),
                      ),
                    ],
                    selected: {_method},
                    onSelectionChanged: (s) =>
                        setState(() => _method = s.first),
                    style: ButtonStyle(
                      side: WidgetStateProperty.all(
                          const BorderSide(color: AppColors.border)),
                      backgroundColor: WidgetStateProperty.resolveWith(
                        (states) => states.contains(WidgetState.selected)
                            ? AppColors.emerald.withValues(alpha: 0.18)
                            : Colors.transparent,
                      ),
                      foregroundColor:
                          WidgetStateProperty.all(AppColors.onSurface),
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (_method == SaasPaymentMethod.spei && sub.spei != null)
                    SpeiInstructionsCard(spei: sub.spei!)
                  else if (_method == SaasPaymentMethod.oxxo)
                    OxxoInstructionsCard(
                      oxxo: sub.oxxo,
                      amountMxn: sub.pendingInvoice!.amountMxn,
                    ),
                  const SizedBox(height: 14),
                  _ReportButton(sub: sub, onPressed: () => _reportPayment(sub)),
                ] else
                  const _Card(
                    child: Text(
                      'No tienes ninguna mensualidad pendiente.',
                      style: TextStyle(color: AppColors.onSurfaceMuted),
                    ),
                  ),
                const SizedBox(height: 24),
                _sectionTitle('Cambiar plan'),
                const SizedBox(height: 4),
                const Text(
                  'Precios mensuales en pesos. Tu plan actual está marcado.',
                  style: TextStyle(
                      fontSize: 12.5, color: AppColors.onSurfaceMuted),
                ),
                const SizedBox(height: 10),
                _PlansList(
                  sub: sub,
                  busy: _changingPlan,
                  onSelect: (plan) => _changePlan(sub, plan),
                ),
                const SizedBox(height: 24),
                _sectionTitle('Historial de pagos'),
                const SizedBox(height: 10),
                const _InvoiceHistory(),
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

  Widget _sectionTitle(String t) => Text(
        t,
        style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: AppColors.onSurface),
      );
}

// ---------------------------------------------------------------------------
// Piezas
// ---------------------------------------------------------------------------

class _PlanHeader extends StatelessWidget {
  const _PlanHeader({required this.sub});
  final Subscription sub;

  @override
  Widget build(BuildContext context) {
    final plan = sub.plan;
    final chipColor = switch (sub.status) {
      SubscriptionStatus.active => AppColors.emerald,
      SubscriptionStatus.softLock => AppColors.warning,
      SubscriptionStatus.hardLock => AppColors.error,
    };
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                plan == null ? 'Sin plan asignado' : 'Plan ${plan.name}',
                key: const Key('planHeader'),
                style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.onSurface),
              ),
              const SizedBox(height: 2),
              Text(
                plan == null
                    ? sub.tenantName
                    : '${mxn(plan.priceMxn)} MXN al mes · ${sub.tenantName}',
                style: const TextStyle(
                    fontSize: 12.5, color: AppColors.onSurfaceMuted),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: chipColor.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            sub.status.label,
            key: const Key('statusChip'),
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w700, color: chipColor),
          ),
        ),
      ],
    );
  }
}

class _AmountCard extends StatelessWidget {
  const _AmountCard({required this.sub});
  final Subscription sub;

  @override
  Widget build(BuildContext context) {
    final inv = sub.pendingInvoice!;
    final review = sub.pendingValidation;
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'A pagar',
            style: TextStyle(fontSize: 12, color: AppColors.onSurfaceMuted),
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                mxn(inv.amountMxn),
                key: const Key('amountDue'),
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  color: AppColors.onSurface,
                  fontFeatures: [FontFeature.tabularFigures()],
                  height: 1.05,
                ),
              ),
              const SizedBox(width: 6),
              const Text(
                'MXN',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.onSurfaceMuted),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${periodLabel(inv.dueDate)} · vence el ${longDate(inv.dueDate)}',
            style:
                const TextStyle(fontSize: 13, color: AppColors.onSurfaceMuted),
          ),
          if (review != null) ...[
            const SizedBox(height: 12),
            _ReviewStrip(validation: review),
          ],
        ],
      ),
    );
  }
}

/// Estado del aviso de pago — siempre visible mientras exista.
class _ReviewStrip extends StatelessWidget {
  const _ReviewStrip({required this.validation});
  final PaymentValidation validation;

  @override
  Widget build(BuildContext context) {
    final (color, icon, title, body) = switch (validation.status) {
      ValidationStatus.pendiente => (
          AppColors.skyBlue,
          Icons.hourglass_top_rounded,
          'Recibimos tu aviso',
          '${validation.method.label} · ref. ${validation.reference}. Un fundador lo revisa en el banco y te avisamos aquí.',
        ),
      ValidationStatus.rechazada => (
          AppColors.warning,
          Icons.info_outline_rounded,
          'No encontramos tu pago',
          validation.notes?.isNotEmpty == true
              ? '${validation.notes} — Revisa y vuelve a avisarnos.'
              : 'Revisa la referencia y vuelve a avisarnos.',
        ),
      ValidationStatus.aprobada => (
          AppColors.emerald,
          Icons.check_circle_outline_rounded,
          'Pago validado',
          'Gracias. Tu cuenta está al corriente.',
        ),
    };
    return Container(
      key: const Key('reviewStrip'),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: color)),
                const SizedBox(height: 2),
                Text(body,
                    style: const TextStyle(
                        fontSize: 12.5,
                        color: AppColors.onSurface,
                        height: 1.35)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ReportButton extends StatelessWidget {
  const _ReportButton({required this.sub, required this.onPressed});
  final Subscription sub;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final inReview = sub.hasPaymentInReview;
    return SizedBox(
      height: 52,
      child: FilledButton.icon(
        key: const Key('reportPaymentButton'),
        onPressed: inReview ? null : onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.emerald,
          foregroundColor: AppColors.darkSlate,
          disabledBackgroundColor: AppColors.surfaceVariant,
          disabledForegroundColor: AppColors.onSurfaceMuted,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        icon:
            Icon(inReview ? Icons.hourglass_top_rounded : Icons.check_rounded),
        label: Text(
          inReview ? 'Aviso en revisión' : 'Ya pagué',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

class _PlansList extends ConsumerWidget {
  const _PlansList(
      {required this.sub, required this.busy, required this.onSelect});
  final Subscription sub;
  final bool busy;
  final ValueChanged<SaasPlan> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plans = ref.watch(saasPlansProvider);
    return plans.when(
      loading: () => const _Card(child: SizedBox(height: 40)),
      error: (_, __) => const _Card(
        child: Text('No se pudieron cargar los planes.',
            style: TextStyle(color: AppColors.onSurfaceMuted)),
      ),
      data: (list) => Column(
        children: [
          for (final plan in list) ...[
            PlanCard(
              plan: plan,
              isCurrent: plan.id == sub.plan?.id,
              busy: busy || sub.hasPaymentInReview,
              onSelect: () => onSelect(plan),
            ),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

class _InvoiceHistory extends ConsumerWidget {
  const _InvoiceHistory();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final invoices = ref.watch(saasInvoicesProvider);
    return invoices.when(
      loading: () => const _Card(child: SizedBox(height: 40)),
      error: (_, __) => const _Card(
        child: Text('No se pudo cargar el historial.',
            style: TextStyle(color: AppColors.onSurfaceMuted)),
      ),
      data: (list) {
        if (list.isEmpty) {
          return const _Card(
            child: Text('Aún no hay pagos registrados.',
                style: TextStyle(color: AppColors.onSurfaceMuted)),
          );
        }
        return _Card(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (var i = 0; i < list.length; i++) ...[
                if (i > 0) const Divider(height: 1, color: AppColors.border),
                _InvoiceRow(invoice: list[i]),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _InvoiceRow extends StatelessWidget {
  const _InvoiceRow({required this.invoice});
  final SubscriptionInvoice invoice;

  @override
  Widget build(BuildContext context) {
    final color = switch (invoice.status) {
      InvoiceStatus.pagada => AppColors.emerald,
      InvoiceStatus.pendiente => AppColors.warning,
      InvoiceStatus.cancelada => AppColors.onSurfaceMuted,
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  periodLabel(invoice.dueDate),
                  style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.onSurface),
                ),
                const SizedBox(height: 2),
                Text(
                  '${invoice.planName ?? 'Plan'} · vence ${shortDate(invoice.dueDate)}',
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.onSurfaceMuted),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                mxn(invoice.amountMxn),
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.onSurface,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: 2),
              Text(
                invoice.status.label,
                style: TextStyle(
                    fontSize: 11.5, fontWeight: FontWeight.w700, color: color),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child, this.padding});
  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) => Container(
        padding: padding ?? const EdgeInsets.fromLTRB(16, 14, 16, 14),
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
  Widget build(BuildContext context) {
    Widget block(double h) => Container(
          height: h,
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
          ),
        );
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      children: [block(44), block(110), block(96), block(48), block(220)],
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, this.onRetry});
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded,
                size: 40, color: AppColors.onSurfaceMuted),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 14.5, color: AppColors.onSurface, height: 1.4),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: onRetry,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.onSurface,
                  side: const BorderSide(color: AppColors.border),
                ),
                child: const Text('Reintentar'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
