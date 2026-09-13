import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/theme/app_colors.dart';
import '../../onboarding/presentation/onboarding_provider.dart';
import '../../sales_pos/data/sales_repository.dart';
import '../../sales_pos/domain/cart_state.dart';
import '../../sales_pos/domain/payment_entry.dart';
import '../domain/cash_denomination_entry.dart';
import '../domain/cash_movement.dart';
import '../domain/cash_session.dart';
import 'cash_session_provider.dart';
import 'widgets/cash_closing_ticket_card.dart';
import 'widgets/cash_movements_list_box.dart';

/// Pantalla de resultado del arqueo (Subtarea 10.2.1) con el ticket de
/// Corte Z embebido y sus acciones de exportación (Subtarea 10.2.3).
///
/// Se muestra vía `pushReplacement` justo después de confirmar el cierre en
/// `CloseSessionWizard` — mismo patrón que `SaleReceiptScreen` (Tarea 8.2):
/// una sola pantalla combina el semáforo de discrepancia con el ticket
/// compartible, en vez de dos pantallas separadas (decisión aprobada por
/// Eduardo para la Tarea 10.2).
///
/// Trazabilidad: Constitución Art. VII (7.2) · Doc. Maestro RF-18, RF-19 ·
///              HU-16 / CU-19, CU-20
class CashSessionSummaryScreen extends ConsumerStatefulWidget {
  const CashSessionSummaryScreen({
    super.key,
    required this.session,
    required this.physicalEntries,
    required this.digitalTotals,
    required this.movements,
  });

  /// Sesión ya cerrada (`status == closed`).
  final CashSession session;
  final List<CashDenominationEntry> physicalEntries;
  final Map<PaymentMethodMxn, double> digitalTotals;
  final List<CashMovement> movements;

  @override
  ConsumerState<CashSessionSummaryScreen> createState() => _CashSessionSummaryScreenState();
}

class _CashSessionSummaryScreenState extends ConsumerState<CashSessionSummaryScreen> {
  final _ticketKey = GlobalKey();
  bool _isSharing = false;
  bool _isStartingNewSession = false;

  CashSession get _session => widget.session;

  /// Ventas en efectivo completadas durante el turno — mismo filtro que
  /// `_computeExpectedCashMxn` en `cash_session_provider.dart`, pero acotado
  /// también por el cierre (el turno ya terminó).
  List<CheckoutResult> get _salesInShift => SalesRepositoryMock.todaysSales
      .where((sale) =>
          sale.completedAt.isAfter(_session.openedAt) &&
          (_session.closedAt == null || sale.completedAt.isBefore(_session.closedAt!)))
      .toList();

  double get _cashSalesMxn => _salesInShift
      .expand((sale) => sale.payments)
      .where((p) => p.method == PaymentMethodMxn.cashMxn)
      .fold(0.0, (sum, p) => sum + p.amountMxn);

  Color _resultColor() => switch (_session.balanceResult) {
        CashBalanceResult.exact => AppColors.emerald,
        CashBalanceResult.short => AppColors.error,
        CashBalanceResult.over => AppColors.warning,
        null => AppColors.onSurfaceMuted,
      };

  IconData _resultIcon() => switch (_session.balanceResult) {
        CashBalanceResult.exact => Icons.check_circle_rounded,
        CashBalanceResult.short => Icons.error_rounded,
        CashBalanceResult.over => Icons.info_rounded,
        null => Icons.help_rounded,
      };

  // ── Acciones ─────────────────────────────────────────────────────────────

