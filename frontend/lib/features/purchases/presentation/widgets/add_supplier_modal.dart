import 'dart:math' show max;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import '../purchases_provider.dart';

/// Abre el modal de alta de proveedor — mismo botón "+" del hub que crea
/// órdenes de compra, ahora en el tab Proveedores (ajuste de QA de Eduardo).
/// Retorna el nombre del proveedor creado si fue exitoso, null si se canceló.
Future<String?> showAddSupplierModal(BuildContext context) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const AddSupplierModal(),
  );
}

/// Modal minimalista de alta de proveedor — nombre y teléfono son los únicos
/// campos requeridos (Constitución Art. IV, Bootstrap: Rapidez y Eficiencia)
/// ya que el teléfono es central al directorio (llamada/WhatsApp, 11.2.2).
/// RFC queda como dato opcional de fondo para las cuentas por pagar.
class AddSupplierModal extends ConsumerStatefulWidget {
  const AddSupplierModal({super.key});

  @override
  ConsumerState<AddSupplierModal> createState() => _AddSupplierModalState();
}

/// Código de región del teléfono — Constitución Art. I (1.2.4): México es el
/// mercado primario de Nexus, de ahí que `+52` sea el valor por defecto; se
/// deja un puñado de códigos vecinos frecuentes en la cadena de suministro
/// de un comercio mexicano en vez de un selector con los ~200 del mundo.
class _CountryCode {
  const _CountryCode(this.dialCode, this.flag, this.label);
  final String dialCode;
  final String flag;
  final String label;
}

const _kCountryCodes = [
  _CountryCode('+52', '🇲🇽', 'México'),
  _CountryCode('+1', '🇺🇸', 'EE. UU. / Canadá'),
  _CountryCode('+502', '🇬🇹', 'Guatemala'),
  _CountryCode('+501', '🇧🇿', 'Belice'),
  _CountryCode('+503', '🇸🇻', 'El Salvador'),
  _CountryCode('+58', '🇻🇪', 'Venezuela'),
];

