import 'dart:math' show max;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../../core/theme/app_colors.dart';
import '../inventory_provider.dart';

// ---------------------------------------------------------------------------
// Función de conveniencia para abrir el modal desde cualquier pantalla
// ---------------------------------------------------------------------------

/// Abre el modal de alta de producto.
/// Retorna el nombre del producto creado si fue exitoso, null si se canceló.
Future<String?> showAddProductModal(BuildContext context) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true, // Respeta el teclado
    useRootNavigator: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const AddProductModal(),
  );
}

// ---------------------------------------------------------------------------
// Widget principal
// ---------------------------------------------------------------------------

/// Modal minimalista de alta de producto — 3 Campos Vitales (SR-08).
///
/// Estado completamente local (StatefulWidget) — no requiere Riverpod.
/// La lista se actualiza llamando a addProduct() en el notifier antes de
/// cerrar el modal.
///
/// Trazabilidad: Constitución Art. VII (7.3) · Doc. Maestro SR-08 · CU-05
class AddProductModal extends ConsumerStatefulWidget {
  const AddProductModal({super.key});

  @override
  ConsumerState<AddProductModal> createState() => _AddProductModalState();
}

class _AddProductModalState extends ConsumerState<AddProductModal> {
  final _formKey = GlobalKey<FormState>();

  // Controllers
  final _nameController = TextEditingController();
  final _priceController = TextEditingController();
  final _stockController = TextEditingController(text: '0');

  // Focus nodes para secuencia de foco (CU-05.5)
  final _nameFocus = FocusNode();
  final _priceFocus = FocusNode();
  final _stockFocus = FocusNode();

  bool _isSaving = false;
  String? _errorMessage;
  bool _isFormValid = false;