  /// Comparte el ticket como imagen PNG — misma técnica que
  /// `SaleReceiptScreen._shareReceiptAsImage` (Tarea 8.2.2).
  Future<void> _shareTicketAsImage() async {
    setState(() => _isSharing = true);
    try {
      final boundary = _ticketKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;

      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;

      final tempDir = await getTemporaryDirectory();
      final fileName = 'corte_z_${_session.id}_${DateTime.now().millisecondsSinceEpoch}.png';
      final file = File('${tempDir.path}/$fileName');
      await file.writeAsBytes(byteData.buffer.asUint8List());

      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'image/png')],
        subject: 'Corte de Caja ${_session.id}',
      );
    } finally {
      if (mounted) setState(() => _isSharing = false);
    }
  }

  void _showPrintBlocker() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Impresión térmica y PDF disponibles cuando el backend entregue el '
          'reporte de corte (Tarea 10.1)',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _startNewSession() async {
    setState(() => _isStartingNewSession = true);
    await ref.read(cashSessionProvider.notifier).startNewSession();
    if (mounted) Navigator.of(context).pop();
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final onboarding = ref.watch(onboardingProvider).data;
    final businessName = onboarding.businessName.isEmpty ? 'NEXUS STORE' : onboarding.businessName;

    return Scaffold(
      backgroundColor: AppColors.darkSlate,
      appBar: AppBar(
        backgroundColor: AppColors.darkSlate,
        elevation: 0,
        scrolledUnderElevation: 0,
        automaticallyImplyLeading: false,
        title: const Text(
          'Resultado del Cierre',
          style: TextStyle(color: AppColors.onSurface, fontSize: 18, fontWeight: FontWeight.w700),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _BalanceBanner(session: _session, color: _resultColor(), icon: _resultIcon()),
              const SizedBox(height: 16),
              _ComparisonCard(session: _session, movements: widget.movements, resultColor: _resultColor()),
              if (widget.movements.isNotEmpty) ...[
                const SizedBox(height: 16),
                _MovementsCard(movements: widget.movements),
              ],
              const SizedBox(height: 28),
              const _TicketSectionHeader(),
              const SizedBox(height: 12),
              RepaintBoundary(
                key: _ticketKey,
                child: CashClosingTicketCard(
                  session: _session,
                  businessName: businessName,
                  physicalEntries: widget.physicalEntries,
                  digitalTotals: widget.digitalTotals,
                  movements: widget.movements,
                  cashSalesMxn: _cashSalesMxn,
                  salesCount: _salesInShift.length,
                  pageBackground: AppColors.darkSlate,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: _SecondaryActionButton(
                      icon: Icons.share_rounded,
                      label: 'WhatsApp',
                      foregroundColor: AppColors.onSurface,
                      borderColor: AppColors.border,
                      isLoading: _isSharing,
                      onTap: _isSharing ? null : _shareTicketAsImage,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _SecondaryActionButton(
                      icon: Icons.print_outlined,
                      label: 'Imprimir',
                      foregroundColor: AppColors.skyBlue,
                      borderColor: AppColors.skyBlue,
                      onTap: _showPrintBlocker,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 56,
                child: ElevatedButton.icon(
                  onPressed: _isStartingNewSession ? null : _startNewSession,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.emerald,
                    foregroundColor: AppColors.darkSlate,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  icon: _isStartingNewSession
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.darkSlate),
                        )
                      : const Icon(Icons.point_of_sale_rounded, size: 20),
                  label: const Text('Nuevo turno', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
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
// Semáforo de resultado — Subtarea 10.2.1
// ---------------------------------------------------------------------------

class _BalanceBanner extends StatelessWidget {
  const _BalanceBanner({required this.session, required this.color, required this.icon});

  final CashSession session;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final differenceMxn = session.differenceMxn ?? 0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 40),
          const SizedBox(height: 10),
          Text(
            session.balanceResult?.label ?? 'Sin resultado',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: color),
          ),
          const SizedBox(height: 4),
          Text(
            '${differenceMxn >= 0 ? '+' : '-'}\$${differenceMxn.abs().toStringAsFixed(2)} MXN',
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tarjeta comparativa — CA-02
// ---------------------------------------------------------------------------

class _ComparisonCard extends StatelessWidget {
  const _ComparisonCard({required this.session, required this.movements, required this.resultColor});

  final CashSession session;
  final List<CashMovement> movements;
  final Color resultColor;

  double get _movementsNet => movements.fold(
        0.0,
        (sum, m) => sum + (m.type == CashMovementType.deposit ? m.amountMxn : -m.amountMxn),
      );

  @override
  Widget build(BuildContext context) {
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
          _row('Fondo inicial', session.openingAmountMxn, AppColors.onSurfaceMuted),
          const SizedBox(height: 8),
          _row('Movimientos netos', _movementsNet, AppColors.onSurfaceMuted),
          const SizedBox(height: 8),
          _row('Efectivo esperado', session.expectedCashMxn, AppColors.onSurface),
          const SizedBox(height: 8),
          _row('Efectivo físico contado', session.physicalCashMxn ?? 0, AppColors.onSurface),
        ],
      ),
    );
  }

  Widget _row(String label, double amountMxn, Color valueColor) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(label,
              style: const TextStyle(fontSize: 14, color: AppColors.onSurfaceMuted),
              overflow: TextOverflow.ellipsis),
        ),
        const SizedBox(width: 8),
        Text(
          '${amountMxn < 0 ? '-' : ''}\$${amountMxn.abs().toStringAsFixed(2)}',
          style: TextStyle(fontFamily: 'monospace', fontSize: 14, fontWeight: FontWeight.w700, color: valueColor),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Movimientos del turno — visibles también en el resumen, no solo en el
// ticket, para que la discrepancia sea explicable de un vistazo.
// ---------------------------------------------------------------------------

class _MovementsCard extends StatelessWidget {
  const _MovementsCard({required this.movements});

  final List<CashMovement> movements;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: CashMovementsListBox(movements: movements),
    );
  }
}

// ---------------------------------------------------------------------------
// Encabezado del ticket Corte Z — más prominente que un título de sección
// normal para que sea evidente que el ticket compartible/imprimible sigue
// justo debajo (pedido de Eduardo en QA).
// ---------------------------------------------------------------------------

class _TicketSectionHeader extends StatelessWidget {
  const _TicketSectionHeader();

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.skyBlue.withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.receipt_long_rounded, color: AppColors.skyBlue, size: 20),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Ticket Corte Z',
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: AppColors.onSurface),
              ),
              SizedBox(height: 2),
              Text(
                'Compártelo o imprímelo para tu archivo',
                style: TextStyle(fontSize: 12, color: AppColors.onSurfaceMuted),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Botón secundario — idéntico al de `SaleReceiptScreen` (Tarea 8.2.2).
// ---------------------------------------------------------------------------

class _SecondaryActionButton extends StatelessWidget {
  const _SecondaryActionButton({
    required this.icon,
    required this.label,
    required this.foregroundColor,
    required this.borderColor,
    required this.onTap,
    this.isLoading = false,
  });

  final IconData icon;
  final String label;
  final Color foregroundColor;
  final Color borderColor;
  final VoidCallback? onTap;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: OutlinedButton.icon(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          foregroundColor: foregroundColor,
          side: BorderSide(color: borderColor),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        icon: isLoading
            ? SizedBox(
                height: 16,
                width: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: foregroundColor),
              )
            : Icon(icon, size: 18),
        label: Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
      ),
    );
  }
}
