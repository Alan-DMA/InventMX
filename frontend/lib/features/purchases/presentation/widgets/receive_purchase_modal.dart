import 'dart:math' show max;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import '../../domain/purchase_order.dart';
import '../purchases_provider.dart';

/// Modal de recepción de mercancía — Subtarea 11.2.1 (botón "Recibir" de la
/// tarjeta de orden). Permite recepción total o parcial por línea, igual que
/// `POST /purchase-orders/{id}/receive` (docs/api/purchases.yaml).
Future<bool> showReceivePurchaseModal(BuildContext context, PurchaseOrder order) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    backgroundColor: Colors.transparent,
    builder: (_) => ReceivePurchaseModal(order: order),
  ).then((v) => v ?? false);
}

class ReceivePurchaseModal extends ConsumerStatefulWidget {
  const ReceivePurchaseModal({super.key, required this.order});

  final PurchaseOrder order;

  @override
  ConsumerState<ReceivePurchaseModal> createState() => _ReceivePurchaseModalState();
}

class _ReceivePurchaseModalState extends ConsumerState<ReceivePurchaseModal> {
  late final Map<String, int> _received = {
    for (final item in widget.order.items)
      item.productId: item.quantity - item.quantityReceived,
  };
  bool _isSaving = false;
  String? _error;

  bool get _hasAnyReceipt => _received.values.any((q) => q > 0);

  Future<void> _submit() async {
    if (!_hasAnyReceipt || _isSaving) return;
    setState(() {
      _isSaving = true;
      _error = null;
    });

    final updatedItems = widget.order.items.map((item) {
      final justReceived = _received[item.productId] ?? 0;
      return item.copyWith(
        quantityReceived: item.quantityReceived + justReceived,
      );
    }).toList();

    try {
      await ref.read(purchaseOrdersProvider.notifier).receiveOrder(
            purchaseOrderId: widget.order.id,
            updatedItems: updatedItems,
          );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() {
        _isSaving = false;
        _error = 'No se pudo registrar la recepción.';
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
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Recibir ${widget.order.folio}',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppColors.onSurface,
                    ),
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
              widget.order.supplierName,
              style: const TextStyle(fontSize: 13, color: AppColors.onSurfaceMuted),
            ),
            const SizedBox(height: 16),
            ...widget.order.items.map(_buildItemRow),
            if (_error != null) ...[
              const SizedBox(height: 8),
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
              onPressed: _hasAnyReceipt && !_isSaving ? _submit : null,
              child: _isSaving
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.darkSlate),
                    )
                  : const Text('Confirmar recepción'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildItemRow(PurchaseOrderItem item) {
    final pending = item.quantity - item.quantityReceived;
    final current = _received[item.productId] ?? 0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.productName,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.onSurface),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Pendiente: $pending / ${item.quantity} pzs',
                    style: const TextStyle(fontSize: 12, color: AppColors.onSurfaceMuted),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: current > 0
                  ? () => setState(() => _received[item.productId] = current - 1)
                  : null,
              icon: const Icon(Icons.remove_circle_outline_rounded, size: 20),
              color: AppColors.onSurfaceMuted,
            ),
            SizedBox(
              width: 32,
              child: Text(
                '$current',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.onSurface),
              ),
            ),
            IconButton(
              onPressed: current < pending
                  ? () => setState(() => _received[item.productId] = current + 1)
                  : null,
              icon: const Icon(Icons.add_circle_outline_rounded, size: 20),
              color: AppColors.emerald,
            ),
          ],
        ),
      ),
    );
  }
}
