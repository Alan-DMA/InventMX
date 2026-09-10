import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import '../domain/product.dart';
import 'inventory_provider.dart';
import 'widgets/adjust_stock_modal.dart';

/// Pantalla de edición completa de producto — Tarea 3.2.4
///
/// Campos editables (alineados con PATCH /inventory/products/{id}):
///   nombre, precio venta MXN, costo MXN, categoría, código de barras,
///   stock mínimo de alerta, imagen (URL / placeholder cámara), activo/inactivo.
///
/// Campos informativos (no editables):
///   SKU (autogenerado por backend), stock actual (se modifica via AdjustStock).
///
/// Trazabilidad: Constitución Art. I (1.2.4 MXN, 1.2.8 Rapidez)
///              Doc. Maestro RF-02, SR-08 · HU-05 / CU-06
class EditProductScreen extends ConsumerStatefulWidget {
  const EditProductScreen({super.key, required this.product});

  final Product product;

  @override
  ConsumerState<EditProductScreen> createState() => _EditProductScreenState();
}

class _EditProductScreenState extends ConsumerState<EditProductScreen> {
  // ── Controllers ─────────────────────────────────────────────────────────
  late final TextEditingController _nameCon;
  late final TextEditingController _priceCon;
  late final TextEditingController _costCon;
  late final TextEditingController _barcodeCon;
  late final TextEditingController _minStockCon;
  late final TextEditingController _categoryCon;
  late final TextEditingController _imageUrlCon;

  // ── Focus nodes ──────────────────────────────────────────────────────────
  late final FocusNode _nameFocus;
  late final FocusNode _priceFocus;
  late final FocusNode _costFocus;
  late final FocusNode _barcodeFocus;
  late final FocusNode _minStockFocus;
  late final FocusNode _categoryFocus;

  // ── Estado local ─────────────────────────────────────────────────────────
  bool _isActive = true;
  bool _isSaving = false;
  String? _errorMessage;
  String? _selectedCategory; // valor seleccionado en el dropdown
  bool _isAddingCategory =
      false; // true → muestra textfield libre en lugar del dropdown

  // ── Validación ───────────────────────────────────────────────────────────
  bool get _isFormValid {
    final name = _nameCon.text.trim();
    final price = double.tryParse(_priceCon.text.replaceAll(',', '.')) ?? 0;
    return name.length >= 2 && price > 0;
  }

  @override
  void initState() {
    super.initState();
    final p = widget.product;

    _nameCon = TextEditingController(text: p.name);
    _priceCon = TextEditingController(text: p.priceMxn.toStringAsFixed(2));
    _costCon = TextEditingController(
      text: p.costMxn > 0 ? p.costMxn.toStringAsFixed(2) : '',
    );
    _barcodeCon = TextEditingController(text: p.barcode ?? '');
    _minStockCon = TextEditingController(
      text: p.minStockAlert != null ? p.minStockAlert.toString() : '',
    );
    _categoryCon = TextEditingController(text: p.category);
    _imageUrlCon = TextEditingController(text: p.imageUrl ?? '');

    _nameFocus = FocusNode();
    _priceFocus = FocusNode();
    _costFocus = FocusNode();
    _barcodeFocus = FocusNode();
    _minStockFocus = FocusNode();
    _categoryFocus = FocusNode();

    _isActive = p.isActive;
    _selectedCategory = p.category;

    // Refresca el botón Guardar al cambiar cualquier campo
    for (final c in [_nameCon, _priceCon]) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    for (final c in [
      _nameCon,
      _priceCon,
      _costCon,
      _barcodeCon,
      _minStockCon,
      _categoryCon,
      _imageUrlCon,
    ]) {
      c.dispose();
    }
    for (final f in [
      _nameFocus,
      _priceFocus,
      _costFocus,
      _barcodeFocus,
      _minStockFocus,
      _categoryFocus,
    ]) {
      f.dispose();
    }
    super.dispose();
  }

  // ── Guardar ──────────────────────────────────────────────────────────────

  Future<void> _save() async {
    if (!_isFormValid || _isSaving) return;
    FocusScope.of(context).unfocus();

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      final price = double.tryParse(_priceCon.text.replaceAll(',', '.')) ?? 0;
      final costText = _costCon.text.replaceAll(',', '.');
      final cost = costText.isEmpty ? 0.0 : (double.tryParse(costText) ?? 0);
      final minStock =
          _minStockCon.text.isEmpty ? null : int.tryParse(_minStockCon.text);
      final imageUrl =
          _imageUrlCon.text.trim().isEmpty ? null : _imageUrlCon.text.trim();

      await ref.read(inventoryProvider.notifier).updateProduct(
            productId: widget.product.id,
            name: _nameCon.text.trim(),
            priceMxn: price,
            costMxn: cost,
            category:
                (_selectedCategory == null || _selectedCategory!.trim().isEmpty)
                    ? 'General'
                    : _selectedCategory!.trim(),
            barcode: _barcodeCon.text.trim().isEmpty
                ? null
                : _barcodeCon.text.trim(),
            minStockAlert: minStock,
            imageUrl: imageUrl,
            isActive: _isActive,
          );

      // Invalida el detalle para que se recargue con datos frescos
      ref.invalidate(productDetailProvider(widget.product.id));

      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text('✓ ${_nameCon.text.trim()} actualizado correctamente'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      setState(() {
        _isSaving = false;
        _errorMessage =
            'No se pudo guardar. Verifica tu conexión e intenta de nuevo.';
      });
    }
  }

