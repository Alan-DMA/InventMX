import 'dart:math' show max;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import '../../domain/account_payable.dart';
import '../purchases_provider.dart';

/// Modal de abono a una cuenta por pagar — Subtarea 11.2.3, equivalente a
/// `POST /accounts-payable/{id}/pay` (docs/api/purchases.yaml).
Future<bool> showPaymentModal(BuildContext context, AccountPayable payable) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    backgroundColor: Colors.transparent,
    builder: (_) => PaymentModal(payable: payable),
  ).then((v) => v ?? false);
}

class PaymentModal extends ConsumerStatefulWidget {
  const PaymentModal({super.key, required this.payable});

  final AccountPayable payable;

  @override
  ConsumerState<PaymentModal> createState() => _PaymentModalState();
}

class _PaymentModalState extends ConsumerState<PaymentModal> {
  final _amountCtrl = TextEditingController();
  SupplierPaymentMethod _method = SupplierPaymentMethod.spei;
  bool _isSaving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _amountCtrl.text = widget.payable.balanceMxn.toStringAsFixed(2);
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  double? get _amount => double.tryParse(_amountCtrl.text.replaceAll(',', ''));

  bool get _isValid {
    final amount = _amount;
    return amount != null && amount > 0 && amount <= widget.payable.balanceMxn + 0.005;
  }

  Future<void> _submit() async {
    final amount = _amount;
    if (!_isValid || amount == null || _isSaving) return;
    setState(() {
      _isSaving = true;
      _error = null;
    });

    try {
      await ref.read(accountsPayableProvider.notifier).registerPayment(
            accountPayableId: widget.payable.id,
            amountPaidMxn: amount,
            paymentMethod: _method,
          );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() {
        _isSaving = false;
        _error = 'El abono excede el saldo pendiente o no pudo registrarse.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = max(
      MediaQuery.of(context).viewInsets.bottom,
      MediaQuery.of(context).padding.bottom,
    );

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
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Abonar a ${widget.payable.supplierName}',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.onSurface),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  icon: const Icon(Icons.close_rounded, size: 22, color: AppColors.onSurfaceMuted),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Saldo pendiente: \$${widget.payable.balanceMxn.toStringAsFixed(2)} MXN',
              style: const TextStyle(fontSize: 13, color: AppColors.onSurfaceMuted),
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _amountCtrl,
              onChanged: (_) => setState(() {}),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(color: AppColors.onSurface, fontSize: 16, fontWeight: FontWeight.w600),
              decoration: const InputDecoration(
                labelText: 'Monto a abonar (MXN)  *',
                prefixIcon: Icon(Icons.attach_money_rounded, size: 18),
              ),
            ),
            const SizedBox(height: 16),
            const Text('Método de pago', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.onSurface)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: SupplierPaymentMethod.values.map((m) {
                final selected = m == _method;
                return ChoiceChip(
                  label: Text(m.label),
                  selected: selected,
                  onSelected: (_) => setState(() => _method = m),
                  selectedColor: AppColors.emerald.withValues(alpha: 0.2),
                  labelStyle: TextStyle(
                    color: selected ? AppColors.emerald : AppColors.onSurfaceMuted,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                  backgroundColor: AppColors.surfaceVariant,
                  side: BorderSide(color: selected ? AppColors.emerald : AppColors.border),
                );
              }).toList(),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
                ),
                child: Text(_error!, style: const TextStyle(fontSize: 13, color: AppColors.error)),
              ),
            ],
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _isValid && !_isSaving ? _submit : null,
              child: _isSaving
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.darkSlate),
                    )
                  : const Text('Confirmar abono'),
            ),
          ],
        ),
      ),
    );
  }
}
