import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../saas_admin/domain/subscription.dart' show mxn;
import '../../data/sales_repository.dart';
import '../../domain/cart_item.dart';
import '../../domain/cart_state.dart';

// ---------------------------------------------------------------------------
// Función de conveniencia
// ---------------------------------------------------------------------------

/// Abre la hoja de reembolso para [sale]. Retorna la venta actualizada (con
/// `refund` ya aplicado) si se confirmó, o `null` si se canceló.
///
/// Trazabilidad: docs/api/sales.yaml `POST /sales/{id}/refund` (acciones
/// sobre la venta, Fase 2 — evaluado con `/intent:fortify`, Sep 2026).
Future<CheckoutResult?> showRefundSaleModal(
  BuildContext context, {
  required CheckoutResult sale,
}) {
  return showModalBottomSheet<CheckoutResult>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    backgroundColor: Colors.transparent,
    builder: (_) => RefundSaleModal(sale: sale),
  );
}

// ---------------------------------------------------------------------------
// Widget principal
// ---------------------------------------------------------------------------

/// Hoja transaccional de reembolso — hermana de `PaymentModal` (mismo
/// patrón: `StatefulWidget` local, sin provider, para un flujo corto que se
/// llena y se descarta).
///
/// Total y parcial son el mismo control: un contador por ítem acotado a su
/// cantidad original; "Reembolsar todo" simplemente los sube al máximo.
class RefundSaleModal extends ConsumerStatefulWidget {
  const RefundSaleModal({super.key, required this.sale});

  final CheckoutResult sale;

  @override
  ConsumerState<RefundSaleModal> createState() => _RefundSaleModalState();
}

class _RefundSaleModalState extends ConsumerState<RefundSaleModal> {
  late final Map<String, int> _quantities = {
    for (final item in widget.sale.items) item.id: 0,
  };
  final _reasonController = TextEditingController();
  bool _refundToStock = true;
  bool _isSubmitting = false;
  String? _error;

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  double get _totalToRefund => widget.sale.items.fold<double>(
        0,
        (sum, item) => sum + item.unitPriceMxn * (_quantities[item.id] ?? 0),
      );

  bool get _hasSelection => _quantities.values.any((q) => q > 0);

  bool get _canSubmit =>
      _hasSelection &&
      _reasonController.text.trim().isNotEmpty &&
      !_isSubmitting;

  void _setAll(bool refundEverything) {
    setState(() {
      for (final item in widget.sale.items) {
        _quantities[item.id] = refundEverything ? item.quantity : 0;
      }
    });
  }

  void _setQuantity(CartItem item, int quantity) {
    setState(() => _quantities[item.id] = quantity.clamp(0, item.quantity));
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() {
      _isSubmitting = true;
      _error = null;
    });

    final lines = [
      for (final item in widget.sale.items)
        if ((_quantities[item.id] ?? 0) > 0)
          RefundedLine(cartItemId: item.id, quantity: _quantities[item.id]!),
    ];
    final isFull = widget.sale.items.every(
      (item) => (_quantities[item.id] ?? 0) == item.quantity,
    );