class _AddSupplierModalState extends ConsumerState<AddSupplierModal> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _rfcController = TextEditingController();

  final _nameFocus = FocusNode();
  final _phoneFocus = FocusNode();
  final _rfcFocus = FocusNode();

  String _countryCode = _kCountryCodes.first.dialCode;

  bool _isSaving = false;
  String? _errorMessage;
  bool _isFormValid = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _nameFocus.requestFocus());
    _nameController.addListener(_validateForm);
    _phoneController.addListener(_validateForm);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _rfcController.dispose();
    _nameFocus.dispose();
    _phoneFocus.dispose();
    _rfcFocus.dispose();
    super.dispose();
  }

  void _validateForm() {
    final valid = _nameController.text.trim().length >= 2 &&
        _phoneController.text.trim().length >= 10;
    if (valid != _isFormValid) setState(() => _isFormValid = valid);
  }

  Future<void> _submit() async {
    if (!_isFormValid || _isSaving) return;
    final name = _nameController.text.trim();

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      await ref.read(suppliersProvider.notifier).createSupplier(
            name: name,
            phone: '$_countryCode${_phoneController.text.trim()}',
            rfc: _rfcController.text.trim().isEmpty
                ? null
                : _rfcController.text.trim(),
          );
      if (mounted) Navigator.of(context).pop(name);
    } catch (e) {
      setState(() {
        _isSaving = false;
        _errorMessage = 'No se pudo guardar el proveedor. Intenta de nuevo.';
      });
    }
  }

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
          _buildHandle(),
          _buildHeader(),
          const SizedBox(height: 24),
          _buildNameField(),
          const SizedBox(height: 16),
          _buildPhoneField(),
          const SizedBox(height: 16),
          _buildRfcField(),
          if (_errorMessage != null) ...[
            const SizedBox(height: 12),
            _buildErrorBanner(),
          ],
          const SizedBox(height: 24),
          _buildSubmitButton(),
        ],
      ),
    );
  }

  Widget _buildHandle() {
    return Center(
      child: Container(
        width: 40,
        height: 4,
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
            color: AppColors.border, borderRadius: BorderRadius.circular(2)),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        const Expanded(
          child: Text(
            'Nuevo proveedor',
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.onSurface),
          ),
        ),
        IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.close_rounded,
              size: 22, color: AppColors.onSurfaceMuted),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          tooltip: 'Cerrar',
        ),
      ],
    );
  }

  Widget _buildNameField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel('Nombre del proveedor', required: true),
        const SizedBox(height: 6),
        TextFormField(
          controller: _nameController,
          focusNode: _nameFocus,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          style: const TextStyle(color: AppColors.onSurface, fontSize: 15),
          decoration: const InputDecoration(
            hintText: 'Ej: Distribuidora Bimbo Norte',
            prefixIcon: Icon(Icons.local_shipping_outlined, size: 18),
          ),
          onFieldSubmitted: (_) => _phoneFocus.requestFocus(),
        ),
      ],
    );
  }

  Widget _buildPhoneField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel('Teléfono', required: true),
        const SizedBox(height: 6),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Código de región — ajuste de QA: faltaba un selector explícito
            // en vez de asumir siempre México dentro del número.
            SizedBox(
              width: 108,
              child: DropdownButtonFormField<String>(
                initialValue: _countryCode,
                isExpanded: true,
                onChanged: (code) => setState(() => _countryCode = code!),
                items: _kCountryCodes
                    .map((c) => DropdownMenuItem(
                          value: c.dialCode,
                          child: Text('${c.flag} ${c.dialCode}',
                              overflow: TextOverflow.ellipsis),
                        ))
                    .toList(),
                decoration: const InputDecoration(
                    contentPadding: EdgeInsets.symmetric(horizontal: 10)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextFormField(
                controller: _phoneController,
                focusNode: _phoneFocus,
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.next,
                style:
                    const TextStyle(color: AppColors.onSurface, fontSize: 15),
                decoration: const InputDecoration(
                  hintText: 'Ej: 5512345678',
                  prefixIcon: Icon(Icons.call_outlined, size: 18),
                ),
                onFieldSubmitted: (_) => _rfcFocus.requestFocus(),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        const Text(
          'Se usa para el botón de llamada/WhatsApp del directorio.',
          style: TextStyle(fontSize: 11, color: AppColors.onSurfaceMuted),
        ),
      ],
    );
  }

  Widget _buildRfcField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel('RFC'),
        const SizedBox(height: 6),
        TextFormField(
          controller: _rfcController,
          focusNode: _rfcFocus,
          textCapitalization: TextCapitalization.characters,
          textInputAction: TextInputAction.done,
          style: const TextStyle(color: AppColors.onSurface, fontSize: 15),
          decoration: const InputDecoration(
            hintText: 'Opcional',
            prefixIcon: Icon(Icons.badge_outlined, size: 18),
          ),
          onFieldSubmitted: (_) => _submit(),
        ),
      ],
    );
  }

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
            child: Text(_errorMessage!,
                style: const TextStyle(fontSize: 13, color: AppColors.error)),
          ),
        ],
      ),
    );
  }

  Widget _buildSubmitButton() {
    return ElevatedButton(
      onPressed: _isFormValid && !_isSaving ? _submit : null,
      child: _isSaving
          ? const SizedBox(
              height: 22,
              width: 22,
              child: CircularProgressIndicator(
                  strokeWidth: 2.5, color: AppColors.darkSlate),
            )
          : const Text('Agregar proveedor'),
    );
  }

  Widget _fieldLabel(String text, {bool required = false}) {
    return Row(
      children: [
        Text(text,
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppColors.onSurface)),
        if (required)
          const Text(' *',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.emerald)),
      ],
    );
  }
}
