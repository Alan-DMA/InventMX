import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/theme/app_colors.dart';
import '../../domain/banxico_denomination.dart';
import '../../domain/cash_denomination_entry.dart';
import 'cash_count_row_tile.dart';

/// Paso 1 del wizard de arqueo — "Ingreso de Denominaciones" (Subtareas
/// 9.2.1 + 9.2.2 unificadas: el modelo híbrido de tipo+valor+cantidad cubre
/// billetes y monedas en una sola tabla, sin necesitar pasos separados).
///
/// Layout inspirado en la referencia de Figma (node 77:2), re-temantizado a
/// la identidad oscura de Nexus; mismo patrón de interacción "formulario +
/// agregar a lista" que `PaymentModal` (Tarea 7.2).
class CashCountStep extends StatefulWidget {
  const CashCountStep({
    super.key,
    required this.entries,
    required this.onAdd,
    required this.onRemove,
    required this.onClearAll,
    this.onQuantityFocusChanged,
  });

  final List<CashDenominationEntry> entries;
  final void Function(BanxicoDenomination denomination, int quantity) onAdd;
  final void Function(String apiKey) onRemove;
  final VoidCallback onClearAll;

  /// Notifica cuando el campo "Cant." gana/pierde foco (teclado numérico
  /// abierto). `CloseSessionWizard` lo usa para ocultar su barra inferior
  /// mientras se edita — el `MediaQuery.viewInsets` no sirve para esto
  /// porque el `Scaffold` padre (`DashboardShell`, para mantener la barra
  /// de tabs visible) ya lo consume/zera vía `removeBottomInset` antes de
  /// que este widget lo vea.
  final ValueChanged<bool>? onQuantityFocusChanged;

  @override
  State<CashCountStep> createState() => _CashCountStepState();
}

class _CashCountStepState extends State<CashCountStep> {
  DenominationKind _selectedKind = DenominationKind.bill;
  late BanxicoDenomination _selectedDenomination = BanxicoCatalog.bills.first;
  final _quantityController = TextEditingController(text: '1');
  final _quantityFocusNode = FocusNode();

  int get _enteredQuantity => int.tryParse(_quantityController.text) ?? 0;
  bool get _canAdd => _enteredQuantity > 0;

  @override
  void initState() {
    super.initState();
    _quantityController.addListener(() => setState(() {}));
    _quantityFocusNode.addListener(_handleQuantityFocusChange);
  }

  void _handleQuantityFocusChange() {
    widget.onQuantityFocusChanged?.call(_quantityFocusNode.hasFocus);
  }

  @override
  void dispose() {
    _quantityController.dispose();
    _quantityFocusNode.dispose();
    super.dispose();
  }

  void _onKindChanged(DenominationKind? kind) {
    if (kind == null) return;
    setState(() {
      _selectedKind = kind;
      _selectedDenomination = BanxicoCatalog.byKind(kind).first;
    });
  }