  @override
  void initState() {
    super.initState();
    // Auto-foco en nombre al abrir (CA-05)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _nameFocus.requestFocus();
    });

    // Validación reactiva en cada cambio
    _nameController.addListener(_validateForm);
    _priceController.addListener(_validateForm);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    _stockController.dispose();
    _nameFocus.dispose();
    _priceFocus.dispose();
    _stockFocus.dispose();
    super.dispose();
  }

  // ── Validación ─────────────────────────────────────────────────────────

  void _validateForm() {
    final name = _nameController.text.trim();
    final price = double.tryParse(
          _priceController.text.replaceAll(',', '.'),
        ) ??
        0.0;

    final valid = name.length >= 2 && price > 0;
    if (valid != _isFormValid) {
      setState(() => _isFormValid = valid);
    }
  }

  // ── Envío ───────────────────────────────────────────────────────────────

  Future<void> _submit() async {
    if (!_isFormValid || _isSaving) return;

    final name = _nameController.text.trim();
    final priceMxn = double.parse(_priceController.text.replaceAll(',', '.'));
    final stockText = _stockController.text.trim();
    final stock = int.tryParse(stockText) ?? 0;

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      await ref.read(inventoryProvider.notifier).addProduct(
            name: name,
            priceMxn: priceMxn,
            stock: stock,
          );

      // Éxito: cierra el modal y devuelve el nombre para el SnackBar
      if (mounted) Navigator.of(context).pop(name);
    } catch (e) {
      // Error: muestra banner dentro del modal sin cerrar (CA-03)
      setState(() {
        _isSaving = false;
        _errorMessage = _parseError(e);
      });
    }
  }

  String _parseError(Object e) {
    final msg = e.toString();
    if (msg.contains('BARCODE_ALREADY_EXISTS')) {
      return 'Ya tienes un producto con ese código de barras.';
    }
    if (msg.contains('TENANT_SOFT_LOCK') || msg.contains('FORBIDDEN')) {
      return 'Tu suscripción no permite agregar más productos.';
    }
    return 'No se pudo guardar el producto. Intenta de nuevo.';
  }

  // ── Build ───────────────────────────────────────────────────────────────

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
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHandle(),
            _buildHeader(),
            const SizedBox(height: 24),
            _buildNameField(),
            const SizedBox(height: 16),
            _buildPriceField(),
            const SizedBox(height: 16),
            _buildStockField(),
            const SizedBox(height: 8),
            if (_errorMessage != null) ...[
              const SizedBox(height: 8),
              _buildErrorBanner(),
            ],
            const SizedBox(height: 24),
            _buildSubmitButton(),
          ],
        ),
      ),
    );
  }

  // ── Drag handle ─────────────────────────────────────────────────────────

  Widget _buildHandle() {
    return Center(
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
  }

  // ── Header con título y botón cerrar ────────────────────────────────────

  Widget _buildHeader() {
    return Row(
      children: [
        const Expanded(
          child: Text(
            'Nuevo producto',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.onSurface,
            ),
          ),
        ),
        IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(
            Icons.close_rounded,
            size: 22,
            color: AppColors.onSurfaceMuted,
          ),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          tooltip: 'Cerrar',
        ),
      ],
    );
  }

  // ── Campo Nombre ─────────────────────────────────────────────────────────

  Widget _buildNameField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel('Nombre del producto', required: true),
        const SizedBox(height: 6),
        TextFormField(
          controller: _nameController,
          focusNode: _nameFocus,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          style: const TextStyle(
            color: AppColors.onSurface,
            fontSize: 15,
          ),
          decoration: const InputDecoration(
            hintText: 'Ej: Coca-Cola 600ml',
            prefixIcon: Icon(Icons.inventory_2_outlined, size: 18),
          ),
          onFieldSubmitted: (_) => _priceFocus.requestFocus(),
        ),
      ],
    );
  }

  // ── Campo Precio MXN ─────────────────────────────────────────────────────

  Widget _buildPriceField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel('Precio de venta (MXN)', required: true),
        const SizedBox(height: 6),
        TextFormField(
          controller: _priceController,
          focusNode: _priceFocus,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          textInputAction: TextInputAction.next,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[\d.,]')),
          ],
          style: const TextStyle(
            color: AppColors.onSurface,
            fontSize: 15,
          ),
          decoration: const InputDecoration(
            hintText: '0.00',
            prefixText: '\$ ',
            prefixStyle: TextStyle(
              color: AppColors.emerald,
              fontWeight: FontWeight.w600,
              fontSize: 15,
            ),
            prefixIcon: Icon(Icons.attach_money_rounded, size: 18),
          ),
          onFieldSubmitted: (_) => _stockFocus.requestFocus(),
        ),
      ],
    );
  }

  // ── Campo Stock inicial ───────────────────────────────────────────────────

  Widget _buildStockField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel('Stock inicial'),
        const SizedBox(height: 6),
        TextFormField(
          controller: _stockController,
          focusNode: _stockFocus,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.done,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: const TextStyle(
            color: AppColors.onSurface,
            fontSize: 15,
          ),
          decoration: const InputDecoration(
            hintText: '0',
            prefixIcon: Icon(Icons.layers_outlined, size: 18),
            suffixText: 'pzs',
            suffixStyle: TextStyle(
              color: AppColors.onSurfaceMuted,
              fontSize: 13,
            ),
          ),
          onFieldSubmitted: (_) => _submit(),
        ),
        const SizedBox(height: 4),
        const Text(
          'Puedes ajustar el stock después desde la ficha del producto.',
          style: TextStyle(fontSize: 11, color: AppColors.onSurfaceMuted),
        ),
      ],
    );
  }

  // ── Banner de error ──────────────────────────────────────────────────────

  Widget _buildErrorBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded,
              size: 16, color: AppColors.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _errorMessage!,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.error,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Botón de envío ───────────────────────────────────────────────────────

  Widget _buildSubmitButton() {
    return ElevatedButton(
      onPressed: _isFormValid && !_isSaving ? _submit : null,
      child: _isSaving
          ? const SizedBox(
              height: 22,
              width: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: AppColors.darkSlate,
              ),
            )
          : const Text('Agregar producto'),
    );
  }

  // ── Helper etiqueta de campo ─────────────────────────────────────────────

  Widget _fieldLabel(String text, {bool required = false}) {
    return Row(
      children: [
        Text(
          text,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: AppColors.onSurface,
          ),
        ),
        if (required)
          const Text(
            ' *',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.emerald,
            ),
          ),
      ],
    );
  }
}
