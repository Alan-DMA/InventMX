import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/theme/app_colors.dart';
import '../../domain/payment_entry.dart';
import 'payment_row_tile.dart';

// ---------------------------------------------------------------------------
// Ícono por método de pago — mapeo presentación-only (el dominio se mantiene
// libre de dependencias de Flutter).
// ---------------------------------------------------------------------------

extension PaymentMethodIconX on PaymentMethodMxn {
  IconData get icon => switch (this) {
        PaymentMethodMxn.cashMxn => Icons.payments_rounded,
        PaymentMethodMxn.spei => Icons.account_balance_rounded,
        PaymentMethodMxn.cardTpv => Icons.credit_card_rounded,
        PaymentMethodMxn.codi => Icons.qr_code_rounded,
        PaymentMethodMxn.other => Icons.more_horiz_rounded,
      };
}

// ---------------------------------------------------------------------------
// Función de conveniencia para abrir el modal
// ---------------------------------------------------------------------------

/// Abre el modal de cobro con métodos de pago mixtos.
/// Retorna la lista de pagos confirmada, o null si el usuario cancela.
Future<List<PaymentEntry>?> showPaymentModal(
  BuildContext context, {
  required double totalMxn,
}) {
  return showModalBottomSheet<List<PaymentEntry>>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    backgroundColor: Colors.transparent,
    builder: (_) => PaymentModal(totalMxn: totalMxn),
  );
}

// ---------------------------------------------------------------------------
// Widget principal
// ---------------------------------------------------------------------------

/// Modal de cobro y métodos de pago mixtos — Tarea 7.2 (`PaymentModal`).
///
/// Layout inspirado en la referencia visual de Figma (node 63:312), adaptado
/// a la identidad visual oscura de Nexus y sin el detalle operacional de
/// denominaciones/verificación que se descartó en el plan aprobado.
///
/// Trazabilidad: Constitución Art. VII (7.2) · Doc. Maestro RF-14, SR-04 · HU-13 / CU-14
class PaymentModal extends StatefulWidget {
  const PaymentModal({super.key, required this.totalMxn});

  final double totalMxn;

  @override
  State<PaymentModal> createState() => _PaymentModalState();
}

class _PaymentModalState extends State<PaymentModal> {
  final _amountController = TextEditingController();
  final _referenceController = TextEditingController();

  PaymentMethodMxn _selectedMethod = PaymentMethodMxn.cashMxn;
  final List<PaymentEntry> _payments = [];
  int _idCounter = 0;

  // ── Cálculos derivados ───────────────────────────────────────────────────

  double get _paidMxn =>
      _payments.fold(0.0, (sum, p) => sum + p.amountMxn);

  /// Positivo = cambio a devolver. Negativo = falta por cubrir.
  double get _differenceMxn => _paidMxn - widget.totalMxn;

  bool get _isCovered => _payments.isNotEmpty && _differenceMxn >= 0;

  double get _enteredAmount =>
      double.tryParse(_amountController.text.replaceAll(',', '.')) ?? 0;

  bool get _canAdd => _enteredAmount > 0;

  @override
  void initState() {
    super.initState();
    _amountController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _amountController.dispose();
    _referenceController.dispose();
    super.dispose();
  }

  // ── Acciones ─────────────────────────────────────────────────────────────

  void _addPayment() {
    if (!_canAdd) return;
    final reference = _referenceController.text.trim();

    setState(() {
      _payments.add(PaymentEntry(
        id: 'pay-${++_idCounter}',
        method: _selectedMethod,
        amountMxn: _enteredAmount,
        referenceCode: reference.isEmpty ? null : reference,
      ));
      _amountController.clear();
      _referenceController.clear();
    });
  }

  void _removePayment(String id) {
    setState(() => _payments.removeWhere((p) => p.id == id));
  }

  void _confirm() {
    if (!_isCovered) return;
    Navigator.of(context).pop(List<PaymentEntry>.of(_payments));
  }

  // ── Build ───────────────────────────────────────────────────────────────