  void _add() {
    if (!_canAdd) return;
    final quantity = _enteredQuantity;
    final denomination = _selectedDenomination;
    widget.onAdd(denomination, quantity);
    setState(() => _quantityController.text = '1');

    // Cierra el teclado de inmediato y confirma la acción: sin esto, el
    // teclado tapa la tabla de desglose y el cambio pasa desapercibido.
    FocusScope.of(context).unfocus();
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Agregado: $quantity ${quantity == 1 ? 'ud' : 'uds'} de '
          '${denomination.kind.label.toLowerCase()} \$${denomination.displayValue}',
        ),
        backgroundColor: AppColors.surface,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _confirmClearAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Vaciar desglose',
            style: TextStyle(color: AppColors.onSurface, fontWeight: FontWeight.w700)),
        content: const Text(
          '¿Eliminar todas las denominaciones ingresadas?',
          style: TextStyle(color: AppColors.onSurfaceMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar',
                style: TextStyle(color: AppColors.onSurfaceMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Vaciar', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirmed == true) widget.onClearAll();
  }

  /// El padre (`CloseSessionWizard`) da a este widget una altura acotada
  /// (vía `Expanded`) y desactiva el resize por teclado (`resizeToAvoidBottomInset:
  /// false`) para que la barra inferior no "suba" junto al teclado. Por eso
  /// aquí el scroll vive únicamente en la tabla de desglose: el título, el
  /// formulario y el encabezado quedan fijos (no se desplazan), y solo
  /// `_buildList()` — envuelta en `Expanded` — se encoge o hace scroll.
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Ingreso de Denominaciones',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppColors.onSurface,
          ),
        ),
        const SizedBox(height: 2),
        const Text(
          'Selecciona el tipo, valor y cantidad a ingresar',
          style: TextStyle(fontSize: 12, color: AppColors.onSurfaceMuted),
        ),
        const SizedBox(height: 12),
        _buildForm(),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Flexible(
                    child: Text(
                      'Desglose Ingresado',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.onSurface,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceVariant,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${widget.entries.length}',
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.onSurfaceMuted,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (widget.entries.isNotEmpty)
              TextButton(
                onPressed: _confirmClearAll,
                child: const Text('Vaciar todo',
                    style: TextStyle(fontSize: 12, color: AppColors.error)),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(child: _buildList()),
      ],
    );
  }

  Widget _buildList() {
    if (widget.entries.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        alignment: Alignment.center,
        child: const Text(
          'Aún no agregas ninguna denominación',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: AppColors.onSurfaceMuted),
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: ListView.separated(
        itemCount: widget.entries.length,
        separatorBuilder: (_, __) => const Divider(height: 1, color: AppColors.border),
        itemBuilder: (_, i) => CashCountRowTile(
          entry: widget.entries[i],
          onRemove: () => widget.onRemove(widget.entries[i].denomination.apiKey),
        ),
      ),
    );
  }

  /// Tipo, Valor y Cantidad viven en una sola fila (como en la referencia
  /// de Figma, node 77:2) — la versión con Cantidad en su propia fila le
  /// costaba ~60-70px extra al formulario, quitándoselos a la tabla de
  /// desglose de abajo, que es el elemento que debe predominar en pantalla.
  Widget _buildForm() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 4, child: _buildKindDropdown()),
              const SizedBox(width: 6),
              Expanded(flex: 4, child: _buildDenominationDropdown()),
              const SizedBox(width: 6),
              Expanded(flex: 5, child: _buildQuantityField()),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 40,
            child: ElevatedButton.icon(
              onPressed: _canAdd ? _add : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.emerald,
                foregroundColor: AppColors.darkSlate,
                disabledBackgroundColor: AppColors.surfaceVariant,
                disabledForegroundColor: AppColors.onSurfaceMuted,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                elevation: 0,
              ),
              icon: const Icon(Icons.add_rounded, size: 16),
              label: const Text('Agregar',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLabeledField(String label, Widget field) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(fontSize: 11, color: AppColors.onSurfaceMuted)),
        const SizedBox(height: 4),
        field,
      ],
    );
  }

  Widget _buildKindDropdown() {
    return _buildLabeledField(
      'Tipo',
      Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(8),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<DenominationKind>(
            value: _selectedKind,
            isExpanded: true,
            dropdownColor: AppColors.surface,
            icon: const Icon(Icons.expand_more_rounded,
                size: 14, color: AppColors.onSurfaceMuted),
            style: const TextStyle(fontSize: 12, color: AppColors.onSurface),
            items: DenominationKind.values
                .map((k) => DropdownMenuItem(
                      value: k,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              color: kindColor(k),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Flexible(child: Text(k.label, overflow: TextOverflow.ellipsis)),
                        ],
                      ),
                    ))
                .toList(),
            onChanged: _onKindChanged,
          ),
        ),
      ),
    );
  }

  Widget _buildDenominationDropdown() {
    final options = BanxicoCatalog.byKind(_selectedKind);
    return _buildLabeledField(
      'Valor',
      Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(8),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<BanxicoDenomination>(
            value: _selectedDenomination,
            isExpanded: true,
            dropdownColor: AppColors.surface,
            icon: const Icon(Icons.expand_more_rounded,
                size: 14, color: AppColors.onSurfaceMuted),
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.onSurface,
            ),
            items: options
                .map((d) => DropdownMenuItem(
                      value: d,
                      child: Text('\$${d.displayValue}'),
                    ))
                .toList(),
            onChanged: (d) {
              if (d == null) return;
              setState(() => _selectedDenomination = d);
            },
          ),
        ),
      ),
    );
  }

  bool get _canDecrement => _enteredQuantity > 1;

  void _incrementQuantity() {
    _setQuantity(_enteredQuantity + 1);
  }

  void _decrementQuantity() {
    if (!_canDecrement) return;
    _setQuantity(_enteredQuantity - 1);
  }

  void _setQuantity(int value) {
    _quantityController.text = '$value';
    _quantityController.selection =
        TextSelection.collapsed(offset: _quantityController.text.length);
  }

  Widget _buildQuantityField() {
    return _buildLabeledField(
      'Cant.',
      Container(
        height: 44,
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            _buildStepButton(
              icon: Icons.remove_rounded,
              onTap: _canDecrement ? _decrementQuantity : null,
            ),
            Expanded(
              child: TextField(
                controller: _quantityController,
                focusNode: _quantityFocusNode,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.onSurface,
                ),
                onSubmitted: (_) => _add(),
                decoration: const InputDecoration(
                  isDense: true,
                  filled: false,
                  contentPadding: EdgeInsets.zero,
                  border: InputBorder.none,
                ),
              ),
            ),
            _buildStepButton(
              icon: Icons.add_rounded,
              onTap: _incrementQuantity,
            ),
          ],
        ),
      ),
    );
  }

  /// Botón +/- del selector de cantidad — complementa (no reemplaza) la
  /// entrada por teclado, para ajustar cantidades pequeñas sin abrir el
  /// teclado numérico.
  Widget _buildStepButton({required IconData icon, required VoidCallback? onTap}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 26,
          height: 44,
          child: Icon(
            icon,
            size: 14,
            color: onTap == null
                ? AppColors.onSurfaceMuted.withValues(alpha: 0.4)
                : AppColors.onSurfaceMuted,
          ),
        ),
      ),
    );
  }
}
