import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../../core/theme/app_colors.dart';

/// Card que aparece tras detectar un código EAN en el modo Góndola.
///
/// Si el EAN está en el catálogo semilla muestra el nombre autocompletado.
/// Si no está, permite ingresar el nombre manualmente.
/// El usuario confirma precio y stock antes de guardar el producto.
class ScanResultCard extends StatefulWidget {
  const ScanResultCard({
    super.key,
    required this.barcode,
    this.suggestedName,
    this.suggestedCategory,
    required this.onConfirm,
    required this.onDismiss,
  });

  /// Código EAN escaneado.
  final String barcode;

  /// Nombre del producto si se encontró en el catálogo semilla (puede ser null).
  final String? suggestedName;

  /// Categoría sugerida del catálogo (puede ser null).
  final String? suggestedCategory;

  /// Callback con (name, priceMxn, stock) cuando el usuario confirma.
  final void Function(String name, double priceMxn, int stock) onConfirm;

  /// Callback para descartar la card y volver a escanear.
  final VoidCallback onDismiss;

  @override
  State<ScanResultCard> createState() => _ScanResultCardState();
}

class _ScanResultCardState extends State<ScanResultCard> {
  late final TextEditingController _nameCon;
  late final TextEditingController _priceCon;
  late final TextEditingController _stockCon;

  late final FocusNode _nameFocus;
  late final FocusNode _priceFocus;

  bool get _isFromCatalog => widget.suggestedName != null;

  bool get _isValid {
    final name = _nameCon.text.trim();
    final price = double.tryParse(_priceCon.text.replaceAll(',', '.')) ?? 0;
    return name.length >= 2 && price > 0;
  }

  @override
  void initState() {
    super.initState();
    _nameCon = TextEditingController(text: widget.suggestedName ?? '');
    _priceCon = TextEditingController();
    _stockCon = TextEditingController(text: '1');
    _nameFocus = FocusNode();
    _priceFocus = FocusNode();

    // Si el nombre no viene del catálogo, foco en nombre; si viene, en precio
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_isFromCatalog) {
        _nameFocus.requestFocus();
      } else {
        _priceFocus.requestFocus();
      }
    });

    for (final c in [_nameCon, _priceCon]) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    _nameCon.dispose();
    _priceCon.dispose();
    _stockCon.dispose();
    _nameFocus.dispose();
    _priceFocus.dispose();
    super.dispose();
  }

  void _confirm() {
    if (!_isValid) return;
    final price = double.tryParse(_priceCon.text.replaceAll(',', '.')) ?? 0;
    final stock = int.tryParse(_stockCon.text) ?? 1;
    widget.onConfirm(_nameCon.text.trim(), price, stock);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _isFromCatalog
              ? AppColors.emerald.withValues(alpha: 0.5)
              : AppColors.skyBlue.withValues(alpha: 0.5),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header con EAN y badge de fuente
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
            decoration: BoxDecoration(
              color: (_isFromCatalog ? AppColors.emerald : AppColors.skyBlue)
                  .withValues(alpha: 0.08),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(15)),
            ),
            child: Row(
              children: [
                Icon(
                  _isFromCatalog
                      ? Icons.verified_rounded
                      : Icons.qr_code_rounded,
                  size: 16,
                  color:
                      _isFromCatalog ? AppColors.emerald : AppColors.skyBlue,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _isFromCatalog
                            ? 'Producto encontrado en catálogo'
                            : 'Código no registrado',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: _isFromCatalog
                              ? AppColors.emerald
                              : AppColors.skyBlue,
                          letterSpacing: 0.3,
                        ),
                      ),
                      Text(
                        widget.barcode,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.onSurfaceMuted,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                ),
                // Botón cerrar
                GestureDetector(
                  onTap: widget.onDismiss,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceVariant,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Icon(
                      Icons.close_rounded,
                      size: 16,
                      color: AppColors.onSurfaceMuted,
                    ),
                  ),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Nombre del producto
                TextFormField(
                  controller: _nameCon,
                  focusNode: _nameFocus,
                  textCapitalization: TextCapitalization.sentences,
                  textInputAction: TextInputAction.next,
                  onFieldSubmitted: (_) => _priceFocus.requestFocus(),
                  decoration: InputDecoration(
                    labelText: 'Nombre del producto *',
                    filled: true,
                    fillColor: AppColors.surfaceVariant,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
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
                      borderSide: const BorderSide(
                          color: AppColors.borderFocus, width: 1.5),
                    ),
                    // Badge de categoría sugerida
                    suffixIcon: widget.suggestedCategory != null
                        ? Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: Chip(
                              label: Text(
                                widget.suggestedCategory!,
                                style: const TextStyle(fontSize: 11),
                              ),
                              padding: EdgeInsets.zero,
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                              backgroundColor: AppColors.surfaceVariant,
                              side: const BorderSide(color: AppColors.border),
                            ),
                          )
                        : null,
                  ),
                ),
                const SizedBox(height: 10),

                // Precio y Stock en fila
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Precio
                    Expanded(
                      flex: 3,
                      child: TextFormField(
                        controller: _priceCon,
                        focusNode: _priceFocus,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        textInputAction: TextInputAction.next,
                        decoration: InputDecoration(
                          labelText: 'Precio MXN *',
                          prefixText: '\$ ',
                          prefixStyle: const TextStyle(
                            color: AppColors.emerald,
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                          filled: true,
                          fillColor: AppColors.surfaceVariant,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
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
                            borderSide: const BorderSide(
                                color: AppColors.borderFocus, width: 1.5),
                          ),
                        ),
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    // Stock
                    Expanded(
                      flex: 2,
                      child: TextFormField(
                        controller: _stockCon,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly
                        ],
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => _confirm(),
                        decoration: InputDecoration(
                          labelText: 'Stock',
                          filled: true,
                          fillColor: AppColors.surfaceVariant,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
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
                            borderSide: const BorderSide(
                                color: AppColors.borderFocus, width: 1.5),
                          ),
                        ),
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Botón confirmar
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: _isValid ? _confirm : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.emerald,
                      foregroundColor: AppColors.darkSlate,
                      disabledBackgroundColor: AppColors.surfaceVariant,
                      disabledForegroundColor: AppColors.onSurfaceMuted,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      elevation: 0,
                    ),
                    icon: const Icon(Icons.check_rounded, size: 20),
                    label: const Text(
                      'Agregar producto',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
