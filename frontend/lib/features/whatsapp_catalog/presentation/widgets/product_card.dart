import 'package:flutter/material.dart';

import '../../domain/public_catalog.dart';
import '../catalog_theme.dart';

/// Tarjeta de producto de la vitrina — Tarea 13.2.1.
///
/// Foto (o placeholder por categoría, D4) arriba en 1:1, nombre en dos
/// líneas, precio como protagonista y el "+" en la esquina. Al agregar, el
/// "+" se convierte en un stepper **en el mismo lugar**: el pulgar no tiene
/// que buscar el control a otro lado. Agotado se escribe, no solo se atenúa.
class ProductCard extends StatelessWidget {
  const ProductCard({
    super.key,
    required this.product,
    required this.quantity,
    required this.onAdd,
    required this.onRemove,
  });

  final PublicCatalogProduct product;
  final int quantity;
  final VoidCallback onAdd;
  final VoidCallback onRemove;

  /// Alto del bloque bajo la foto: padding 10 + nombre 38 + 8 + control 40
  /// + padding 10 + borde 2. El grid lo usa para calcular la proporción.
  static const double textBlockHeight = 110;

  @override
  Widget build(BuildContext context) {
    final available = product.inStock;
    final inOrder = quantity > 0;

    return Semantics(
      container: true,
      label: '${product.name}, ${mxn(product.priceMxn)}'
          '${available ? '' : ', agotado'}'
          '${inOrder ? ', $quantity en tu pedido' : ''}',
      child: Container(
        key: ValueKey('product-${product.id}'),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: CatalogColors.ground,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: inOrder ? CatalogColors.accent : CatalogColors.line,
            width: inOrder ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                AspectRatio(
                  aspectRatio: 1,
                  child: Opacity(
                    opacity: available ? 1 : 0.45,
                    child: _ProductImage(product: product),
                  ),
                ),
                if (!available)
                  Positioned(
                    left: 8,
                    top: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: CatalogColors.ink,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'Agotado',
                        style: TextStyle(
                          color: CatalogColors.ground,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      product.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13.5,
                        height: 1.35,
                        color: available
                            ? CatalogColors.ink
                            : CatalogColors.inkMuted,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Text(
                            mxn(product.priceMxn),
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              fontFeatures: CatalogTheme.tabular,
                              color: available
                                  ? CatalogColors.ink
                                  : CatalogColors.inkMuted,
                            ),
                          ),
                        ),
                        if (available)
                          inOrder
                              ? QuantityStepper(
                                  quantity: quantity,
                                  onAdd: onAdd,
                                  onRemove: onRemove,
                                  compact: true,
                                )
                              : _AddButton(
                                  onPressed: onAdd, name: product.name),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProductImage extends StatelessWidget {
  const _ProductImage({required this.product});

  final PublicCatalogProduct product;

  @override
  Widget build(BuildContext context) {
    final url = product.imageUrl;
    final placeholder = ColoredBox(
      color: CatalogColors.tileFor(product.categoryName),
      child: Center(
        child: Icon(
          CatalogColors.iconFor(product.categoryName),
          size: 36,
          color: CatalogColors.ink.withValues(alpha: 0.35),
        ),
      ),
    );
    if (url == null || url.isEmpty) return placeholder;
    return Image.network(
      url,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => placeholder,
      loadingBuilder: (_, child, progress) =>
          progress == null ? child : placeholder,
    );
  }
}

class _AddButton extends StatelessWidget {
  const _AddButton({required this.onPressed, required this.name});

  final VoidCallback onPressed;
  final String name;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Agregar $name',
      child: Material(
        color: CatalogColors.accent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(10),
          child: const SizedBox(
            width: 40,
            height: 40,
            child: Icon(Icons.add_rounded, color: CatalogColors.onAccent),
          ),
        ),
      ),
    );
  }
}

/// `− n +` — el mismo control en la tarjeta y en el sheet del pedido.
class QuantityStepper extends StatelessWidget {
  const QuantityStepper({
    super.key,
    required this.quantity,
    required this.onAdd,
    required this.onRemove,
    this.compact = false,
  });

  final int quantity;
  final VoidCallback onAdd;
  final VoidCallback onRemove;

  /// En la tarjeta cabe en la esquina; en el sheet respira más.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final size = compact ? 32.0 : 40.0;
    return Container(
      height: compact ? 40 : 44,
      padding: const EdgeInsets.symmetric(horizontal: 3),
      decoration: BoxDecoration(
        color: CatalogColors.accentSoft,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _StepButton(
            icon: quantity == 1
                ? Icons.delete_outline_rounded
                : Icons.remove_rounded,
            label: quantity == 1 ? 'Quitar' : 'Uno menos',
            onTap: onRemove,
            size: size,
          ),
          SizedBox(
            width: compact ? 26 : 32,
            child: Text(
              '$quantity',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: compact ? 14 : 16,
                fontWeight: FontWeight.w700,
                fontFeatures: CatalogTheme.tabular,
                color: CatalogColors.accentPressed,
              ),
            ),
          ),
          _StepButton(
            icon: Icons.add_rounded,
            label: 'Uno más',
            onTap: onAdd,
            size: size,
          ),
        ],
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.size,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(icon, size: 20, color: CatalogColors.accentPressed),
        ),
      ),
    );
  }
}
