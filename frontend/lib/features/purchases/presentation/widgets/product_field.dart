import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../inventory/domain/product.dart';
import '../../../inventory/presentation/inventory_provider.dart';
import '../../data/product_name_matcher.dart';

/// Campo de producto de Compras — el único lugar donde un renglón deja de ser
/// texto y pasa a ser un producto real del catálogo (o una promesa visible de
/// crear uno).
///
/// Se reutiliza en las tres superficies que capturan lo mismo: el formulario
/// de captura (`PurchaseCreateScreen`), el renglón de la factura escaneada
/// (`OcrReviewScreen`) y la fila en edición de la tabla de resumen
/// (`PurchaseItemsSummaryTable`).
///
/// Regla que gobierna el diseño (decisión de Eduardo, sesión de QA Sep 19):
/// **"Se creará" es el estado por defecto; resolver es un acto.** El sistema
/// ofrece coincidencias, el dedo decide — nunca se engancha un producto
/// parecido por cuenta propia, porque un match equivocado corrompe costo y
/// margen en silencio mientras que un duplicado se ve y se corrige.
///
/// Dos presentaciones de la misma búsqueda, según quién escribió el texto:
///   · **Con foco** → panel de resultados: el usuario está buscando.
///   · **Sin foco** → chips "¿Es este?": el texto lo puso el OCR o el dictado
///     y el sistema *ofrece* candidatos sin abrir ocho paneles a la vez en una
///     pantalla llena de renglones.
class ProductField extends ConsumerStatefulWidget {
  const ProductField({
    super.key,
    required this.controller,
    required this.resolved,
    required this.onResolvedChanged,
    this.fieldKey,
    this.label,
    this.hintText = 'Busca o escribe el producto',
    this.autofocus = false,
    this.dense = false,
    this.onChanged,
  });

  final TextEditingController controller;

  /// Producto del catálogo al que está amarrado este renglón, o `null` si se
  /// va a crear uno nuevo con el texto tal cual.
  final Product? resolved;

  final ValueChanged<Product?> onResolvedChanged;

  /// Key del `TextFormField` interno — cada superficie identifica el suyo.
  final Key? fieldKey;

  final String? label;
  final String hintText;
  final bool autofocus;

  /// Variante compacta para la fila de la tabla de resumen.
  final bool dense;

  /// Se notifica en cada tecla, después de resolver el estado interno.
  final VoidCallback? onChanged;

  @override
  ConsumerState<ProductField> createState() => _ProductFieldState();
}

class _ProductFieldState extends ConsumerState<ProductField> {
  static const _matcher = ProductNameMatcher();

  final _focusNode = FocusNode();
  bool _hasFocus = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(
      () => setState(() => _hasFocus = _focusNode.hasFocus),
    );
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  String get _query => widget.controller.text.trim();

  void _handleTextChanged() {
    // Editar el nombre a mano desvincula el producto: nunca se manda un
    // `productId` real con un nombre que ya no es el suyo.
    if (widget.resolved != null &&
        widget.controller.text != widget.resolved!.name) {
      widget.onResolvedChanged(null);
    }
    setState(() {});
    widget.onChanged?.call();
  }

  void _resolve(Product product) {
    widget.controller.text = product.name; // Nombre canónico del catálogo.
    widget.onResolvedChanged(product);
    _focusNode.unfocus();
    widget.onChanged?.call();
  }

  void _unlink() {
    widget.onResolvedChanged(null);
    _focusNode.requestFocus();
    widget.onChanged?.call();
  }

  /// Coincidencias del catálogo para [query]: primero las que contienen el
  /// texto (lo que el usuario espera al teclear), y si son pocas se completan
  /// con parecidos del `ProductNameMatcher` — ahí es donde caen las lecturas
  /// del OCR ("Leche Lala 1lt" no contiene "Leche Lala Entera 1L", pero se le
  /// parece).
  List<Product> _candidatesFor(String query, List<Product> catalog) {
    if (query.isEmpty) return const [];
    final q = query.toLowerCase();

    final contains = catalog
        .where((p) =>
            p.name.toLowerCase().contains(q) ||
            p.sku.toLowerCase().contains(q) ||
            (p.barcode?.contains(q) ?? false))
        .take(5)
        .toList();
    if (contains.length >= 3) return contains;

    final similar = _matcher
        .match(query, catalog)
        .candidates
        .where((p) => !contains.any((c) => c.id == p.id));

    return [...contains, ...similar].take(5).toList();
  }

