import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import '../../domain/cash_movement.dart';
import '../cash_session_provider.dart';

// ---------------------------------------------------------------------------
// Presentación por tipo de movimiento
// ---------------------------------------------------------------------------

extension CashMovementTypeIconX on CashMovementType {
  IconData get icon => switch (this) {
        CashMovementType.withdrawal => Icons.remove_circle_outline_rounded,
        CashMovementType.deposit => Icons.add_circle_outline_rounded,
      };

  Color get color => switch (this) {
        CashMovementType.withdrawal => AppColors.error,
        CashMovementType.deposit => AppColors.emerald,
      };
}

// ---------------------------------------------------------------------------
// Función de conveniencia
// ---------------------------------------------------------------------------

/// Abre el modal de registro de movimientos de caja menor — Subtarea 10.2.2.
/// Retorna `true` si el movimiento se registró, o `false`/`null` si se canceló.
Future<bool> showCashMovementModal(BuildContext context) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const CashMovementModal(),
  ).then((v) => v ?? false);
}

// ---------------------------------------------------------------------------
// Widget
// ---------------------------------------------------------------------------

/// Formulario ágil para registrar retiros o entradas de caja menor durante
/// un turno abierto — Subtarea 10.2.2.
///
/// Estado 100% local (`ConsumerStatefulWidget`, sin provider propio): flujo
/// transaccional efímero, mismo patrón que `AdjustStockModal` (Tarea 4.2.A).
///
/// Trazabilidad: Constitución Art. VII (7.2) · Doc. Maestro RF-18 · HU-16 / CU-19
class CashMovementModal extends ConsumerStatefulWidget {
  const CashMovementModal({super.key});

  @override
  ConsumerState<CashMovementModal> createState() => _CashMovementModalState();
}

class _CashMovementModalState extends ConsumerState<CashMovementModal> {
  CashMovementType _type = CashMovementType.withdrawal;
  final _amountController = TextEditingController();
  final _descriptionController = TextEditingController();
  bool _isSaving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _amountController.addListener(() => setState(() {}));
    _descriptionController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _amountController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  // ── Lógica ───────────────────────────────────────────────────────────────

  double get _amountMxn =>
      double.tryParse(_amountController.text.replaceAll(',', '.')) ?? 0;

  bool get _isValid =>
      _amountMxn > 0 && _descriptionController.text.trim().length >= 3;

  Future<void> _submit() async {
    if (!_isValid || _isSaving) return;
    setState(() {
      _isSaving = true;
      _error = null;
    });

    try {
      await ref.read(cashMovementsProvider.notifier).addMovement(
            type: _type,
            amountMxn: _amountMxn,
            description: _descriptionController.text.trim(),
          );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() {
        _isSaving = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final bottomInset = mq.viewInsets.bottom > 0 ? mq.viewInsets.bottom : mq.padding.bottom;

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(24, 12, 24, 24 + bottomInset),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _handle(),
            _header(),
            const SizedBox(height: 20),
            _typeSelector(),
            const SizedBox(height: 16),
            _amountField(),
            const SizedBox(height: 16),
            _descriptionField(),
            if (_error != null) ...[const SizedBox(height: 12), _errorBanner()],
            const SizedBox(height: 20),
            _submitButton(),
          ],
        ),
      ),
    );
  }

  Widget _handle() => Center(
        child: Container(
          width: 40,
          height: 4,
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: AppColors.border,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      );

  Widget _header() => Row(
        children: [
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Registrar movimiento',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.onSurface,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Retiros o entradas de efectivo durante el turno',
                  style: TextStyle(fontSize: 12, color: AppColors.onSurfaceMuted),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).pop(false),
            icon: const Icon(Icons.close_rounded, size: 22, color: AppColors.onSurfaceMuted),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      );

  Widget _typeSelector() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Tipo de movimiento',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.onSurface),
          ),
          const SizedBox(height: 10),
          Row(
            children: CashMovementType.values.map((t) {
              final selected = _type == t;
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: t == CashMovementType.withdrawal ? 8 : 0),
                  child: GestureDetector(
                    onTap: () => setState(() => _type = t),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: selected ? t.color.withValues(alpha: 0.12) : AppColors.surfaceVariant,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: selected ? t.color : AppColors.border,
                          width: selected ? 1.5 : 1,
                        ),
                      ),
                      child: Column(
                        children: [
                          Icon(t.icon, size: 20, color: selected ? t.color : AppColors.onSurfaceMuted),
                          const SizedBox(height: 4),
                          Text(
                            t.label,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: selected ? t.color : AppColors.onSurfaceMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      );

  Widget _amountField() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Monto  *',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.onSurface),
          ),
          const SizedBox(height: 10),
          TextField(
            key: const Key('cashMovementAmountField'),
            controller: _amountController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.,]'))],
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.onSurface,
            ),
            decoration: const InputDecoration(
              hintText: '0.00',
              prefixText: '\$ ',
              prefixStyle: TextStyle(fontFamily: 'monospace', color: AppColors.onSurfaceMuted),
            ),
          ),
        ],
      );

  Widget _descriptionField() => TextFormField(
        controller: _descriptionController,
        maxLength: 200,
        textCapitalization: TextCapitalization.sentences,
        style: const TextStyle(color: AppColors.onSurface, fontSize: 14),
        decoration: const InputDecoration(
          labelText: 'Motivo  *',
          hintText: 'Ej: Pago de hielo al proveedor',
          prefixIcon: Icon(Icons.edit_note_rounded, size: 18),
          counterText: '',
        ),
      );

  Widget _errorBanner() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.error.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            const Icon(Icons.error_outline_rounded, size: 16, color: AppColors.error),
            const SizedBox(width: 8),
            Expanded(child: Text(_error!, style: const TextStyle(fontSize: 13, color: AppColors.error))),
          ],
        ),
      );

  Widget _submitButton() {
    return SizedBox(
      height: 52,
      child: ElevatedButton(
        onPressed: _isValid && !_isSaving ? _submit : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: _type.color,
          foregroundColor: AppColors.darkSlate,
          disabledBackgroundColor: AppColors.surfaceVariant,
          disabledForegroundColor: AppColors.onSurfaceMuted,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 0,
        ),
        child: _isSaving
            ? const SizedBox(
                height: 22,
                width: 22,
                child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.darkSlate),
              )
            : Text(
                'Registrar ${_type.label.toLowerCase()}',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
      ),
    );
  }
}
