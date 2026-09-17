import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/theme/app_colors.dart';
import 'package:nexus_app/core/widgets/product_image_widget.dart';
import '../../../inventory/domain/product.dart';
import '../../../inventory/presentation/inventory_provider.dart';
import '../../../inventory/presentation/widgets/add_product_modal.dart';
import '../../domain/ean_lookup_result.dart';
import '../cart_provider.dart';
import '../community_lookup_provider.dart';

/// Panel desplegable de resultados de búsqueda del POS.
///
/// Filtra la lista ya cargada en inventoryProvider (sin llamada extra
/// al backend) con búsqueda fuzzy local case-insensitive.
/// Se muestra cuando searchQuery.isNotEmpty y se cierra al añadir un producto.
///
/// Tarea 15.2.1 — cuando no hay coincidencia local y lo tecleado/escaneado
/// parece un código de barras, consulta el motor de dos niveles (catálogo
/// semilla + red comunitaria) y ofrece el nombre verificado con un toque.
class ProductSearchResults extends ConsumerWidget {
  const ProductSearchResults({
    super.key,
    required this.query,
    required this.onProductAdded,
  });

  final String query;

  /// Callback que se ejecuta tras añadir un producto al carrito.
  /// La pantalla lo usa para limpiar la búsqueda y cerrar el panel.
  final VoidCallback onProductAdded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (query.trim().isEmpty) return const SizedBox.shrink();

    final allProducts = ref.watch(inventoryProvider).products;
    final q = query.toLowerCase().trim();

    final results = allProducts
        .where((p) {
          return p.name.toLowerCase().contains(q) ||
              p.sku.toLowerCase().contains(q) ||
              (p.barcode?.contains(q) ?? false);
        })
        .take(6)
        .toList();

    if (results.isEmpty) {
      // Sin coincidencia local. Si parece código de barras, el motor de dos
      // niveles puede tener el nombre; si es texto libre, no hay nada que
      // consultar (un nombre tecleado no identifica un producto).
      if (looksLikeBarcode(query)) {
        return _CommunitySuggestion(
          barcode: query.trim(),
          onProductAdded: onProductAdded,
        );
      }
      return _NoResultsHint(query: query);
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: results.asMap().entries.map((entry) {
            final isLast = entry.key == results.length - 1;
            return _ResultRow(
              product: entry.value,
              isLast: isLast,
              onAdd: () {
                ref.read(cartProvider.notifier).addProduct(entry.value);
                onProductAdded();
              },
            );
          }).toList(),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Fila de resultado
// ---------------------------------------------------------------------------

class _ResultRow extends StatelessWidget {
  const _ResultRow({
    required this.product,
    required this.isLast,
    required this.onAdd,
  });

  final Product product;
  final bool isLast;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onAdd,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          border: isLast
              ? null
              : const Border(
                  bottom: BorderSide(color: AppColors.border),
                ),
        ),
        child: Row(
          children: [
            // Thumbnail pequeño
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(8),
              ),
              child: ProductImageWidget(
                imageUrl: product.imageUrl,
                width: 38,
                height: 38,
                borderRadius: BorderRadius.circular(8),
                fit: BoxFit.cover,
                placeholder: _icon(),
              ),
            ),
            const SizedBox(width: 12),

            // Nombre + SKU
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.name,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: AppColors.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    product.sku,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.onSurfaceMuted,
                    ),
                  ),
                ],
              ),
            ),

            // Precio + botón +
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '\$${product.priceMxn.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.emerald,
                  ),
                ),
                const SizedBox(height: 2),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.emerald.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: AppColors.emerald.withValues(alpha: 0.3),
                    ),
                  ),
                  child: const Text(
                    '+ Añadir',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: AppColors.emerald,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _icon() => Center(
        child: Icon(
          Icons.inventory_2_outlined,
          size: 18,
          color: AppColors.onSurfaceMuted.withValues(alpha: 0.4),
        ),
      );
}

// ---------------------------------------------------------------------------
// Sugerencia del motor de dos niveles (Tarea 15.2.1 · RF-29 · Const. 7.5)
// ---------------------------------------------------------------------------

