import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/public_catalog.dart';
import 'catalog_theme.dart';
import 'whatsapp_catalog_provider.dart';
import 'widgets/order_bar.dart';
import 'widgets/order_sheet.dart';
import 'widgets/product_card.dart';

/// Vitrina pública `/tienda/{slug}` — Tarea 13.2.1 (RF-23, Constitución 7.4).
///
/// La abre un cliente desde un enlace de WhatsApp o un QR, sin cuenta. Tema
/// claro propio (`CatalogTheme.light`), independiente del oscuro del tendero.
///
/// Decisiones de diseño (contrato en `.impeccable/surfaces/`):
///   · Es la página de tienda que el cliente ya sabe usar (grid, "+", barra
///     con el total) **sin** la capa comercial de las apps de delivery: cero
///     promos, cero cuenta.
///   · Precio y "+" siempre visibles; buscador y categorías fijos al hacer
///     scroll.
///   · El estado real se dice: agotado, catálogo apagado, tienda inexistente,
///     sin conexión — cada uno con su salida.
///   · Sin fotos (D4), el hueco 1:1 lo ocupa un placeholder por categoría
///     con color e ícono propios; cuando lleguen las fotos caben ahí mismo.
class PublicCatalogScreen extends ConsumerStatefulWidget {
  const PublicCatalogScreen({super.key, required this.slug});

  final String slug;

  @override
  ConsumerState<PublicCatalogScreen> createState() =>
      _PublicCatalogScreenState();
}

class _PublicCatalogScreenState extends ConsumerState<PublicCatalogScreen> {
  final _searchCtrl = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  /// Un teclado en un teléfono barato manda una letra cada ~100 ms; pedir el
  /// catálogo por cada una es tirar datos. 250 ms de espera es invisible.
  void _onSearchChanged(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted) ref.read(publicCatalogQueryProvider.notifier).search(text);
    });
  }

  void _clearSearch() {
    _searchCtrl.clear();
    _debounce?.cancel();
    ref.read(publicCatalogQueryProvider.notifier).search('');
  }

  @override
  Widget build(BuildContext context) {
    final catalog = ref.watch(publicCatalogProvider(widget.slug));
    final cart = ref.watch(orderCartProvider);

    return Theme(
      data: CatalogTheme.light,
      child: Scaffold(
        backgroundColor: CatalogColors.ground,
        // La barra del pedido flota sobre el grid en vez de ocupar el slot de
        // `bottomNavigationBar`: escondida no debe reservar altura.
        body: Stack(
          children: [
            Positioned.fill(
              child: catalog.when(
                skipLoadingOnReload: true,
                loading: () => const _CatalogSkeleton(),
                error: (error, _) => _FailureView(
                  failure: error,
                  slug: widget.slug,
                  onRetry: () =>
                      ref.invalidate(publicCatalogProvider(widget.slug)),
                ),
                data: (data) => _CatalogBody(
                  catalog: data,
                  refreshing: catalog.isLoading,
                  searchCtrl: _searchCtrl,
                  onSearchChanged: _onSearchChanged,
                  onClearSearch: _clearSearch,
                ),
              ),
            ),
            if (catalog.hasValue)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: OrderBar(
                  itemCount: cart.itemCount,
                  subtotalMxn: cart.subtotalMxn,
                  onOpen: () => showOrderSheet(context,
                      store: catalog.requireValue.store),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Cuerpo
// ---------------------------------------------------------------------------

class _CatalogBody extends ConsumerWidget {
  const _CatalogBody({
    required this.catalog,
    required this.refreshing,
    required this.searchCtrl,
    required this.onSearchChanged,
    required this.onClearSearch,
  });

  final PublicCatalog catalog;
  final bool refreshing;
  final TextEditingController searchCtrl;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onClearSearch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = ref.watch(publicCatalogQueryProvider);
    final cart = ref.watch(orderCartProvider);
    final cartNotifier = ref.read(orderCartProvider.notifier);
    final width = MediaQuery.sizeOf(context).width;
    final columns = width >= 900 ? 4 : (width >= 600 ? 3 : 2);
    // Alto de la tarjeta = foto 1:1 + bloque fijo de texto y control (ver
    // `ProductCard.textBlockHeight`), así la proporción no depende del ancho.
    final cardWidth = (width - 32 - 12 * (columns - 1)) / columns;
    final aspectRatio = cardWidth / (cardWidth + ProductCard.textBlockHeight);
    final filtering = query.search.isNotEmpty || query.categoryId != null;

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: _StoreHeader(store: catalog.store)),
        SliverPersistentHeader(
          pinned: true,
          delegate: _FiltersDelegate(
            searchCtrl: searchCtrl,
            onSearchChanged: onSearchChanged,
            onClearSearch: onClearSearch,
            categories: catalog.categories,
            selected: query.categoryId,
            onSelect: (id) => ref
                .read(publicCatalogQueryProvider.notifier)
                .selectCategory(id),
            refreshing: refreshing,
          ),
        ),
        if (catalog.products.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: _EmptyResults(
              filtering: filtering,
              onClear: () {
                onClearSearch();
                ref
                    .read(publicCatalogQueryProvider.notifier)
                    .selectCategory(null);
              },
            ),
          )
        else
          SliverPadding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, cart.isEmpty ? 24 : 96),
            sliver: SliverGrid(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: aspectRatio,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, i) {
                  final product = catalog.products[i];
                  return ProductCard(
                    product: product,
                    quantity: cart.quantityOf(product.id),
                    onAdd: () => cartNotifier.add(product),
                    onRemove: () => cartNotifier.remove(product.id),
                  );
                },
                childCount: catalog.products.length,
              ),
            ),
          ),
        const SliverToBoxAdapter(child: _Footer()),
      ],
    );
  }
}

