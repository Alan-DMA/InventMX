import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../../core/widgets/barcode_scan_sheet.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus_app/core/widgets/product_image_widget.dart';
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
  bool _isUploadingImage = false;
  String? _errorMessage;
  String? _selectedCategory; // valor seleccionado en el dropdown
  String? _selectedSupplierId; // valor seleccionado para proveedor
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
    _selectedSupplierId = p.supplierId;

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

  // ── Subida de imágenes ───────────────────────────────────────────────────

  Future<void> _pickAndUploadImage() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
        withData: true,
      );

      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      final bytes = file.bytes;
      if (bytes == null || bytes.isEmpty) return;

      if (bytes.lengthInBytes > 5 * 1024 * 1024) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('La imagen seleccionada supera el límite de 5 MB'),
              backgroundColor: AppColors.error,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }

      setState(() {
        _isUploadingImage = true;
      });

      String finalImageUrl;
      try {
        // 1. Intentar subir al servidor para obtener URL estática ligera (/uploads/images/...)
        final uploadedUrl = await ref.read(inventoryProvider.notifier).uploadImage(
              fileBytes: bytes,
              fileName: file.name,
            );
        finalImageUrl = uploadedUrl;
      } catch (_) {
        // 2. Fallback a binario Base64 Data URI si la carga falla o sin conexión
        final ext = (file.extension ?? 'jpg').toLowerCase();
        final mimeType = (ext == 'png')
            ? 'image/png'
            : (ext == 'webp' ? 'image/webp' : 'image/jpeg');
        final base64String = base64Encode(bytes);
        finalImageUrl = 'data:$mimeType;base64,$base64String';
      }

      setState(() {
        _imageUrlCon.text = finalImageUrl;
        _isUploadingImage = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✓ Imagen cargada correctamente'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      setState(() {
        _isUploadingImage = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al cargar imagen: $e'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _showImageOptionsModal() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.upload_file_rounded,
                      color: AppColors.emerald),
                  title: const Text('Subir imagen desde archivo'),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _pickAndUploadImage();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.link_rounded,
                      color: AppColors.onSurface),
                  title: const Text('Ingresar URL de imagen'),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _showImageUrlDialog();
                  },
                ),
                if (_imageUrlCon.text.isNotEmpty)
                  ListTile(
                    leading: const Icon(Icons.delete_outline_rounded,
                        color: AppColors.error),
                    title: const Text('Quitar imagen',
                        style: TextStyle(color: AppColors.error)),
                    onTap: () {
                      Navigator.of(ctx).pop();
                      setState(() {
                        _imageUrlCon.clear();
                      });
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showImageUrlDialog() {
    final urlController = TextEditingController(text: _imageUrlCon.text);
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: AppColors.surface,
          title: const Text('URL de la Imagen'),
          content: TextField(
            controller: urlController,
            decoration: const InputDecoration(
              hintText: 'https://ejemplo.com/foto.jpg',
              labelText: 'Enlace web',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () {
                setState(() {
                  _imageUrlCon.text = urlController.text.trim();
                });
                Navigator.of(ctx).pop();
              },
              child: const Text('Aceptar'),
            ),
          ],
        );
      },
    );
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

      final categoryName = _isAddingCategory
          ? (_categoryCon.text.trim().isNotEmpty
              ? _categoryCon.text.trim()
              : 'General')
          : ((_selectedCategory == null || _selectedCategory!.trim().isEmpty)
              ? 'General'
              : _selectedCategory!.trim());

      await ref.read(inventoryProvider.notifier).updateProduct(
            productId: widget.product.id,
            name: _nameCon.text.trim(),
            priceMxn: price,
            costMxn: cost,
            category: categoryName,
            barcode: _barcodeCon.text.trim().isEmpty
                ? null
                : _barcodeCon.text.trim(),
            minStockAlert: minStock,
            imageUrl: imageUrl,
            isActive: _isActive,
            supplierId: _selectedSupplierId,
          );

      // Invalida el detalle para que se recargue con datos frescos
      ref.invalidate(productDetailProvider(widget.product.id));
      ref.invalidate(categoriesProvider);

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
        _errorMessage = 'No se pudo guardar. $e';
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
                isUploading: _isUploadingImage,
                onChangeTap: _showImageOptionsModal,
                onPickImage: _pickAndUploadImage,
                onUrlTap: _showImageUrlDialog,
                onRemoveImage: () => setState(() => _imageUrlCon.clear()),
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
                          onPressed: () async {
                            // U-03: la cámara rellena el campo; el usuario
                            // sigue pudiendo corregirlo a mano.
                            final code = await showBarcodeScanSheet(
                              context,
                              hint: 'Apunta al código de barras del producto',
                            );
                            if (code == null || !mounted) return;
                            setState(() => _barcodeCon.text = code);
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

              // ── Sección: Imagen del producto ─────────────────────────
              const _SectionHeader(label: 'IMAGEN DEL PRODUCTO'),
              _FormPad(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextFormField(
                      controller: _imageUrlCon,
                      textInputAction: TextInputAction.done,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        labelText: 'URL o ruta de imagen',
                        hintText: 'https://... o sube una imagen',
                        prefixIcon: const Icon(
                          Icons.image_outlined,
                          size: 18,
                          color: AppColors.onSurfaceMuted,
                        ),
                        suffixIcon: _imageUrlCon.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear_rounded, size: 18),
                                tooltip: 'Quitar imagen',
                                onPressed: () =>
                                    setState(() => _imageUrlCon.clear()),
                              )
                            : null,
                      ),
                    ),
                    const SizedBox(height: 10),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            AppColors.emerald.withValues(alpha: 0.15),
                        foregroundColor: AppColors.emerald,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        side: const BorderSide(color: AppColors.emerald),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: _isUploadingImage ? null : _pickAndUploadImage,
                      icon: _isUploadingImage
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.emerald,
                              ),
                            )
                          : const Icon(Icons.upload_file_rounded, size: 18),
                      label: const Text(
                        'Subir imagen desde archivo',
                        style: TextStyle(fontWeight: FontWeight.w600),
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
                    const SizedBox(height: 12),
                    // Proveedor predeterminado
                    Consumer(
                      builder: (context, ref, _) {
                        final suppliersAsync = ref.watch(suppliersProvider);
                        final suppliers = suppliersAsync.valueOrNull ?? [];

                        return DropdownButtonFormField<String?>(
                          initialValue: suppliers.any((s) => s.id == _selectedSupplierId)
                              ? _selectedSupplierId
                              : null,
                          decoration: const InputDecoration(
                            labelText: 'Proveedor predeterminado',
                            prefixIcon: Icon(
                              Icons.local_shipping_outlined,
                              size: 18,
                              color: AppColors.onSurfaceMuted,
                            ),
                          ),
                          dropdownColor: AppColors.surface,
                          iconEnabledColor: AppColors.onSurfaceMuted,
                          style: const TextStyle(
                            color: AppColors.onSurface,
                            fontSize: 14,
                          ),
                          hint: const Text(
                            'Sin proveedor asignado',
                            style: TextStyle(
                              color: AppColors.onSurfaceMuted,
                              fontSize: 14,
                            ),
                          ),
                          items: [
                            const DropdownMenuItem<String?>(
                              value: null,
                              child: Text('Sin asignar'),
                            ),
                            ...suppliers.map(
                              (s) => DropdownMenuItem<String?>(
                                value: s.id,
                                child: Text(s.name),
                              ),
                            ),
                          ],
                          onChanged: (val) {
                            setState(() => _selectedSupplierId = val);
                          },
                        );
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
    this.onPickImage,
    this.onUrlTap,
    this.onRemoveImage,
    this.isUploading = false,
  });

  final String? imageUrl;
  final VoidCallback onChangeTap;
  final VoidCallback? onPickImage;
  final VoidCallback? onUrlTap;
  final VoidCallback? onRemoveImage;
  final bool isUploading;

  @override
  Widget build(BuildContext context) {
    final hasImage = imageUrl != null && imageUrl!.trim().isNotEmpty;

    return Stack(
      children: [
        // Banner principal interactivo (todo el banner es clickable)
        Material(
          color: AppColors.surfaceVariant,
          child: InkWell(
            onTap: isUploading ? null : (onPickImage ?? onChangeTap),
            child: SizedBox(
              height: 180,
              width: double.infinity,
              child: isUploading
                  ? const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: AppColors.emerald,
                          ),
                          SizedBox(height: 10),
                          Text(
                            'Cargando imagen...',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.onSurfaceMuted,
                            ),
                          ),
                        ],
                      ),
                    )
                  : hasImage
                      ? ProductImageWidget(
                          imageUrl: imageUrl,
                          fit: BoxFit.cover,
                          width: double.infinity,
                          height: 180,
                          placeholder: _placeholder(),
                        )
                      : _placeholder(),
            ),
          ),
        ),

        // Botones de acción sobre el banner
        Positioned(
          bottom: 12,
          right: 12,
          child: Wrap(
            spacing: 8,
            children: [
              // Botón "Cambiar foto" (mantiene compatibilidad con tests y opciones)
              GestureDetector(
                onTap: isUploading ? null : onChangeTap,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: AppColors.darkSlate.withValues(alpha: 0.9),
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

              // Botón "Quitar" si ya tiene imagen
              if (hasImage && onRemoveImage != null)
                GestureDetector(
                  onTap: isUploading ? null : onRemoveImage,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                    decoration: BoxDecoration(
                      color: AppColors.darkSlate.withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: AppColors.error.withValues(alpha: 0.5),
                      ),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.delete_outline_rounded,
                          size: 14,
                          color: AppColors.error,
                        ),
                        SizedBox(width: 4),
                        Text(
                          'Quitar',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: AppColors.error,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
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
          Icons.add_photo_alternate_outlined,
          size: 40,
          color: AppColors.onSurfaceMuted.withValues(alpha: 0.5),
        ),
        const SizedBox(height: 8),
        const Text(
          'Haz clic aquí para seleccionar o subir una imagen',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.onSurface,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'El binario se almacenará directamente en la base de datos',
          style: TextStyle(
            fontSize: 11,
            color: AppColors.onSurfaceMuted.withValues(alpha: 0.6),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.emerald.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.emerald.withValues(alpha: 0.4)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.file_upload_outlined, size: 14, color: AppColors.emerald),
                  SizedBox(width: 4),
                  Text(
                    'Subir archivo',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.emerald),
                  ),
                ],
              ),
            ),
            if (onUrlTap != null) ...[
              const SizedBox(width: 8),
              GestureDetector(
                onTap: onUrlTap,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.link_rounded, size: 14, color: AppColors.onSurfaceMuted),
                      SizedBox(width: 4),
                      Text(
                        'URL web',
                        style: TextStyle(fontSize: 11, color: AppColors.onSurfaceMuted),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
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
