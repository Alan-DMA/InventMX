import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../domain/cash_session.dart';
import 'cash_session_provider.dart';
import 'widgets/close_session_wizard.dart';

/// Pantalla principal de la tab "Caja" — Tarea 9.2.
///
/// Reemplaza `CashPlaceholder`: muestra el turno activo (cajero, fondo
/// inicial, apertura, efectivo esperado en vivo) y el botón para iniciar el
/// asistente de cierre (`CloseSessionWizard`).
///
/// Trazabilidad: Constitución Art. VII (7.2) · Doc. Maestro RF-18 · HU-15
class CashSessionScreen extends ConsumerStatefulWidget {
  const CashSessionScreen({super.key});

  @override
  ConsumerState<CashSessionScreen> createState() => _CashSessionScreenState();
}

class _CashSessionScreenState extends ConsumerState<CashSessionScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(cashSessionProvider.notifier).ensureOpenSession();
    });
  }

  Future<void> _openCloseWizard() async {
    final closed = await Navigator.of(context).push<CashSession>(
      MaterialPageRoute(builder: (_) => const CloseSessionWizard()),
    );
    if (closed == null || !mounted) return;

    final resultColor = switch (closed.balanceResult) {
      CashBalanceResult.exact => AppColors.emerald,
      CashBalanceResult.short => AppColors.error,
      CashBalanceResult.over => AppColors.warning,
      null => AppColors.onSurfaceMuted,
    };

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.check_circle_rounded, color: resultColor, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Turno cerrado — ${closed.balanceResult?.label ?? ''} '
                '(\$${closed.differenceMxn?.abs().toStringAsFixed(2) ?? '0.00'} MXN)',
                style: const TextStyle(color: AppColors.onSurface),
              ),
            ),
          ],
        ),
        backgroundColor: AppColors.surface,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
      ),
    );

    // Permite seguir probando el flujo: abre un turno nuevo automáticamente.
    await ref.read(cashSessionProvider.notifier).startNewSession();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(cashSessionProvider);
    final expectedCashMxn = ref.watch(expectedCashMxnProvider);

    return Scaffold(
      backgroundColor: AppColors.darkSlate,
      appBar: AppBar(
        backgroundColor: AppColors.darkSlate,
        elevation: 0,
        scrolledUnderElevation: 0,
        automaticallyImplyLeading: false,
        title: const Text(
          'Caja',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: AppColors.onSurface,
          ),
        ),
      ),
      body: SafeArea(
        child: session == null
            ? const Center(
                child: CircularProgressIndicator(color: AppColors.emerald),
              )
            : Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _ActiveShiftCard(session: session, expectedCashMxn: expectedCashMxn),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton.icon(
                        onPressed: _openCloseWizard,
                        icon: const Icon(Icons.point_of_sale_rounded, size: 20),
                        label: const Text(
                          'Cerrar turno',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tarjeta de turno activo
// ---------------------------------------------------------------------------

class _ActiveShiftCard extends StatelessWidget {
  const _ActiveShiftCard({required this.session, required this.expectedCashMxn});

  final CashSession session;
  final double expectedCashMxn;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.emerald.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.circle, size: 8, color: AppColors.emerald),
                    SizedBox(width: 6),
                    Text(
                      'TURNO ABIERTO',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.emerald,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            session.cashierName,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.onSurface,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Apertura: ${_formatDateTime(session.openedAt)}',
            style: const TextStyle(fontSize: 13, color: AppColors.onSurfaceMuted),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(child: _statTile('Fondo inicial', session.openingAmountMxn)),
              const SizedBox(width: 12),
              Expanded(
                child: _statTile('Efectivo esperado', expectedCashMxn,
                    valueColor: AppColors.skyBlue),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statTile(String label, double amountMxn, {Color? valueColor}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 11, color: AppColors.onSurfaceMuted)),
          const SizedBox(height: 4),
          Text(
            '\$${amountMxn.toStringAsFixed(2)}',
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: valueColor ?? AppColors.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}
