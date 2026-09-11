import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import '../../domain/banxico_denomination.dart';
import '../../domain/cash_denomination_entry.dart';
import '../../domain/cash_session.dart';
import '../cash_session_provider.dart';
import 'cash_count_step.dart';
import 'digital_summary_step.dart';

/// Asistente visual de cierre de caja (Wizard Banxico) — Tarea 9.2.
///
/// 2 pasos (colapsados desde los 3 del plan original: el modelo híbrido de
/// tipo+valor+cantidad ya cubre billetes y monedas en una sola tabla):
///   1. Conteo de Efectivo — `CashCountStep`
///   2. Resumen y Confirmación — `DigitalSummaryStep`
///
/// Layout del Paso 1 inspirado en la referencia de Figma (node 77:2); el
/// Paso 2 es diseño propio manteniendo la misma identidad visual. El
/// indicador de pasos con círculos numerados (`WizardStepper`) se retiró —
/// no existe en la referencia de Figma y le restaba espacio vertical al
/// desglose de billetes — y se reemplazó por una barra delgada de progreso
/// (`_buildProgressBar`), igual de liviana que la línea bajo el encabezado
/// del diseño original pero sin ocupar el alto de los círculos+etiquetas.
///
/// Entradas del conteo viven en el estado local del widget (flujo
/// transaccional efímero — convención ya establecida en `PaymentModal`).
///
/// Trazabilidad: Constitución Art. VII (7.2) · Doc. Maestro RF-18, RF-19,
///              Sección 6 (SR-07) · HU-15 / CU-17, CU-18
class CloseSessionWizard extends ConsumerStatefulWidget {
  const CloseSessionWizard({super.key});

  @override
  ConsumerState<CloseSessionWizard> createState() => _CloseSessionWizardState();
}

class _CloseSessionWizardState extends ConsumerState<CloseSessionWizard> {
  static const _totalSteps = 2;

  int _currentStep = 0;
  final List<CashDenominationEntry> _entries = [];
  bool _isClosing = false;
  bool _quantityFocused = false;

  double get _physicalCashMxn =>
      _entries.fold(0.0, (sum, e) => sum + e.subtotalMxn);

  /// La denominación tocada (nueva o con cantidad acumulada) siempre queda
  /// primera en la lista — señal visual de que "Agregar" sí tuvo efecto,
  /// sin depender de que el usuario haga scroll para notarlo.
  void _addEntry(BanxicoDenomination denomination, int quantity) {
    setState(() {
      final index = _entries.indexWhere(
        (e) => e.denomination.apiKey == denomination.apiKey,
      );
      final CashDenominationEntry entry;
      if (index >= 0) {
        final existing = _entries.removeAt(index);
        entry = existing.copyWith(quantity: existing.quantity + quantity);
      } else {
        entry = CashDenominationEntry(denomination: denomination, quantity: quantity);
      }
      _entries.insert(0, entry);
    });
  }

  void _removeEntry(String apiKey) {
    setState(() => _entries.removeWhere((e) => e.denomination.apiKey == apiKey));
  }

  void _clearAll() {
    setState(() => _entries.clear());
  }

  void _goToStep2() {
    setState(() => _currentStep = 1);
  }

  void _goBack() {
    if (_currentStep == 0) {
      Navigator.of(context).maybePop();
    } else {
      setState(() => _currentStep = 0);
    }
  }

