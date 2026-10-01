import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../domain/cash_movement.dart';
import '../domain/cash_session.dart';
import 'cash_session_provider.dart';
import 'widgets/cash_movement_modal.dart';
import 'widgets/cash_movements_list_box.dart';
import 'widgets/close_session_wizard.dart';
import '../../account/presentation/widgets/warehouse_scope_badge.dart';

/// Pantalla principal de la tab "Caja" — Tarea 9.2 (ampliada en 10.2.2 con
/// movimientos de caja menor).
///
/// Reemplaza `CashPlaceholder`: muestra el turno activo (cajero, fondo
/// inicial, apertura, efectivo esperado en vivo), la lista de movimientos de
/// caja menor del turno y el botón para iniciar el asistente de cierre
/// (`CloseSessionWizard`).
///
/// Trazabilidad: Constitución Art. VII (7.2) · Doc. Maestro RF-18 · HU-15 / HU-16
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
      // Se retoma el turno abierto en el servidor; sin turno se ofrece abrirlo (A1)
      ref.read(cashSessionProvider.notifier).load();
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

    // Sin turno: se ofrece abrir uno nuevo con el fondo que declare el cajero
    ref.read(cashSessionProvider.notifier).startNewSession();
  }

  Future<void> _openMovementModal() async {
    final registered = await showCashMovementModal(context);
    if (registered && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Movimiento registrado'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(cashSessionProvider);
    final load = ref.watch(cashLoadProvider);
    final expectedCashMxn = ref.watch(expectedCashMxnProvider).valueOrNull;
    final movements = ref.watch(cashMovementsProvider);

    return Scaffold(
      backgroundColor: AppColors.darkSlate,
      appBar: AppBar(
        backgroundColor: AppColors.darkSlate,
        elevation: 0,
        scrolledUnderElevation: 0,
        automaticallyImplyLeading: false,
        title: const ScopedAppBarTitle(
          title: Text(
            'Caja',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: AppColors.onSurface,
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: session == null
            ? load.loading
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.emerald),
                  )
                : load.error != null
                    ? _LoadError(
                        message: load.error!,
                        onRetry: () => ref.read(cashSessionProvider.notifier).load(),
                      )
                    : const _OpenShiftForm()
            : RefreshIndicator(
                color: AppColors.emerald,
                onRefresh: () => ref.read(cashSessionProvider.notifier).refresh(),
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _ActiveShiftCard(session: session, expectedCashMxn: expectedCashMxn),
                      const SizedBox(height: 24),
                      _MovementsSection(
                        movements: movements,
                        onRegister: _openMovementModal,
                      ),
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
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sin turno: el cajero declara su fondo (Integración de Caja, C1)
// ---------------------------------------------------------------------------

/// "Abrir turno · ¿Con cuánto efectivo empiezas?". Un monto simple (la app es
/// referencial; el conteo por piezas queda para el cierre).
class _OpenShiftForm extends ConsumerStatefulWidget {
  const _OpenShiftForm();

  /// Arriba de esto se pide confirmar: es raro y suele ser un cero de más.
  static const unusualAmountMxn = 50000.0;

  @override
  ConsumerState<_OpenShiftForm> createState() => _OpenShiftFormState();
}

class _OpenShiftFormState extends ConsumerState<_OpenShiftForm> {
  final _amount = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  double? get _value {
    final text = _amount.text.trim().replaceAll(',', '');
    if (text.isEmpty) return null;
    return double.tryParse(text);
  }

  Future<void> _submit() async {
    final value = _value;
    if (value == null || value < 0) {
      setState(() => _error = 'Escribe cuánto efectivo hay en la caja (puede ser 0).');
      return;
    }
    if (value > _OpenShiftForm.unusualAmountMxn) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: const Text('¿El fondo es correcto?'),
          content: Text('Vas a empezar con \$${value.toStringAsFixed(2)} MXN. Es más de lo usual.'),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Corregir')),
            TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Sí, abrir turno')),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(cashSessionProvider.notifier).openSession(value);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Container(
        key: const Key('cashOpenShiftForm'),
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
            const Text(
              'Abrir turno',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.onSurface),
            ),
            const SizedBox(height: 4),
            const Text(
              '¿Con cuánto efectivo empiezas? Es el dinero que ya está en la caja.',
              style: TextStyle(fontSize: 14, color: AppColors.onSurfaceMuted, height: 1.4),
            ),
            const SizedBox(height: 16),
            TextField(
              key: const Key('cashOpeningAmount'),
              controller: _amount,
              enabled: !_busy,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: 'Fondo inicial',
                prefixText: '\$ ',
                suffixText: 'MXN',
                errorText: _error,
                errorMaxLines: 3,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                key: const Key('cashOpenShift'),
                onPressed: _busy ? null : _submit,
                child: Text(_busy ? 'Abriendo…' : 'Abrir turno'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// No se pudo consultar el turno: se dice y se reintenta (nunca carga infinita, CA-C1).
class _LoadError extends StatelessWidget {
  const _LoadError({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_rounded, size: 40, color: AppColors.onSurfaceMuted),
              const SizedBox(height: 12),
              const Text(
                'No pudimos consultar tu turno',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.onSurface),
              ),
              const SizedBox(height: 6),
              Text(
                message,
                key: const Key('cashLoadError'),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, color: AppColors.onSurfaceMuted, height: 1.4),
              ),
              const SizedBox(height: 16),
              OutlinedButton(
                key: const Key('cashLoadRetry'),
                onPressed: onRetry,
                style: OutlinedButton.styleFrom(minimumSize: const Size(160, 48)),
                child: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
}

// ---------------------------------------------------------------------------
// Sección de movimientos de caja menor — Subtarea 10.2.2
// ---------------------------------------------------------------------------

class _MovementsSection extends StatelessWidget {
  const _MovementsSection({required this.movements, required this.onRegister});

  final List<CashMovement> movements;
  final VoidCallback onRegister;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Expanded(
              child: Text(
                'Movimientos de caja menor',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.onSurface),
              ),
            ),
            TextButton.icon(
              onPressed: onRegister,
              icon: const Icon(Icons.add_circle_outline_rounded, size: 18),
              label: const Text('Registrar'),
              style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8)),
            ),
          ],
        ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          child: movements.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    'Sin movimientos registrados en este turno.',
                    style: TextStyle(fontSize: 13, color: AppColors.onSurfaceMuted),
                  ),
                )
              : CashMovementsListBox(movements: movements),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Tarjeta de turno activo
// ---------------------------------------------------------------------------

class _ActiveShiftCard extends StatelessWidget {
  const _ActiveShiftCard({required this.session, required this.expectedCashMxn});

  final CashSession session;

  /// `null` mientras se resuelve contra el backend real (Sep 2026 — antes
  /// era un cálculo síncrono sobre datos en memoria, ahora pide `GET /sales`
  /// y `GET /cash/sessions/{id}/movements`).
  final double? expectedCashMxn;

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
                child: _statTile('Efectivo esperado', expectedCashMxn, valueColor: AppColors.skyBlue),
              ),
            ],
          ),
          // El cambio ya está descontado: se dice para que nadie lo registre como retiro (V1)
          if ((session.summary?.cashReceivedMxn ?? 0) > 0) ...[
            const SizedBox(height: 12),
            Text(
              'Ventas en efectivo \$${session.summary!.cashSalesMxn.toStringAsFixed(2)} · '
              'recibido \$${session.summary!.cashReceivedMxn.toStringAsFixed(2)} · '
              'cambio entregado \$${session.summary!.changeGivenMxn.toStringAsFixed(2)}',
              key: const Key('cashSalesBreakdown'),
              style: const TextStyle(fontSize: 13, color: AppColors.onSurfaceMuted, height: 1.4),
            ),
          ],
        ],
      ),
    );
  }

  Widget _statTile(String label, double? amountMxn, {Color? valueColor}) {
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
            amountMxn == null ? '…' : '\$${amountMxn.toStringAsFixed(2)}',
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
