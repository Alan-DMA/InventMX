import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import '../../domain/account_payable.dart';
import '../../../management/presentation/management_provider.dart';
import '../purchases_provider.dart';
import '../widgets/account_payable_card.dart';
import '../widgets/payment_modal.dart';

/// Tab "Por pagar" del hub — Subtarea 11.2.3 (Tablero de CxP con Semáforo).
class AccountsPayableTab extends ConsumerWidget {
  const AccountsPayableTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(accountsPayableProvider);

    return Column(
      children: [
        if (state.summary != null) _buildSummary(state.summary!),
        if (state.hasError)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _ErrorBanner(
                error: state.error!,
                onRetry: () =>
                    ref.read(accountsPayableProvider.notifier).retry()),
          ),
        Expanded(child: _buildBody(context, ref, state)),
      ],
    );
  }

  Widget _buildSummary(AccountsPayableSummary summary) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          Expanded(
            child: _SummaryCard(
              label: 'Pendiente total',
              value: '\$${summary.totalPendingMxn.toStringAsFixed(0)}',
              color: AppColors.skyBlue,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _SummaryCard(
              label: 'Vencido (${summary.overdueCount})',
              value: '\$${summary.overdueAmountMxn.toStringAsFixed(0)}',
              color: AppColors.error,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(
      BuildContext context, WidgetRef ref, AccountsPayableState state) {
    if (state.isLoading && state.items.isEmpty) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.emerald));
    }

    if (state.items.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle_outline_rounded,
                  size: 56, color: AppColors.success),
              SizedBox(height: 16),
              Text(
                'No tienes cuentas por pagar pendientes',
                style: TextStyle(fontSize: 15, color: AppColors.onSurfaceMuted),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
      itemCount: state.items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, i) {
        final payable = state.items[i];
        return AccountPayableCard(
          payable: payable,
          onPay: ref.watch(canPayCreditProvider)
              ? () => showPaymentModal(context, payable)
              : null,
        );
      },
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard(
      {required this.label, required this.value, required this.color});

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 11, color: AppColors.onSurfaceMuted)),
          const SizedBox(height: 2),
          Text(value,
              style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w700, color: color)),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.error, required this.onRetry});

  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.wifi_off_rounded, size: 18, color: AppColors.error),
          const SizedBox(width: 10),
          const Expanded(
              child: Text('Error de conexión. Revisa tu red.',
                  style: TextStyle(fontSize: 13, color: AppColors.error))),
          TextButton(onPressed: onRetry, child: const Text('Reintentar')),
        ],
      ),
    );
  }
}