  @override
  Widget build(BuildContext context) {
    final resolved = widget.resolved;
    final catalog = ref.watch(inventoryProvider).products;
    final candidates = resolved == null
        ? _candidatesFor(_query, catalog)
        : const <Product>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          key: widget.fieldKey,
          controller: widget.controller,
          focusNode: _focusNode,
          autofocus: widget.autofocus,
          onChanged: (_) => _handleTextChanged(),
          textCapitalization: TextCapitalization.sentences,
          style: TextStyle(
            color: AppColors.onSurface,
            fontSize: widget.dense ? 14 : 15,
            fontWeight: FontWeight.w500,
          ),
          decoration: InputDecoration(
            labelText: widget.label,
            hintText: widget.hintText,
            isDense: widget.dense,
            prefixIcon: Icon(
              resolved != null
                  ? Icons.inventory_2_rounded
                  : Icons.search_rounded,
              size: 18,
              color: resolved != null
                  ? AppColors.emerald
                  : AppColors.onSurfaceMuted,
            ),
            prefixIconConstraints:
                const BoxConstraints(minWidth: 40, minHeight: 40),
            suffixIcon: resolved == null
                ? null
                : IconButton(
                    key: const Key('productFieldUnlinkButton'),
                    tooltip: 'Buscar otro producto',
                    onPressed: _unlink,
                    icon: const Icon(Icons.close_rounded, size: 18),
                    color: AppColors.onSurfaceMuted,
                  ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: _buildStatus(resolved, candidates),
        ),
      ],
    );
  }

  Widget _buildStatus(Product? resolved, List<Product> candidates) {
    if (resolved != null) {
      return const Padding(
        padding: EdgeInsets.only(top: 6),
        child: _StatusLine(
          key: Key('productFieldResolved'),
          icon: Icons.check_circle_rounded,
          color: AppColors.emerald,
          label: 'En tu inventario',
        ),
      );
    }

    // Buscando: el usuario está dentro del campo, así que el panel de
    // resultados va en flujo (no flotando) — dentro de la tabla de resumen un
    // overlay quedaría recortado por el scroll interno de la tabla.
    if (_hasFocus && _query.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: _ResultsPanel(
          results: candidates,
          query: _query,
          onPick: _resolve,
        ),
      );
    }

    if (_query.isEmpty) return const SizedBox.shrink();

    // Sin foco y sin resolver: se ofrece, no se decide.
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _StatusLine(
            key: Key('productFieldWillCreate'),
            icon: Icons.add_circle_rounded,
            color: AppColors.skyBlue,
            label: 'Se creará',
          ),
          if (candidates.isNotEmpty) ...[
            const SizedBox(height: 6),
            _SuggestionChips(candidates: candidates, onPick: _resolve),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Estado del renglón — una línea, no una tarjeta: la fila ya es el contenedor
// ---------------------------------------------------------------------------

class _StatusLine extends StatelessWidget {
  const _StatusLine({
    super.key,
    required this.icon,
    required this.color,
    required this.label,
  });

  final IconData icon;
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Resultados de búsqueda — mientras el campo tiene el foco
// ---------------------------------------------------------------------------

class _ResultsPanel extends StatelessWidget {
  const _ResultsPanel({
    required this.results,
    required this.query,
    required this.onPick,
  });

  final List<Product> results;
  final String query;
  final ValueChanged<Product> onPick;

  @override
  Widget build(BuildContext context) {
    if (results.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            const Icon(Icons.add_circle_rounded,
                size: 16, color: AppColors.skyBlue),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '"$query" no está en tu inventario. Se creará al guardar la orden.',
                style: const TextStyle(
                  fontSize: 12,
                  height: 1.35,
                  color: AppColors.onSurfaceMuted,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      constraints: const BoxConstraints(maxHeight: 208),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: ListView.separated(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        itemCount: results.length,
        separatorBuilder: (_, __) =>
            const Divider(height: 1, color: AppColors.border),
        itemBuilder: (_, i) => _ResultRow(
          key: Key('productFieldResult_${results[i].id}'),
          product: results[i],
          onTap: () => onPick(results[i]),
        ),
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({super.key, required this.product, required this.onTap});

  final Product product;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        // 48 dp de alto mínimo — el dedo del tendero, no el cursor.
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    product.name,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: AppColors.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 1),
                  Text(
                    product.sku,
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.onSurfaceMuted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text(
              '${product.availableStock} en stock',
              style: const TextStyle(
                  fontSize: 11, color: AppColors.onSurfaceMuted),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sugerencias — se ofrecen, nunca se aplican solas
// ---------------------------------------------------------------------------

class _SuggestionChips extends StatelessWidget {
  const _SuggestionChips({required this.candidates, required this.onPick});

  final List<Product> candidates;
  final ValueChanged<Product> onPick;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        const Text(
          '¿Es este?',
          style: TextStyle(fontSize: 11, color: AppColors.onSurfaceMuted),
        ),
        for (final candidate in candidates.take(3))
          Material(
            color: AppColors.surfaceVariant,
            borderRadius: BorderRadius.circular(8),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              key: Key('productFieldSuggestion_${candidate.id}'),
              onTap: () => onPick(candidate),
              child: Container(
                constraints: const BoxConstraints(minHeight: 34),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        candidate.name,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.skyBlue,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
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
}
