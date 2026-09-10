import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_colors.dart';
import 'inventory_provider.dart';
import 'widgets/add_product_modal.dart';
import 'widgets/category_filter_bar.dart';
import 'widgets/inventory_search_bar.dart';
import 'widgets/product_list_tile.dart';

/// Pantalla principal de Inventario — Subtarea 3.2.1
///
/// Casos de uso implementados:
///   CU-06.1 Listado normal con paginación
///   CU-06.2 Búsqueda fuzzy con debounce 300 ms
///   CU-06.3 Filtro por categoría (local)
///   CU-06.4 Filtro stock bajo (query al repositorio)
///   CU-06.5 Scroll infinito al 80% de la lista
///   CU-06.6 Empty state inicial con CTA
///   CU-06.7 Error de red con banner + reintentar
///
/// Trazabilidad: Constitución Art. I (1.2.4 MXN, 1.2.8 Rapidez)
///              Doc. Maestro RF-02, RF-04, SR-02, SR-08 · HU-05 / CU-06
class InventoryScreen extends ConsumerStatefulWidget {
  const InventoryScreen({super.key});

  @override
  ConsumerState<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends ConsumerState<InventoryScreen> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  // ── Scroll infinito — dispara loadMore al llegar al 80% ─────────────────
  void _onScroll() {
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent * 0.8) {
      ref.read(inventoryProvider.notifier).loadMore();
    }
  }

  // ── Navegación al detalle ────────────────────────────────────────────────
  void _goToDetail(BuildContext context, String productId) {
    context.push(AppRoutes.productDetailPath(productId));
  }

  // ── Abre modal de alta (3.2.3) ───────────────────────────────────────────
  Future<void> _openAddModal(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final created = await showAddProductModal(context);
    if (created != null && mounted) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('✓ "$created" agregado al inventario'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.surface,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(inventoryProvider);

    return Scaffold(
      backgroundColor: AppColors.darkSlate,
      appBar: _buildAppBar(context),
      body: Column(
        children: [
          // ── Barra de búsqueda ──────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: InventorySearchBar(
              onChanged: (q) =>
                  ref.read(inventoryProvider.notifier).setQuery(q),
            ),
          ),

          // ── Chips de filtro ────────────────────────────────────────────
          CategoryFilterBar(
            categories: state.availableCategories,
            activeCategory: state.activeCategory,
            showLowStock: state.showLowStock,
            onCategorySelected: (cat) =>
                ref.read(inventoryProvider.notifier).setCategory(cat),
            onToggleLowStock: () =>
                ref.read(inventoryProvider.notifier).toggleLowStock(),
          ),

          const SizedBox(height: 4),

          // ── Banner de error (no bloqueante) ────────────────────────────
          if (state.hasError) _buildErrorBanner(state.error!),

          // ── Cuerpo principal ───────────────────────────────────────────
          Expanded(
            child: _buildBody(context, state),
          ),
        ],
      ),
      floatingActionButton: _buildFab(context),
    );
  }

  // ────────────────────────────────────────────────────────────────────────
  // AppBar
  // ────────────────────────────────────────────────────────────────────────

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    return AppBar(
      backgroundColor: AppColors.darkSlate,
      elevation: 0,
      automaticallyImplyLeading: false,
      title: const Text(
        'Inventario',
        style: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: AppColors.onSurface,
        ),
      ),
      actions: [
        // Modo Góndola — escaneo continuo de góndola (Tarea 5.2)
        IconButton(
          tooltip: 'Modo Góndola — Escaneo continuo',
          icon: const Icon(
            Icons.document_scanner_rounded,
            color: AppColors.skyBlue,
            size: 24,
          ),
          onPressed: () => context.push(AppRoutes.gondola),
        ),
        // Importar desde Excel/CSV (Tarea 5.2)
        IconButton(
          tooltip: 'Importar desde Excel o CSV',
          icon: const Icon(
            Icons.upload_file_rounded,
            color: AppColors.onSurface,
            size: 24,
          ),
          onPressed: () => context.push(AppRoutes.import),
        ),
        // Acceso a Configuraciones / Perfil — placeholder hasta tarea RBAC
        IconButton(
          tooltip: 'Perfil y configuración',
          icon: const Icon(
            Icons.account_circle_outlined,
            color: AppColors.onSurface,
            size: 26,
          ),
          onPressed: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Configuraciones disponibles próximamente'),
                behavior: SnackBarBehavior.floating,
              ),
            );
          },
        ),
        const SizedBox(width: 4),
      ],
    );
  }

  // ────────────────────────────────────────────────────────────────────────
  // Cuerpo — despacha a skeleton / empty state / lista
  // ────────────────────────────────────────────────────────────────────────

  Widget _buildBody(BuildContext context, InventoryState state) {
    // Primera carga
    if (state.isLoading) return _buildSkeleton();

    // Sin productos (sin filtros activos) — CU-06.6
    if (!state.hasProducts &&
        state.query.isEmpty &&
        state.activeCategory == null &&
        !state.showLowStock) {
      return _buildEmptyState(context);
    }

    // Sin resultados con filtros activos — CU-06.2 / CU-06.3 / CU-06.4
    if (!state.hasProducts) return _buildEmptySearchState(state);

    return _buildProductList(context, state);
  }

  // ────────────────────────────────────────────────────────────────────────
  // Lista de productos con scroll infinito
  // ────────────────────────────────────────────────────────────────────────

  Widget _buildProductList(BuildContext context, InventoryState state) {
    return ListView.separated(
      controller: _scrollController,
      padding: const EdgeInsets.only(top: 4, bottom: 100),
      itemCount: state.products.length + (state.isLoadingMore ? 1 : 0),
      separatorBuilder: (_, __) => const Divider(
        height: 1,
        indent: 80,
        endIndent: 16,
        color: AppColors.border,
      ),
      itemBuilder: (context, index) {
        // Indicador de carga de página adicional al final de la lista
        if (index == state.products.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.emerald,
                ),
              ),
            ),
          );
        }

        final product = state.products[index];
        return ProductListTile(
          product: product,
          onTap: () => _goToDetail(context, product.id),
        );
      },
    );
  }

  // ────────────────────────────────────────────────────────────────────────
  // Skeleton — primera carga
  // ────────────────────────────────────────────────────────────────────────

  Widget _buildSkeleton() {
    return ListView.separated(
      padding: const EdgeInsets.only(top: 4),
      itemCount: 8,
      separatorBuilder: (_, __) => const Divider(
        height: 1,
        indent: 80,
        endIndent: 16,
        color: AppColors.border,
      ),
      itemBuilder: (_, __) => const ProductListTileSkeleton(),
    );
  }

  // ────────────────────────────────────────────────────────────────────────
  // Empty states
  // ────────────────────────────────────────────────────────────────────────

  /// CU-06.6 — sin productos registrados en absoluto
  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: AppColors.emerald.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.inventory_2_outlined,
                size: 44,
                color: AppColors.emerald,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Aún no tienes productos',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.onSurface,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'Agrega tu primer artículo con solo\nnombre, precio y cantidad.',
              style: TextStyle(
                fontSize: 14,
                color: AppColors.onSurfaceMuted,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
            ElevatedButton.icon(
              onPressed: () => _openAddModal(context),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Agregar tu primer producto'),
            ),
          ],
        ),
      ),
    );
  }

  /// Sin resultados para búsqueda / filtro activo
  Widget _buildEmptySearchState(InventoryState state) {
    final String message;
    if (state.showLowStock && !state.hasProducts) {
      message = 'Todo tu inventario tiene\nstock suficiente ✓';
    } else if (state.query.isNotEmpty) {
      message = 'Sin resultados para\n"${state.query}"';
    } else {
      message = 'Sin productos en\nesta categoría';
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              state.showLowStock
                  ? Icons.check_circle_outline_rounded
                  : Icons.search_off_rounded,
              size: 56,
              color: AppColors.onSurfaceMuted,
            ),
            const SizedBox(height: 16),
            Text(
              message,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: AppColors.onSurfaceMuted,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  // ────────────────────────────────────────────────────────────────────────
  // Banner de error — no bloquea la UI (CU-06.7)
  // ────────────────────────────────────────────────────────────────────────

  Widget _buildErrorBanner(String error) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.wifi_off_rounded, size: 18, color: AppColors.error),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Error de conexión. Revisa tu red.',
              style: TextStyle(
                fontSize: 13,
                color: AppColors.error,
              ),
            ),
          ),
          TextButton(
            onPressed: () => ref.read(inventoryProvider.notifier).retry(),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.error,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text(
              'Reintentar',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ────────────────────────────────────────────────────────────────────────
  // FAB — abre modal de alta (3.2.3)
  // ────────────────────────────────────────────────────────────────────────

  Widget _buildFab(BuildContext context) {
    return FloatingActionButton(
      onPressed: () => _openAddModal(context),
      backgroundColor: AppColors.emerald,
      foregroundColor: AppColors.darkSlate,
      elevation: 2,
      tooltip: 'Agregar producto',
      child: const Icon(Icons.add_rounded, size: 28),
    );
  }
}