  /// Proporción fija del alto de pantalla que ocupa el modal — se mantiene
  /// constante sin importar cuántos pagos se hayan agregado, para que la
  /// pantalla anterior siga parcialmente visible detrás y el modal no
  /// "salte" de tamaño al agregar el primer pago.
  static const double _kSheetHeightRatio = 0.75;

  /// Piso mínimo en píxeles: header + formulario (con el campo de folio
  /// visible, su variante más alta) + resumen + CTA — todo lo que ahora
  /// permanece siempre fijo — necesitan este espacio como mínimo para no
  /// desbordar, incluso si el % de pantalla diera un número menor.
  static const double _kMinSheetHeight = 560;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);

    // Alto disponible por encima del teclado. El modal nunca pide más
    // espacio del que realmente existe una vez que el teclado está abierto,
    // lo que evita el RenderFlex overflow al escribir el monto.
    final availableHeight = mq.size.height - mq.viewInsets.bottom;
    final preferredHeight =
        math.max(mq.size.height * _kSheetHeightRatio, _kMinSheetHeight);
    final sheetHeight = preferredHeight.clamp(0.0, availableHeight);

    return Padding(
      padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
      child: SizedBox(
        height: sheetHeight,
        child: Container(
          decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              // Header, formulario, resumen financiero (Total a pagar /
              // Pagado / Faltan-Cambio) y el CTA permanecen siempre fijos —
              // el usuario nunca debe perder de vista en qué punto del cobro
              // está. Solo la lista de pagos ya agregados hace scroll
              // interno cuando no caben todos a la vez.
              _buildHeader(),
              _buildAddForm(),
              Expanded(child: _buildPaymentsList()),
              _buildSummary(),
              _buildFooter(mq.padding.bottom),
            ],
          ),
        ),
      ),
    );
  }

  // ── 1. Header ────────────────────────────────────────────────────────────

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 16, 4),
      child: Column(
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Seleccionar métodos de pago',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AppColors.onSurface,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Registra pagos parciales o combinados',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.onSurfaceMuted,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded,
                    size: 22, color: AppColors.onSurfaceMuted),
                tooltip: 'Cerrar',
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── 2. Formulario de alta ────────────────────────────────────────────────

  Widget _buildAddForm() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'AGREGAR MÉTODO DE PAGO',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.onSurfaceMuted,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 7, child: _buildMethodDropdown()),
              const SizedBox(width: 8),
              Expanded(flex: 3, child: _buildAmountField()),
            ],
          ),
          if (_selectedMethod.requiresReference) ...[
            const SizedBox(height: 10),
            _buildReferenceField(),
          ],
          const SizedBox(height: 10),
          _buildAddButton(),
        ],
      ),
    );
  }

  Widget _buildAddButton() {
    return SizedBox(
      width: double.infinity,
      height: 40,
      child: ElevatedButton.icon(
        onPressed: _canAdd ? _addPayment : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.emerald,
          foregroundColor: AppColors.darkSlate,
          disabledBackgroundColor: AppColors.surfaceVariant,
          disabledForegroundColor: AppColors.onSurfaceMuted,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 0,
        ),
        icon: const Icon(Icons.add_rounded, size: 18),
        label: const Text('Agregar método',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
      ),
    );
  }

  Widget _buildMethodDropdown() {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<PaymentMethodMxn>(
          value: _selectedMethod,
          isExpanded: true,
          dropdownColor: AppColors.surface,
          icon: const Icon(Icons.expand_more_rounded,
              size: 18, color: AppColors.onSurfaceMuted),
          style: const TextStyle(fontSize: 14, color: AppColors.onSurface),
          items: PaymentMethodMxn.values
              .map((m) => DropdownMenuItem(
                    value: m,
                    child: Row(
                      children: [
                        Icon(m.icon, size: 16, color: AppColors.onSurfaceMuted),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            m.label,
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                      ],
                    ),
                  ))
              .toList(),
          onChanged: (m) {
            if (m == null) return;
            setState(() => _selectedMethod = m);
          },
        ),
      ),
    );
  }

  Widget _buildAmountField() {
    return SizedBox(
      height: 44,
      child: TextField(
        controller: _amountController,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[\d.,]')),
        ],
        textAlign: TextAlign.right,
        style: const TextStyle(
          fontFamily: 'monospace',
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: AppColors.onSurface,
        ),
        onSubmitted: (_) => _addPayment(),
        decoration: const InputDecoration(
          isDense: true,
          hintText: '0.00',
          prefixText: '\$ ',
          prefixStyle: TextStyle(
            fontFamily: 'monospace',
            color: AppColors.onSurfaceMuted,
            fontSize: 14,
          ),
          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        ),
      ),
    );
  }

  Widget _buildReferenceField() {
    return TextField(
      controller: _referenceController,
      textCapitalization: TextCapitalization.characters,
      style: const TextStyle(fontSize: 14, color: AppColors.onSurface),
      decoration: const InputDecoration(
        isDense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        hintText: 'Folio o referencia (opcional)',
        prefixIcon: Icon(Icons.receipt_long_outlined, size: 18),
      ),
    );
  }

  // ── 3. Lista scrollable de pagos agregados ──────────────────────────────

  Widget _buildPaymentsList() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text(
                'PAGOS INGRESADOS (${_payments.length})',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.onSurfaceMuted,
                  letterSpacing: 0.6,
                ),
              ),
              if (_payments.isNotEmpty) ...[
                const SizedBox(width: 8),
                const Flexible(
                  child: Text(
                    'Toca el bote para descartar',
                    textAlign: TextAlign.right,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        TextStyle(fontSize: 11, color: AppColors.onSurfaceMuted),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Expanded(
            child: _payments.isEmpty
                ? const Center(
                    child: Text(
                      'Aún no agregas ningún método',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.onSurfaceMuted,
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: EdgeInsets.zero,
                    itemCount: _payments.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1, color: AppColors.border),
                    itemBuilder: (_, i) => PaymentRowTile(
                      entry: _payments[i],
                      onRemove: () => _removePayment(_payments[i].id),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  // ── 4. Resumen financiero ────────────────────────────────────────────────

  Widget _buildSummary() {
    final isCovered = _isCovered;
    final differenceLabel = isCovered ? 'Cambio a devolver' : 'Faltan';
    final differenceAmount = _differenceMxn.abs();
    final differenceColor = isCovered ? AppColors.emerald : AppColors.warning;

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 10, 24, 4),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _summaryRow('Total a pagar', widget.totalMxn),
          const SizedBox(height: 4),
          _summaryRow('Pagado', _paidMxn),
          const SizedBox(height: 8),
          const Divider(height: 1, color: AppColors.border),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Text(
                    differenceLabel,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: AppColors.onSurface,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: differenceColor,
                    ),
                  ),
                ],
              ),
              Text(
                '\$${differenceAmount.toStringAsFixed(2)} MXN',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: differenceColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
        ],
      ),
    );
  }

  Widget _summaryRow(String label, double amountMxn) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style:
                const TextStyle(fontSize: 14, color: AppColors.onSurfaceMuted)),
        Text(
          '\$${amountMxn.toStringAsFixed(2)}',
          style: const TextStyle(
            fontFamily: 'monospace',
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppColors.onSurface,
          ),
        ),
      ],
    );
  }

  // ── 5. CTA ───────────────────────────────────────────────────────────────

  Widget _buildFooter(double safeAreaBottom) {
    return Container(
      padding: EdgeInsets.fromLTRB(24, 8, 24, 12 + safeAreaBottom),
      child: SizedBox(
        width: double.infinity,
        height: 52,
        child: ElevatedButton.icon(
          onPressed: _isCovered ? _confirm : null,
          icon: const Icon(Icons.check_circle_rounded, size: 20),
          label: Text(
            'Confirmar cobro \$${widget.totalMxn.toStringAsFixed(2)} MXN',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
        ),
      ),
    );
  }
}