  Future<void> _confirmClose() async {
    setState(() => _isClosing = true);
    try {
      final piecesByApiKey = {
        for (final e in _entries) e.denomination.apiKey: e.quantity,
      };
      final closed = await ref
          .read(cashSessionProvider.notifier)
          .closeSession(BanxicoCount(piecesByApiKey));
      if (!mounted) return;
      Navigator.of(context).pop(closed);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al cerrar el turno: $e'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
      setState(() => _isClosing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(cashSessionProvider);
    final expectedCashMxn = ref.watch(expectedCashMxnProvider);
    final digitalTotals = ref.watch(digitalPaymentTotalsProvider);

    return Scaffold(
      backgroundColor: AppColors.darkSlate,
      // El teclado NO redimensiona el body: si lo hiciera, la barra inferior
      // ("Siguiente") se recalcularía y "subiría" a flotar justo encima del
      // teclado junto al botón "Agregar" del formulario — dos acciones
      // compitiendo por atención. Con esto el teclado se superpone (overlay)
      // sin mover el layout; solo el formulario (arriba, fijo) queda visible.
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        backgroundColor: AppColors.darkSlate,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.onSurface),
          onPressed: _goBack,
        ),
        title: const Text(
          'Arqueo de Caja',
          style: TextStyle(
            color: AppColors.onSurface,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Encabezado fijo: barra de progreso + tarjeta de turno. Solo el
            // contenido del paso (justo debajo) es lo que hace scroll.
            _buildProgressBar(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (session != null) _ShiftInfoCard(session: session),
                  const SizedBox(height: 12),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: _currentStep == 0
                    ? CashCountStep(
                        entries: _entries,
                        onAdd: _addEntry,
                        onRemove: _removeEntry,
                        onClearAll: _clearAll,
                        onQuantityFocusChanged: (focused) =>
                            setState(() => _quantityFocused = focused),
                      )
                    : SingleChildScrollView(
                        child: DigitalSummaryStep(
                          digitalTotals: digitalTotals,
                          expectedCashMxn: expectedCashMxn,
                          physicalCashMxn: _physicalCashMxn,
                        ),
                      ),
              ),
            ),
            _buildBottomBar(),
          ],
        ),
      ),
    );
  }

  /// Reemplaza al `WizardStepper` (círculos numerados) por una barra
  /// delgada — misma idea del divisor bajo el encabezado en la referencia
  /// de Figma (node 77:2), pero rellenada según el avance para conservar
  /// algo de orientación sin el costo vertical de los círculos+etiquetas.
  Widget _buildProgressBar() {
    return Container(
      height: 3,
      color: AppColors.surfaceVariant,
      child: FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: (_currentStep + 1) / _totalSteps,
        child: Container(color: AppColors.skyBlue),
      ),
    );
  }

  /// Mientras el campo "Cant." tiene foco (teclado numérico abierto), la
  /// barra se oculta por completo en vez de compactarse: un tamaño
  /// reducido seguía sin dejar suficiente margen contra el overflow que
  /// provoca el `Scaffold` padre (`DashboardShell`) al reducir la altura
  /// disponible para mantener la barra de tabs visible. Ocultarla también
  /// deja "Agregar" como único botón visible, como pidió Eduardo. Se
  /// detecta por foco (no por `MediaQuery.viewInsets`, que el `Scaffold`
  /// padre ya consume/zera vía `removeBottomInset` antes de llegar aquí).
  Widget _buildBottomBar() {
    if (_currentStep == 0 && _quantityFocused) {
      return const SizedBox.shrink();
    }

    final bottomPad = MediaQuery.of(context).padding.bottom;

    return Container(
      padding: EdgeInsets.fromLTRB(16, 12, 16, bottomPad + 12),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: _currentStep == 0
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const Text(
                      'TOTAL CONTADO',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.onSurfaceMuted,
                        letterSpacing: 0.6,
                      ),
                    ),
                    Text(
                      '\$${_physicalCashMxn.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: AppColors.skyBlue,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _goToStep2,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.emerald,
                      foregroundColor: AppColors.darkSlate,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('Siguiente',
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                        SizedBox(width: 8),
                        Icon(Icons.arrow_forward_rounded, size: 18),
                      ],
                    ),
                  ),
                ),
              ],
            )
          : SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: _isClosing ? null : _confirmClose,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.emerald,
                  foregroundColor: AppColors.darkSlate,
                  disabledBackgroundColor: AppColors.surfaceVariant,
                  disabledForegroundColor: AppColors.onSurfaceMuted,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                icon: _isClosing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.5, color: AppColors.darkSlate),
                      )
                    : const Icon(Icons.check_circle_rounded, size: 20),
                label: Text(
                  _isClosing ? 'Cerrando turno...' : 'Confirmar Cierre',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ),
            ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tarjeta de información del turno — visible en ambos pasos para contexto.
// ---------------------------------------------------------------------------

class _ShiftInfoCard extends StatelessWidget {
  const _ShiftInfoCard({required this.session});

  final CashSession session;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.skyBlue.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.badge_rounded, color: AppColors.skyBlue, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        session.cashierName,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.onSurface,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                      decoration: BoxDecoration(
                        color: AppColors.skyBlue.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        'Fondo \$${session.openingAmountMxn.toStringAsFixed(0)}',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: AppColors.skyBlue,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 4,
                  runSpacing: 2,
                  children: [
                    const Icon(Icons.schedule_rounded,
                        size: 12, color: AppColors.onSurfaceMuted),
                    Text(
                      'Abierto ${_formatTime(session.openedAt)}',
                      style: const TextStyle(fontSize: 11, color: AppColors.onSurfaceMuted),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 4),
                      child: Text('•', style: TextStyle(color: AppColors.onSurfaceMuted)),
                    ),
                    const Icon(Icons.calendar_today_rounded,
                        size: 11, color: AppColors.onSurfaceMuted),
                    Text(
                      _formatDate(session.openedAt),
                      style: const TextStyle(fontSize: 11, color: AppColors.onSurfaceMuted),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  String _formatTime(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}