  // ── Margen estimado ──────────────────────────────────────────────────────

  String? get _marginLabel {
    final price = double.tryParse(_priceCon.text.replaceAll(',', '.')) ?? 0;
    final cost = double.tryParse(_costCon.text.replaceAll(',', '.')) ?? 0;
    if (price <= 0 || cost <= 0) return null;
    final margin = ((price - cost) / price) * 100;
    final profit = price - cost;
    return '+\$${profit.toStringAsFixed(2)} (${margin.toStringAsFixed(0)}%)';
  }

  Color get _marginColor {
    final price = double.tryParse(_priceCon.text.replaceAll(',', '.')) ?? 0;
    final cost = double.tryParse(_costCon.text.replaceAll(',', '.')) ?? 0;
    if (price <= 0 || cost <= 0) return AppColors.onSurfaceMuted;
    final margin = ((price - cost) / price) * 100;
    if (margin >= 30) return AppColors.emerald;
    if (margin >= 10) return AppColors.warning;
    return AppColors.error;
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(availableCategoriesProvider);

    return Scaffold(
      backgroundColor: AppColors.darkSlate,
      appBar: AppBar(
        backgroundColor: AppColors.darkSlate,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              size: 20, color: AppColors.onSurface),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Editar producto',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppColors.onSurface,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: _isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.emerald,
                    ),
                  )
                : TextButton(
                    onPressed: _isFormValid ? _save : null,
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.emerald,
                      disabledForegroundColor:
                          AppColors.onSurfaceMuted.withValues(alpha: 0.4),
                      textStyle: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                    child: const Text('Guardar'),
                  ),
          ),
        ],
      ),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Banner foto ─────────────────────────────────────────
              _PhotoBanner(
                imageUrl: _imageUrlCon.text.isEmpty ? null : _imageUrlCon.text,
                onChangeTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                          'Captura de cámara/galería — disponible próximamente'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
              ),

              // ── Error banner ────────────────────────────────────────
              if (_errorMessage != null) _ErrorBanner(message: _errorMessage!),

              // ── Sección: Identificación ─────────────────────────────
              const _SectionHeader(label: 'IDENTIFICACIÓN'),
              _FormPad(
                child: Column(
                  children: [
                    // Nombre
                    TextFormField(
                      controller: _nameCon,
                      focusNode: _nameFocus,
                      textCapitalization: TextCapitalization.sentences,
                      textInputAction: TextInputAction.next,
                      onFieldSubmitted: (_) =>
                          FocusScope.of(context).requestFocus(_priceFocus),
                      decoration: const InputDecoration(
                        labelText: 'Nombre *',
                      ),
                    ),
                    const SizedBox(height: 12),

                    // SKU (no editable)
                    TextFormField(
                      initialValue: widget.product.sku,
                      enabled: false,
                      decoration: InputDecoration(
                        labelText: 'SKU (no editable)',
                        suffixIcon: Padding(
                          padding: const EdgeInsets.only(right: 12),
                          child: Icon(
                            Icons.lock_outline_rounded,
                            size: 16,
                            color:
                                AppColors.onSurfaceMuted.withValues(alpha: 0.5),
                          ),
                        ),
                        disabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: AppColors.border.withValues(alpha: 0.4),
                          ),
                        ),
                        fillColor:
                            AppColors.surfaceVariant.withValues(alpha: 0.4),
                      ),
                      style: TextStyle(
                        color: AppColors.onSurfaceMuted.withValues(alpha: 0.5),
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Código de barras
                    TextFormField(
                      controller: _barcodeCon,
                      focusNode: _barcodeFocus,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        labelText: 'Código de barras',
                        suffixIcon: IconButton(
                          icon: Icon(
                            Icons.qr_code_scanner_rounded,
                            size: 20,
                            color:
                                AppColors.onSurfaceMuted.withValues(alpha: 0.6),
                          ),
                          tooltip: 'Escanear código',
                          onPressed: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Escáner de código de barras — disponible próximamente',
                                ),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // ── Sección: Precios ────────────────────────────────────
              const _SectionHeader(label: 'PRECIOS'),
              _FormPad(
                child: Column(
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Precio venta
                        Expanded(
                          child: TextFormField(
                            controller: _priceCon,
                            focusNode: _priceFocus,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            textInputAction: TextInputAction.next,
                            onFieldSubmitted: (_) =>
                                FocusScope.of(context).requestFocus(_costFocus),
                            onChanged: (_) => setState(() {}),
                            decoration: const InputDecoration(
                              labelText: 'Precio venta (MXN) *',
                              prefixText: '\$ ',
                              prefixStyle: TextStyle(
                                color: AppColors.emerald,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        // Costo
                        Expanded(
                          child: TextFormField(
                            controller: _costCon,
                            focusNode: _costFocus,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            textInputAction: TextInputAction.next,
                            onChanged: (_) => setState(() {}),
                            decoration: InputDecoration(
                              labelText: 'Costo (MXN)',
                              hintText: 'Opcional',
                              prefixText: '\$ ',
                              prefixStyle: TextStyle(
                                color: AppColors.onSurfaceMuted
                                    .withValues(alpha: 0.8),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),

                    // Margen estimado — reactivo, ancho completo
                    if (_marginLabel != null) ...[
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: _marginColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: _marginColor.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Text(
                          'Margen estimado: $_marginLabel',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: _marginColor,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              // ── Sección: Inventario ─────────────────────────────────
              const _SectionHeader(label: 'INVENTARIO'),
              _FormPad(
                child: Column(
                  children: [
                    // Stock actual (informativo)
                    _StockInfoRow(
                      product: widget.product,
                      onAdjusted: () => setState(() {}),
                    ),
                    const SizedBox(height: 12),

                    // Stock mínimo de alerta
                    TextFormField(
                      controller: _minStockCon,
                      focusNode: _minStockFocus,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                      textInputAction: TextInputAction.next,
                      onFieldSubmitted: (_) =>
                          FocusScope.of(context).requestFocus(_categoryFocus),
                      decoration: const InputDecoration(
                        labelText: 'Stock mínimo de alerta',
                        hintText: 'Ej: 5',
                        helperText: 'Alerta cuando llegue a este número',
                        helperStyle: TextStyle(
                          fontSize: 11,
                          color: AppColors.onSurfaceMuted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // ── Sección: Clasificación ──────────────────────────────
              const _SectionHeader(label: 'CLASIFICACIÓN'),
              _FormPad(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Modo "agregar nueva": textfield libre reemplaza al dropdown
                    if (_isAddingCategory)
                      TextFormField(
                        controller: _categoryCon,
                        focusNode: _categoryFocus,
                        textCapitalization: TextCapitalization.words,
                        textInputAction: TextInputAction.done,
                        autofocus: true,
                        onChanged: (v) =>
                            setState(() => _selectedCategory = v.trim()),
                        decoration: InputDecoration(
                          labelText: 'Nueva categoría',
                          hintText: 'Ej: Congelados',
                          prefixIcon: const Icon(
                            Icons.add_rounded,
                            size: 18,
                            color: AppColors.emerald,
                          ),
                          suffixIcon: IconButton(
                            icon: const Icon(Icons.close_rounded,
                                size: 18, color: AppColors.onSurfaceMuted),
                            tooltip: 'Cancelar',
                            onPressed: () => setState(() {
                              _isAddingCategory = false;
                              // Restaura la última categoría seleccionada
                              // o la primera de la lista
                              _selectedCategory =
                                  categories.contains(widget.product.category)
                                      ? widget.product.category
                                      : categories.first;
                              _categoryCon.clear();
                            }),
                          ),
                        ),
                      )
                    // Sin categorías disponibles: textfield libre directo
                    else if (categories.isEmpty)
                      TextFormField(
                        controller: _categoryCon,
                        focusNode: _categoryFocus,
                        textCapitalization: TextCapitalization.words,
                        textInputAction: TextInputAction.done,
                        onChanged: (v) =>
                            setState(() => _selectedCategory = v.trim()),
                        decoration: const InputDecoration(
                          labelText: 'Categoría',
                          hintText: 'Ej: Bebidas',
                        ),
                      )
                    // Modo normal: dropdown con categorías existentes
                    else
                      DropdownButtonFormField<String>(
                        initialValue: categories.contains(_selectedCategory)
                            ? _selectedCategory
                            : null,
                        decoration: const InputDecoration(
                          labelText: 'Categoría',
                        ),
                        dropdownColor: AppColors.surface,
                        iconEnabledColor: AppColors.onSurfaceMuted,
                        style: const TextStyle(
                          color: AppColors.onSurface,
                          fontSize: 14,
                        ),
                        hint: const Text(
                          'Selecciona una categoría',
                          style: TextStyle(
                            color: AppColors.onSurfaceMuted,
                            fontSize: 14,
                          ),
                        ),
                        items: [
                          ...categories.map(
                            (cat) => DropdownMenuItem(
                              value: cat,
                              child: Text(cat),
                            ),
                          ),
                          const DropdownMenuItem(
                            value: '__nueva__',
                            child: Row(
                              children: [
                                Icon(Icons.add_rounded,
                                    size: 16, color: AppColors.emerald),
                                SizedBox(width: 6),
                                Text(
                                  'Nueva categoría...',
                                  style: TextStyle(color: AppColors.emerald),
                                ),
                              ],
                            ),
                          ),
                        ],
                        onChanged: (val) {
                          if (val == '__nueva__') {
                            // Cambia al modo textfield en el siguiente frame
                            // para que Flutter monte el widget antes del foco
                            setState(() {
                              _isAddingCategory = true;
                              _selectedCategory = null;
                              _categoryCon.clear();
                            });
                          } else if (val != null) {
                            setState(() => _selectedCategory = val);
                          }
                        },
                      ),
                  ],
                ),
              ),

              // ── Sección: Estado ─────────────────────────────────────
              const _SectionHeader(label: 'ESTADO'),
              _FormPad(
                child: Row(
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Producto activo',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: AppColors.onSurface,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Visible en POS y búsqueda',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.onSurfaceMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: _isActive,
                      onChanged: (v) => setState(() => _isActive = v),
                      activeThumbColor: AppColors.emerald,
                      activeTrackColor:
                          AppColors.emerald.withValues(alpha: 0.3),
                      inactiveThumbColor: AppColors.onSurfaceMuted,
                      inactiveTrackColor: AppColors.surfaceVariant,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Banner de foto
// ---------------------------------------------------------------------------

class _PhotoBanner extends StatelessWidget {
  const _PhotoBanner({
    required this.imageUrl,
    required this.onChangeTap,
  });

  final String? imageUrl;
  final VoidCallback onChangeTap;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Imagen o placeholder
        Container(
          height: 180,
          width: double.infinity,
          color: AppColors.surfaceVariant,
          child: imageUrl != null && imageUrl!.isNotEmpty
              ? Image.network(
                  imageUrl!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => _placeholder(),
                )
              : _placeholder(),
        ),

        // Botón "Cambiar foto" sobre el banner
        Positioned(
          bottom: 12,
          right: 12,
          child: GestureDetector(
            onTap: onChangeTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: AppColors.darkSlate.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: AppColors.border,
                ),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.photo_camera_outlined,
                    size: 14,
                    color: AppColors.onSurface,
                  ),
                  SizedBox(width: 6),
                  Text(
                    'Cambiar foto',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: AppColors.onSurface,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _placeholder() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.photo_camera_outlined,
          size: 36,
          color: AppColors.onSurfaceMuted.withValues(alpha: 0.35),
        ),
        const SizedBox(height: 8),
        Text(
          'VISTA PREVIA DEL PRODUCTO',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: AppColors.onSurfaceMuted.withValues(alpha: 0.4),
            letterSpacing: 1.0,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Tarjeta informativa de stock actual
// ---------------------------------------------------------------------------

class _StockInfoRow extends StatelessWidget {
  const _StockInfoRow({
    required this.product,
    required this.onAdjusted,
  });

  final Product product;
  final VoidCallback onAdjusted;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Label + número apilados verticalmente
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Stock actual',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.onSurfaceMuted,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      '${product.availableStock}',
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        color: AppColors.onSurface,
                        height: 1,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Text(
                      'pzs',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.onSurfaceMuted,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Botón Ajustar → abre AdjustStockModal
          GestureDetector(
            onTap: () =>
                showAdjustStockModal(context, product).then((adjusted) {
              if (adjusted) onAdjusted();
            }),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: AppColors.darkSlate,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.border),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.tune_rounded,
                    size: 14,
                    color: AppColors.skyBlue,
                  ),
                  SizedBox(width: 6),
                  Text(
                    'Ajustar',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: AppColors.skyBlue,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Helpers de layout
// ---------------------------------------------------------------------------

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 1,
              color: AppColors.border,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: AppColors.onSurfaceMuted.withValues(alpha: 0.7),
                letterSpacing: 1.0,
              ),
            ),
          ),
          Expanded(
            child: Container(
              height: 1,
              color: AppColors.border,
            ),
          ),
        ],
      ),
    );
  }
}

/// Wrapper con padding horizontal uniforme para cada grupo de campos.
class _FormPad extends StatelessWidget {
  const _FormPad({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: child,
    );
  }
}

// ---------------------------------------------------------------------------
// Banner de error
// ---------------------------------------------------------------------------

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.error_outline_rounded,
            size: 18,
            color: AppColors.error,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
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
}
