import 'dart:math' show max;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../../core/theme/app_colors.dart';
import '../../domain/product.dart';
import '../inventory_provider.dart';

// ---------------------------------------------------------------------------
// Modelo de almacén (mock MVP — se reemplaza con respuesta real del API
// cuando Alan complete el endpoint de warehouses)
// ---------------------------------------------------------------------------

class _Warehouse {
  const _Warehouse({required this.id, required this.name});
  final String id;
  final String name;
}

const _kWarehouses = [
  _Warehouse(id: 'wh-001', name: 'Almacén Principal'),
  _Warehouse(id: 'wh-002', name: 'Mostrador'),
  _Warehouse(id: 'wh-003', name: 'Bodega'),
];

// ---------------------------------------------------------------------------
// Función de conveniencia
// ---------------------------------------------------------------------------

Future<bool> showTransferStockModal(BuildContext context, Product product) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    backgroundColor: Colors.transparent,
    builder: (_) => TransferStockModal(product: product),
  ).then((v) => v ?? false);
}

// ---------------------------------------------------------------------------
// Widget
// ---------------------------------------------------------------------------

class TransferStockModal extends ConsumerStatefulWidget {
  const TransferStockModal({super.key, required this.product});

  final Product product;

  @override
  ConsumerState<TransferStockModal> createState() => _TransferStockModalState();
}

class _TransferStockModalState extends ConsumerState<TransferStockModal> {
  _Warehouse _from = _kWarehouses[0];
  _Warehouse _to = _kWarehouses[1];
  int _quantity = 1;
  final _notesCtrl = TextEditingController();
  bool _isSaving = false;
  String? _error;

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  // ── Validación ────────────────────────────────────────────────────────────

  bool get _sameWarehouse => _from.id == _to.id;
  bool get _exceedsStock => _quantity > widget.product.availableStock;
  bool get _isValid => !_sameWarehouse && !_exceedsStock && _quantity > 0;

  String? get _validationMessage {
    if (_sameWarehouse) return 'El origen y destino deben ser diferentes.';
    if (_exceedsStock) {
      return 'Solo hay ${widget.product.availableStock} pzs disponibles en origen.';
    }
    return null;
  }

  Future<void> _submit() async {
    if (!_isValid || _isSaving) return;
    setState(() {
      _isSaving = true;
      _error = null;
    });

    try {
      await ref.read(inventoryProvider.notifier).transferStock(
            productId: widget.product.id,
            fromWarehouseId: _from.id,
            toWarehouseId: _to.id,
            quantity: _quantity,
            notes:
                _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
          );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() {
        _isSaving = false;
        _error = 'No se pudo realizar el traslado.';
      });
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final bottomInset = max(mq.viewInsets.bottom, mq.padding.bottom);

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(24, 12, 24, 24 + bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _handle(),
          _header(),
          const SizedBox(height: 20),
          _warehouseSelectors(),
          const SizedBox(height: 20),
          _stepper(),
          const SizedBox(height: 16),
          _notesField(),
          if (_validationMessage != null) ...[
            const SizedBox(height: 10),
            _validationBanner(_validationMessage!),
          ],
          if (_error != null) ...[
            const SizedBox(height: 8),
            _errorBanner(),
          ],
          const SizedBox(height: 20),
          _submitButton(),
        ],
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
              'Trasladar stock',
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

  Widget _warehouseSelectors() => Row(
        children: [
          Expanded(
              child: _warehouseDropdown('Origen', _from, (w) {
            setState(() => _from = w);
          })),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: Icon(Icons.arrow_forward_rounded,
                size: 20, color: AppColors.onSurfaceMuted),
          ),
          Expanded(
              child: _warehouseDropdown('Destino', _to, (w) {
            setState(() => _to = w);
          })),
        ],
      );

  Widget _warehouseDropdown(
    String label,
    _Warehouse selected,
    ValueChanged<_Warehouse> onChanged,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.onSurfaceMuted,
                letterSpacing: 0.5)),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          decoration: BoxDecoration(
            color: AppColors.surfaceVariant,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<_Warehouse>(
              value: selected,
              isExpanded: true,
              dropdownColor: AppColors.surface,
              style: const TextStyle(fontSize: 13, color: AppColors.onSurface),
              icon: const Icon(Icons.expand_more_rounded,
                  size: 18, color: AppColors.onSurfaceMuted),
              items: _kWarehouses
                  .map((w) => DropdownMenuItem(
                        value: w,
                        child: Text(w.name,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13)),
                      ))
                  .toList(),
              onChanged: (w) {
                if (w != null) onChanged(w);
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _stepper() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Cantidad  *',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: AppColors.onSurface)),
              Text(
                'Disponible: ${widget.product.availableStock} pzs',
                style: const TextStyle(
                    fontSize: 12, color: AppColors.onSurfaceMuted),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _stepBtn(Icons.remove_rounded, () {
                if (_quantity > 1) setState(() => _quantity--);
              }),
              Expanded(
                child: Center(
                  child: Text('$_quantity',
                      style: const TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w700,
                          color: AppColors.onSurface)),
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
              child: Icon(icon, size: 24, color: AppColors.onSurface)),
        ),
      );

  Widget _notesField() => TextFormField(
        controller: _notesCtrl,
        textCapitalization: TextCapitalization.sentences,
        style: const TextStyle(color: AppColors.onSurface, fontSize: 14),
        decoration: const InputDecoration(
          labelText: 'Notas (opcional)',
          hintText: 'Ej: Reabastecimiento de mostrador',
          prefixIcon: Icon(Icons.edit_note_rounded, size: 18),
        ),
      );

  Widget _validationBanner(String msg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.warning.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            const Icon(Icons.warning_amber_rounded,
                size: 16, color: AppColors.warning),
            const SizedBox(width: 8),
            Expanded(
                child: Text(msg,
                    style: const TextStyle(
                        fontSize: 13, color: AppColors.warning))),
          ],
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

  Widget _submitButton() => ElevatedButton(
        onPressed: _isValid && !_isSaving ? _submit : null,
        child: _isSaving
            ? const SizedBox(
                height: 22,
                width: 22,
                child: CircularProgressIndicator(
                    strokeWidth: 2.5, color: AppColors.darkSlate))
            : const Text('Trasladar'),
      );
}