class _StoreHeader extends StatelessWidget {
  const _StoreHeader({required this.store});

  final PublicStoreInfo store;

  @override
  Widget build(BuildContext context) {
    final hours = store.businessHours?.trim();
    final number = store.whatsappNumber?.trim();
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: CatalogColors.accentSoft,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    _initials(store.name),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: CatalogColors.accentPressed,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        store.name,
                        key: const Key('storeName'),
                        style: const TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w800,
                          height: 1.15,
                          letterSpacing: -0.2,
                        ),
                      ),
                      if (hours != null && hours.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          hours,
                          style: const TextStyle(
                            fontSize: 13,
                            color: CatalogColors.inkMuted,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _Fact(
                  icon: Icons.chat_outlined,
                  text: number == null || number.isEmpty
                      ? 'Pedidos por WhatsApp'
                      : 'Pedidos por WhatsApp · $number',
                ),
                if (store.deliveryEnabled)
                  _Fact(
                    icon: Icons.moped_outlined,
                    text: store.deliveryFeeMxn > 0
                        ? 'Envío ${mxn(store.deliveryFeeMxn)}'
                        : 'Envío a domicilio',
                  ),
                if (store.pickupEnabled)
                  const _Fact(
                      icon: Icons.storefront_outlined,
                      text: 'Recoger en tienda'),
                if (store.minOrderAmountMxn > 0)
                  _Fact(
                    icon: Icons.receipt_long_outlined,
                    text: 'Mínimo ${mxn(store.minOrderAmountMxn)}',
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _initials(String name) {
    final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    final letters = words.take(2).map((w) => w[0].toUpperCase()).join();
    return letters.isEmpty ? '·' : letters;
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: CatalogColors.inkMuted),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            text,
            style:
                const TextStyle(fontSize: 12.5, color: CatalogColors.inkMuted),
          ),
        ),
      ],
    );
  }
}

/// Buscador + chips, fijos arriba al hacer scroll.
class _FiltersDelegate extends SliverPersistentHeaderDelegate {
  const _FiltersDelegate({
    required this.searchCtrl,
    required this.onSearchChanged,
    required this.onClearSearch,
    required this.categories,
    required this.selected,
    required this.onSelect,
    required this.refreshing,
  });

  final TextEditingController searchCtrl;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onClearSearch;
  final List<PublicCategory> categories;
  final String? selected;
  final ValueChanged<String?> onSelect;
  final bool refreshing;

  static const double _height = 112;