/// Reemplaza el "sin resultados" cuando lo escaneado es un código de barras.
///
/// Tres estados: consultando, con sugerencia, sin coincidencia en ningún
/// catálogo. La sugerencia se **ofrece**: un toque la usa, ninguno la ignora.
/// El nombre llega prellenado al modal de alta, donde el cajero pone el
/// precio de SU tienda (la red nunca comparte precios) y puede corregir el
/// nombre antes de guardar. Al guardar, el producto entra al carrito.
class _CommunitySuggestion extends ConsumerWidget {
  const _CommunitySuggestion({
    required this.barcode,
    required this.onProductAdded,
  });

  final String barcode;
  final VoidCallback onProductAdded;

  Future<void> _useSuggestion(
    BuildContext context,
    WidgetRef ref,
    EanLookupResult result,
  ) async {
    // El panel de resultados se cierra en cuanto el buscador pierde el foco
    // (checkout_screen.dart), y el modal de alta lo toma al abrirse: este
    // widget ya no existe cuando el modal regresa. Por eso se trabaja con el
    // contenedor de providers (vive lo que la app) y no con `ref`/`context`.
    final container = ProviderScope.containerOf(context);

    final createdName = await showAddProductModal(
      context,
      initialBarcode: barcode,
      initialName: result.name,
      initialCategory: result.category,
    );
    if (createdName == null) return;

    // El notifier inserta el producto nuevo al inicio de la lista.
    final products = container.read(inventoryProvider).products;
    final created = products.where((p) => p.barcode == barcode).firstOrNull ??
        products.where((p) => p.name == createdName).firstOrNull;
    if (created != null) {
      container.read(cartProvider.notifier).addProduct(created);
    }
    onProductAdded();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lookup = ref.watch(eanLookupProvider(barcode));

    return lookup.when(
      loading: () => _SuggestionShell(
        key: const Key('communityLookupLoading'),
        child: Row(
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.onSurfaceMuted,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Buscando $barcode en el catálogo Nexus…',
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.onSurfaceMuted,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        ),
      ),
      error: (_, __) => _NoResultsHint(query: barcode),
      data: (result) {
        if (!result.isFound) return _NoResultsHint(query: barcode);

        final isCommunity = result.source == EanSource.communityVerified;
        final chipColor = isCommunity ? AppColors.skyBlue : AppColors.onSurfaceMuted;
        final chipLabel = isCommunity
            ? 'Verificado por la comunidad Nexus'
            : 'Catálogo semilla oficial';
        final chipIcon = isCommunity ? Icons.groups_rounded : Icons.verified_outlined;

        return _SuggestionShell(
          key: const Key('communitySuggestion'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Origen — chip informativo, nunca una calificación
              Row(
                children: [
                  Icon(chipIcon, size: 16, color: chipColor),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      chipLabel,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.2,
                        color: chipColor,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Nombre sugerido + categoría
              Text(
                result.name!,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.onSurface,
                  height: 1.25,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 3),
              Text(
                _subtitle(result, isCommunity),
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.onSurfaceMuted,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: 12),

              // Única acción primaria: el precio lo pone la tienda
              SizedBox(
                width: double.infinity,
                height: 44,
                child: FilledButton(
                  key: const Key('useSuggestionButton'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.emerald,
                    foregroundColor: AppColors.darkSlate,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  onPressed: () => _useSuggestion(context, ref, result),
                  child: const Text('Usar este nombre y poner precio'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// "Abarrotes · 5 comercios coinciden" / "Bebidas · código 7501055300075".
  /// El conteo es un dato (cuántas tiendas independientes registraron lo
  /// mismo), no una calificación: sin estrellas, sin porcentajes.
  static String _subtitle(EanLookupResult r, bool isCommunity) {
    final parts = <String>[];
    if (r.category?.isNotEmpty ?? false) parts.add(r.category!);
    if (isCommunity && (r.confidenceScore ?? 0) >= 3) {
      parts.add('${r.confidenceScore} comercios coinciden');
    } else {
      parts.add('código ${r.barcode}');
    }
    return parts.join(' · ');
  }
}

/// Contenedor común de los tres estados: misma tarjeta que los resultados.
class _SuggestionShell extends StatelessWidget {
  const _SuggestionShell({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }
}

// ---------------------------------------------------------------------------
// Sin resultados
// ---------------------------------------------------------------------------

class _NoResultsHint extends StatelessWidget {
  const _NoResultsHint({required this.query});
  final String query;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Icon(
            Icons.search_off_rounded,
            size: 18,
            color: AppColors.onSurfaceMuted.withValues(alpha: 0.5),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Sin resultados para "$query"',
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.onSurfaceMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
