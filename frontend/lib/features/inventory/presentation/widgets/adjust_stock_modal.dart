import 'dart:math' show max;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../../core/theme/app_colors.dart';
import '../../domain/product.dart';
import '../inventory_provider.dart';

// ---------------------------------------------------------------------------
// Tipos de ajuste
// ---------------------------------------------------------------------------

enum AdjustmentType {
  entryIn, // MANUAL_ADJUSTMENT_IN  ➕
  exit, // MANUAL_ADJUSTMENT_OUT ➖
  waste, // WASTE                 ⚠
}

extension AdjustmentTypeX on AdjustmentType {
  String get apiCode => switch (this) {
        AdjustmentType.entryIn => 'MANUAL_ADJUSTMENT_IN',
        AdjustmentType.exit => 'MANUAL_ADJUSTMENT_OUT',
        AdjustmentType.waste => 'WASTE',
      };

  String get label => switch (this) {
        AdjustmentType.entryIn => 'Entrada',
        AdjustmentType.exit => 'Salida',
        AdjustmentType.waste => 'Merma',
      };

  IconData get icon => switch (this) {
        AdjustmentType.entryIn => Icons.add_circle_outline_rounded,
        AdjustmentType.exit => Icons.remove_circle_outline_rounded,
        AdjustmentType.waste => Icons.warning_amber_rounded,
      };

  /// true = suma al stock, false = resta
  bool get isIncoming => this == AdjustmentType.entryIn;

  Color get color => switch (this) {
        AdjustmentType.entryIn => AppColors.emerald,
        AdjustmentType.exit => AppColors.error,
        AdjustmentType.waste => AppColors.warning,
      };
}

// ---------------------------------------------------------------------------
// Función de conveniencia
// ---------------------------------------------------------------------------

Future<bool> showAdjustStockModal(BuildContext context, Product product) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    backgroundColor: Colors.transparent,
    builder: (_) => AdjustStockModal(product: product),
  ).then((v) => v ?? false);
}

// ---------------------------------------------------------------------------
// Widget
// ---------------------------------------------------------------------------

class AdjustStockModal extends ConsumerStatefulWidget {
  const AdjustStockModal({super.key, required this.product});

  final Product product;

  @override
  ConsumerState<AdjustStockModal> createState() => _AdjustStockModalState();
}

class _AdjustStockModalState extends ConsumerState<AdjustStockModal> {
  AdjustmentType _type = AdjustmentType.entryIn;
  int _quantity = 1;
  final _reasonCtrl = TextEditingController();
  bool _isSaving = false;
  String? _error;

  @override
  void dispose() {
    _reasonCtrl.dispose();
    super.dispose();
  }

  // ── Lógica ───────────────────────────────────────────────────────────────

  int get _resultStock {
    final delta = _type.isIncoming ? _quantity : -_quantity;
    return widget.product.availableStock + delta;
  }

  bool get _isValid =>
      _quantity > 0 && _reasonCtrl.text.trim().length >= 3 && _resultStock >= 0;

  Future<void> _submit() async {
    if (!_isValid || _isSaving) return;
    setState(() {
      _isSaving = true;
      _error = null;
    });

    try {
      await ref.read(inventoryProvider.notifier).adjustStock(
            productId: widget.product.id,
            movementType: _type.apiCode,
            quantity: _quantity,
            reason: _reasonCtrl.text.trim(),
          );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() {
        _isSaving = false;
        _error = 'No se pudo aplicar el ajuste.';
      });
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    // max() garantiza safe area cuando el teclado está cerrado
    // y altura del teclado cuando está abierto — el mayor siempre gana.
    final bottomInset = max(mq.viewInsets.bottom, mq.padding.bottom);

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      // SingleChildScrollView evita el overflow cuando el teclado sube
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
            const SizedBox(height: 20),
            _stepper(),
            const SizedBox(height: 16),
            _reasonField(),
            const SizedBox(height: 12),
            _preview(),
            if (_error != null) ...[const SizedBox(height: 8), _errorBanner()],
            const SizedBox(height: 20),
            _submitButton(),
          ],
        ),
      ),
    );
  }

  // ── Subwidgets ────────────────────────────────────────────────────────────

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
            child: Text(
              'Ajustar stock',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.onSurface),
            ),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).pop(false),
            icon: const Icon(Icons.close_rounded,
                size: 22, color: AppColors.onSurfaceMuted),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      );

  Widget _typeSelector() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Tipo de ajuste',
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppColors.onSurface),
          ),
          const SizedBox(height: 10),
          Row(
            children: AdjustmentType.values.map((t) {
              final selected = _type == t;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () => setState(() => _type = t),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: selected
                            ? t.color.withValues(alpha: 0.12)
                            : AppColors.surfaceVariant,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: selected ? t.color : AppColors.border,
                          width: selected ? 1.5 : 1,
                        ),
                      ),
                      child: Column(
                        children: [
                          Icon(t.icon,
                              size: 20,
                              color: selected
                                  ? t.color
                                  : AppColors.onSurfaceMuted),
                          const SizedBox(height: 4),
                          Text(
                            t.label,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color:
                                  selected ? t.color : AppColors.onSurfaceMuted,
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

  Widget _stepper() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Cantidad  *',
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppColors.onSurface),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _stepBtn(Icons.remove_rounded, () {
                if (_quantity > 1) setState(() => _quantity--);
              }),
              Expanded(
                child: Center(
                  child: Text(
                    '$_quantity',
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w700,
                      color: AppColors.onSurface,
                    ),
                  ),
                ),
              ),
              _stepBtn(Icons.add_rounded, () => setState(() => _quantity++)),
            ],
          ),
        ],
      );

  Widget _stepBtn(IconData icon, VoidCallback onTap) => Material(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            width: 52,
            height: 52,
            child: Icon(icon, size: 24, color: AppColors.onSurface),
          ),
        ),
      );

  Widget _reasonField() => TextFormField(
        controller: _reasonCtrl,
        onChanged: (_) => setState(() {}),
        textCapitalization: TextCapitalization.sentences,
        style: const TextStyle(color: AppColors.onSurface, fontSize: 14),
        decoration: const InputDecoration(
          labelText: 'Motivo  *',
          hintText: 'Ej: Conteo físico mensual',
          prefixIcon: Icon(Icons.edit_note_rounded, size: 18),
        ),
      );

  Widget _preview() {
    final result = _resultStock;
    final isNegative = result < 0;
    final color = isNegative ? AppColors.error : _type.color;
    final arrow = _type.isIncoming ? '↑' : '↓';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Stock actual: ${widget.product.availableStock} pzs',
            style:
                const TextStyle(fontSize: 13, color: AppColors.onSurfaceMuted),
          ),
          Text(
            '$arrow Resultado: $result pzs',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _errorBanner() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.error.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            const Icon(Icons.error_outline_rounded,
                size: 16, color: AppColors.error),
            const SizedBox(width: 8),
            Expanded(
                child: Text(_error!,
                    style:
                        const TextStyle(fontSize: 13, color: AppColors.error))),
          ],
        ),
      );

  Widget _submitButton() {
    final negative = _resultStock < 0;
    final label = negative ? 'Stock insuficiente' : 'Aplicar ajuste';

    return ElevatedButton(
      onPressed: _isValid && !_isSaving ? _submit : null,
      child: _isSaving
          ? const SizedBox(
              height: 22,
              width: 22,
              child: CircularProgressIndicator(
                  strokeWidth: 2.5, color: AppColors.darkSlate))
          : Text(label),
    );
  }
}