    try {
      final updated = await ref.read(salesRepositoryProvider).refundSale(
            saleId: widget.sale.saleId,
            reason: _reasonController.text.trim(),
            refundToStock: _refundToStock,
            // Toda la venta al máximo: se manda null, igual que "sin
            // itemsToRefund" en el contrato ("si se omite, se reembolsa
            // toda la venta") en vez de listar cada línea.
            itemsToRefund: isFull ? null : lines,
          );
      if (!mounted) return;
      Navigator.of(context).pop(updated);
    } on SaleAlreadyRefundedException {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _error = 'Esta venta ya fue reembolsada.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _error = 'No se pudo procesar el reembolso: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.viewInsetsOf(context);

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, scrollController) => Padding(
        padding: EdgeInsets.only(bottom: viewInsets.bottom),
        child: Container(
          decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          // `top: false`: el handle ya empieza pegado al borde de la hoja,
          // sólo el pie con el botón necesita respetar la barra de
          // navegación del sistema. Sin esto, en un teléfono con navegación
          // de 3 botones (la norma en la gama baja a la que apunta Nexus)
          // "Reembolsar" queda cortado por la barra — se detectó probando
          // en el Samsung A07 real, no en la inspección visual de escritorio.
          child: SafeArea(
            top: false,
            child: Column(
              children: [
                _handle(),
                _header(),
                const Divider(height: 1, color: AppColors.border),
                Expanded(
                  child: ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Ítems de la venta',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AppColors.onSurfaceMuted,
                              letterSpacing: 0.4,
                            ),
                          ),
                          TextButton(
                            key: const Key('refundAllButton'),
                            onPressed: () => _setAll(true),
                            style: TextButton.styleFrom(
                              foregroundColor: AppColors.skyBlue,
                              padding: EdgeInsets.zero,
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: const Text(
                              'Reembolsar todo',
                              style: TextStyle(
                                  fontSize: 12, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      for (final item in widget.sale.items) ...[
                        _ItemRow(
                          item: item,
                          quantity: _quantities[item.id] ?? 0,
                          onChanged: (q) => _setQuantity(item, q),
                        ),
                        const SizedBox(height: 8),
                      ],
                      const SizedBox(height: 4),
                      const Divider(height: 1, color: AppColors.border),
                      const SizedBox(height: 16),
                      const Text(
                        'Motivo',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.onSurfaceMuted,
                          letterSpacing: 0.4,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        key: const Key('refundReasonField'),
                        controller: _reasonController,
                        maxLength: 200,
                        maxLines: 2,
                        minLines: 1,
                        onChanged: (_) => setState(() {}),
                        style: const TextStyle(
                            color: AppColors.onSurface, fontSize: 14),
                        decoration: InputDecoration(
                          hintText: 'Ej. Producto defectuoso, cobro duplicado…',
                          hintStyle:
                              const TextStyle(color: AppColors.onSurfaceMuted),
                          filled: true,
                          fillColor: AppColors.surfaceVariant,
                          counterStyle: const TextStyle(
                              color: AppColors.onSurfaceMuted, fontSize: 11),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide:
                                const BorderSide(color: AppColors.border),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide:
                                const BorderSide(color: AppColors.border),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide:
                                const BorderSide(color: AppColors.borderFocus),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _RefundToStockSwitch(
                        value: _refundToStock,
                        onChanged: (v) => setState(() => _refundToStock = v),
                      ),
                    ],
                  ),
                ),
                _footer(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _handle() => Center(
        child: Container(
          width: 40,
          height: 4,
          margin: const EdgeInsets.only(top: 12, bottom: 8),
          decoration: BoxDecoration(
            color: AppColors.border,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      );

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 8, 12),
      child: Row(
        children: [
          const Icon(Icons.assignment_return_rounded,
              size: 18, color: AppColors.onSurfaceMuted),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Reembolsar venta',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.onSurface,
                  ),
                ),
                Text(
                  widget.sale.folio,
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.onSurfaceMuted),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.close_rounded,
                size: 20, color: AppColors.onSurfaceMuted),
          ),
        ],
      ),
    );
  }

  Widget _footer() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // En el pie, no en la lista: un error que cae más abajo de lo
          // que el cajero alcanzó a desplazar pasa inadvertido.
          if (_error != null) ...[
            Container(
              key: const Key('refundErrorBanner'),
              padding: const EdgeInsets.all(10),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
                border:
                    Border.all(color: AppColors.error.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline_rounded,
                      size: 16, color: AppColors.error),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _error!,
                      style: const TextStyle(
                          color: AppColors.error, fontSize: 12.5),
                    ),
                  ),
                ],
              ),
            ),
          ],
          Row(
            children: [
              const Text(
                'Total a reembolsar',
                style: TextStyle(fontSize: 13, color: AppColors.onSurfaceMuted),
              ),
              const Spacer(),
              Text(
                mxn(_totalToRefund),
                key: const Key('refundTotalPreview'),
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: AppColors.onSurface,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 52,
            child: ElevatedButton.icon(
              key: const Key('confirmRefundButton'),
              onPressed: _canSubmit ? _submit : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                disabledBackgroundColor:
                    AppColors.error.withValues(alpha: 0.35),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              icon: _isSubmitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.assignment_return_rounded, size: 20),
              label: Text(
                _isSubmitting ? 'Reembolsando…' : 'Reembolsar',
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Renglón de ítem con contador
// ---------------------------------------------------------------------------

class _ItemRow extends StatelessWidget {
  const _ItemRow(
      {required this.item, required this.quantity, required this.onChanged});

  final CartItem item;
  final int quantity;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final selected = quantity > 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: selected
            ? AppColors.error.withValues(alpha: 0.06)
            : AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: selected
                ? AppColors.error.withValues(alpha: 0.35)
                : AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.onSurface,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '${mxn(item.unitPriceMxn)} c/u · vendidos ${item.quantity}',
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.onSurfaceMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _Stepper(
            quantity: quantity,
            max: item.quantity,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper(
      {required this.quantity, required this.max, required this.onChanged});

  final int quantity;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _stepButton(
          icon: Icons.remove_rounded,
          onTap: quantity > 0 ? () => onChanged(quantity - 1) : null,
        ),
        SizedBox(
          width: 22,
          child: Text(
            '$quantity',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.onSurface,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ),
        _stepButton(
          icon: Icons.add_rounded,
          onTap: quantity < max ? () => onChanged(quantity + 1) : null,
        ),
      ],
    );
  }

  Widget _stepButton({required IconData icon, required VoidCallback? onTap}) {
    final enabled = onTap != null;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: enabled ? AppColors.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
                color: enabled ? AppColors.border : Colors.transparent),
          ),
          child: Icon(
            icon,
            size: 16,
            color: enabled
                ? AppColors.onSurface
                : AppColors.onSurfaceMuted.withValues(alpha: 0.4),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Switch "¿regresa al inventario?"
// ---------------------------------------------------------------------------

class _RefundToStockSwitch extends StatelessWidget {
  const _RefundToStockSwitch({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '¿Regresa al inventario?',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value
                      ? 'El producto vuelve a venderse'
                      : 'No — se descarta (defectuoso, caducado)',
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.onSurfaceMuted),
                ),
              ],
            ),
          ),
          Switch(
            key: const Key('refundToStockSwitch'),
            value: value,
            onChanged: onChanged,
            activeThumbColor: AppColors.emerald,
          ),
        ],
      ),
    );
  }
}