  @override
  double get minExtent => _height;
  @override
  double get maxExtent => _height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) {
    return Container(
      height: _height,
      decoration: BoxDecoration(
        color: CatalogColors.ground,
        border: Border(
          bottom: BorderSide(
            color: overlaps ? CatalogColors.line : Colors.transparent,
          ),
        ),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: SizedBox(
              height: 44,
              child: ValueListenableBuilder<TextEditingValue>(
                valueListenable: searchCtrl,
                builder: (_, value, __) => TextField(
                  key: const Key('catalogSearch'),
                  controller: searchCtrl,
                  onChanged: onSearchChanged,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'Buscar producto',
                    prefixIcon: const Icon(Icons.search_rounded,
                        color: CatalogColors.inkMuted),
                    suffixIcon: value.text.isEmpty
                        ? (refreshing
                            ? const Padding(
                                padding: EdgeInsets.all(12),
                                child: SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: CatalogColors.accent),
                                ),
                              )
                            : null)
                        : IconButton(
                            key: const Key('catalogSearchClear'),
                            tooltip: 'Borrar búsqueda',
                            onPressed: onClearSearch,
                            icon: const Icon(Icons.close_rounded,
                                color: CatalogColors.inkMuted),
                          ),
                  ),
                ),
              ),
            ),
          ),
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                _CategoryChip(
                  key: const Key('category-all'),
                  label: 'Todo',
                  selected: selected == null,
                  onTap: () => onSelect(null),
                ),
                for (final c in categories)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: _CategoryChip(
                      key: Key('category-${c.id}'),
                      label: c.name,
                      selected: selected == c.id,
                      onTap: () => onSelect(selected == c.id ? null : c.id),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  bool shouldRebuild(_FiltersDelegate old) =>
      old.categories != categories ||
      old.selected != selected ||
      old.refreshing != refreshing;
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? CatalogColors.accent : CatalogColors.tile,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            alignment: Alignment.center,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: selected ? CatalogColors.onAccent : CatalogColors.ink,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyResults extends StatelessWidget {
  const _EmptyResults({required this.filtering, required this.onClear});

  final bool filtering;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 40, 32, 40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.search_off_rounded,
              size: 40, color: CatalogColors.inkMuted),
          const SizedBox(height: 12),
          Text(
            filtering
                ? 'No encontramos eso'
                : 'La tienda aún no tiene productos en su catálogo',
            key: const Key('catalogEmpty'),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            filtering
                ? 'Prueba con otro nombre o quita el filtro.'
                : 'Vuelve más tarde o pregúntale directo por WhatsApp.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: CatalogColors.inkMuted),
          ),
          if (filtering) ...[
            const SizedBox(height: 18),
            OutlinedButton(
              key: const Key('catalogClearFilters'),
              onPressed: onClear,
              child: const Text('Ver todo'),
            ),
          ],
        ],
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(16, 20, 16, 28),
      child: Text(
        'Precios en pesos mexicanos. El pedido se confirma por WhatsApp con '
        'la tienda.',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 12, color: CatalogColors.inkMuted),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Estados: cargando y fallos
// ---------------------------------------------------------------------------

class _CatalogSkeleton extends StatelessWidget {
  const _CatalogSkeleton();

  @override
  Widget build(BuildContext context) {
    Widget block(double w, double h, {double r = 8}) => Container(
          width: w,
          height: h,
          decoration: BoxDecoration(
            color: CatalogColors.tile,
            borderRadius: BorderRadius.circular(r),
          ),
        );
    return SafeArea(
      child: Padding(
        key: const Key('catalogSkeleton'),
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              block(44, 44, r: 12),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  block(180, 18),
                  const SizedBox(height: 8),
                  block(120, 12),
                ],
              ),
            ]),
            const SizedBox(height: 18),
            block(double.infinity, 44, r: 12),
            const SizedBox(height: 10),
            Row(children: [
              block(60, 36, r: 999),
              const SizedBox(width: 8),
              block(84, 36, r: 999),
              const SizedBox(width: 8),
              block(72, 36, r: 999),
            ]),
            const SizedBox(height: 16),
            Expanded(
              child: GridView.count(
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 0.66,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  for (var i = 0; i < 6; i++) block(0, 0, r: 12),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FailureView extends StatelessWidget {
  const _FailureView({
    required this.failure,
    required this.slug,
    required this.onRetry,
  });

  final Object failure;
  final String slug;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final (icon, title, body, retry) = switch (failure) {
      StoreNotFound() => (
          Icons.storefront_outlined,
          'No encontramos esta tienda',
          'Revisa que el enlace esté completo o pídeselo de nuevo a la tienda.',
          false,
        ),
      CatalogDisabled(storeName: final name) => (
          Icons.nightlight_outlined,
          '$name tiene su catálogo apagado por ahora',
          'Puedes escribirle directo por WhatsApp o volver más tarde.',
          true,
        ),
      _ => (
          Icons.wifi_off_rounded,
          'No pudimos cargar el catálogo',
          'Revisa tu conexión e inténtalo de nuevo.',
          true,
        ),
    };

    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            key: const Key('catalogFailure'),
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 44, color: CatalogColors.inkMuted),
              const SizedBox(height: 14),
              Text(
                title,
                textAlign: TextAlign.center,
                style:
                    const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                body,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  height: 1.45,
                  color: CatalogColors.inkMuted,
                ),
              ),
              if (retry) ...[
                const SizedBox(height: 22),
                FilledButton(
                  key: const Key('catalogRetry'),
                  onPressed: onRetry,
                  child: const Text('Intentar de nuevo'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
