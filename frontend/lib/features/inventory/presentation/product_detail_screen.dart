import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../domain/product.dart';
import 'inventory_provider.dart';
import 'widgets/action_grid.dart';
import 'widgets/adjust_stock_modal.dart';
import 'widgets/kardex_bottom_sheet.dart';
import 'widgets/product_label_modal.dart';
import 'widgets/stock_card.dart';
import 'widgets/transfer_stock_modal.dart';

/// Pantalla de detalle de producto — Subtarea 3.2.2
///
/// Casos de uso implementados:
///   CU-06.4.1 Carga (caché primero → fallback FutureProvider.family)
///   CU-06.4.2 Margen de ganancia con semáforo
///   CU-06.4.3 Tarjetas de stock DISPONIBLE / RESERVADO
///   CU-06.4.4 Cuadrícula 2×2 de acciones (placeholders Tarea 4.2)
///   CU-06.4.5 Botón editar en AppBar (placeholder Tarea 3.2.3+)
///   CU-06.4.6 Banner fotográfico / placeholder sin imagen
///   CU-06.4.7 Pantalla de error completa con reintentar
///
/// Trazabilidad: Constitución Art. I (1.2.4 MXN, 1.2.8 Rapidez)
///              Doc. Maestro RF-02, RF-05, SR-02 · HU-05 / CU-06
class ProductDetailScreen extends ConsumerWidget {
  const ProductDetailScreen({super.key, required this.productId});

  final String productId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productAsync = ref.watch(productDetailProvider(productId));

    return productAsync.when(
      loading: () => _buildScaffold(
        context,
        title: '',
        body: const SingleChildScrollView(child: _DetailSkeleton()),
      ),
      error: (e, _) => _buildScaffold(
        context,
        title: 'Error',
        body: _ErrorState(
          onRetry: () => ref.invalidate(productDetailProvider(productId)),
        ),
      ),
      data: (product) => _buildScaffold(
        context,
        title: product.name,
        editAction: () => context.push(
          AppRoutes.productEditPath(product.id),
        ),
        body: _DetailBody(product: product),
      ),
    );
  }

  // ── Scaffold compartido ──────────────────────────────────────────────────

  Widget _buildScaffold(
    BuildContext context, {
    required String title,
    required Widget body,
    VoidCallback? editAction,
  }) {
    return Scaffold(
      backgroundColor: AppColors.darkSlate,
      appBar: AppBar(
        backgroundColor: AppColors.darkSlate,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              size: 20, color: AppColors.onSurface),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppColors.onSurface,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (editAction != null)
            IconButton(
              tooltip: 'Editar producto',
              icon: const Icon(Icons.edit_outlined,
                  size: 20, color: AppColors.onSurface),
              onPressed: editAction,
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: body,
    );
  }
}

// ---------------------------------------------------------------------------
// Cuerpo principal — producto cargado
// ---------------------------------------------------------------------------

class _DetailBody extends StatelessWidget {
  const _DetailBody({required this.product});

  final Product product;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Banner fotográfico ─────────────────────────────────────────
          _ProductBanner(imageUrl: product.imageUrl),

          // ── Identificación ────────────────────────────────────────────
          _buildIdentity(context),

          const _SectionDivider(),

          // ── Métricas de precio ────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: _PriceMetricsRow(product: product),
          ),

          const _SectionDivider(),

          // ── Tarjetas de stock ─────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Row(
              children: [
                StockCard(
                  product: product,
                  variant: StockCardVariant.available,
                ),
                const SizedBox(width: 10),
                StockCard(
                  product: product,
                  variant: StockCardVariant.reserved,
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),
          const _SectionDivider(),

          // ── Cuadrícula de acciones ────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Acciones',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.onSurface,
                      ),
                    ),
                    Text(
                      'Todas las opciones de esta →',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.onSurfaceMuted.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ActionGrid(
                  onAdjustStock: () =>
                      showAdjustStockModal(context, product).then((adjusted) {
                    if (adjusted && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('✓ Stock ajustado correctamente'),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    }
                  }),
                  onTransfer: () => showTransferStockModal(context, product)
                      .then((transferred) {
                    if (transferred && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('✓ Traslado registrado correctamente'),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    }
                  }),
                  onKardex: () => showKardexBottomSheet(
                    context,
                    productId: product.id,
                    productName: product.name,
                  ),
                  onLabel: () => showProductLabelModal(context, product),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),
          const _SectionDivider(),

          // ── Información adicional (colapsable) ────────────────────────
          _AdditionalInfo(product: product),
        ],
      ),
    );
  }

  // ── Sección de identificación ────────────────────────────────────────────

  Widget _buildIdentity(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Nombre + SKU en la misma fila
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  product.name,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        height: 1.2,
                      ),
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppColors.border),
                ),
                child: Text(
                  'SKU: ${product.sku}',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: AppColors.onSurfaceMuted,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // Chips de categoría y almacén
          Wrap(
            spacing: 6,
            children: [
              _InfoChip(
                icon: Icons.folder_outlined,
                label: product.category,
              ),
              if (product.warehouseId != null)
                const _InfoChip(
                  icon: Icons.warehouse_outlined,
                  label: 'Almacén Principal',
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Banner fotográfico
// ---------------------------------------------------------------------------

class _ProductBanner extends StatelessWidget {
  const _ProductBanner({required this.imageUrl});

  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 200,
      width: double.infinity,
      color: AppColors.surfaceVariant,
      child: imageUrl != null
          ? Image.network(
              imageUrl!,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _placeholder(),
            )
          : _placeholder(),
    );
  }

  Widget _placeholder() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.inventory_2_outlined,
          size: 64,
          color: AppColors.onSurfaceMuted.withValues(alpha: 0.4),
        ),
        const SizedBox(height: 8),
        Text(
          'SIN IMAGEN DISPONIBLE',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: AppColors.onSurfaceMuted.withValues(alpha: 0.5),
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 12),
        // Botón "Fotografía" — placeholder visual
        OutlinedButton.icon(
          onPressed: null, // Tarea 3.2.3+
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.onSurfaceMuted,
            side: BorderSide(
              color: AppColors.onSurfaceMuted.withValues(alpha: 0.3),
            ),
            minimumSize: Size.zero,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          icon: const Icon(Icons.photo_camera_outlined, size: 14),
          label: const Text(
            'Fotografía',
            style: TextStyle(fontSize: 12),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Fila de métricas de precio — Precio venta · Costo · Margen
// ---------------------------------------------------------------------------

class _PriceMetricsRow extends StatelessWidget {
  const _PriceMetricsRow({required this.product});

  final Product product;

  @override
  Widget build(BuildContext context) {
    final margin = product.profitMargin;
    final marginText = margin != null ? '${margin.toStringAsFixed(1)}%' : '—';
    final marginColor = _marginColor(margin);

    return IntrinsicHeight(
      child: Row(
        children: [
          Expanded(
            child: _MetricColumn(
              label: 'PRECIO VENTA',
              value: '\$${product.priceMxn.toStringAsFixed(2)}',
              subtitle: 'MXN',
              valueColor: AppColors.emerald,
            ),
          ),
          const _VerticalDivider(),
          Expanded(
            child: _MetricColumn(
              label: 'COSTO',
              value: '\$${product.costMxn.toStringAsFixed(2)}',
              subtitle: 'MXN',
              valueColor: AppColors.onSurface,
            ),
          ),
          const _VerticalDivider(),
          Expanded(
            child: _MetricColumn(
              label: 'MARGEN',
              value: marginText,
              subtitle: margin != null
                  ? '+\$${(product.priceMxn - product.costMxn).toStringAsFixed(2)}'
                  : 'Sin costo',
              valueColor: marginColor,
            ),
          ),
        ],
      ),
    );
  }

  Color _marginColor(double? margin) {
    if (margin == null) return AppColors.onSurfaceMuted;
    if (margin >= 30) return AppColors.emerald;
    if (margin >= 10) return AppColors.warning;
    return AppColors.error;
  }
}

class _MetricColumn extends StatelessWidget {
  const _MetricColumn({
    required this.label,
    required this.value,
    required this.subtitle,
    required this.valueColor,
  });

  final String label;
  final String value;
  final String subtitle;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: AppColors.onSurfaceMuted,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: valueColor,
              height: 1,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.onSurfaceMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _VerticalDivider extends StatelessWidget {
  const _VerticalDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      margin: const EdgeInsets.symmetric(vertical: 2),
      color: AppColors.border,
    );
  }
}

// ---------------------------------------------------------------------------
// Información adicional — sección colapsable
// ---------------------------------------------------------------------------

class _AdditionalInfo extends StatefulWidget {
  const _AdditionalInfo({required this.product});

  final Product product;

  @override
  State<_AdditionalInfo> createState() => _AdditionalInfoState();
}

class _AdditionalInfoState extends State<_AdditionalInfo> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final p = widget.product;

    return Column(
      children: [
        // Header colapsable
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Row(
              children: [
                const Icon(
                  Icons.info_outline_rounded,
                  size: 16,
                  color: AppColors.onSurfaceMuted,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Información adicional',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.onSurface,
                    ),
                  ),
                ),
                AnimatedRotation(
                  duration: const Duration(milliseconds: 200),
                  turns: _expanded ? 0.5 : 0,
                  child: const Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 20,
                    color: AppColors.onSurfaceMuted,
                  ),
                ),
              ],
            ),
          ),
        ),

        // Contenido colapsable
        AnimatedCrossFade(
          duration: const Duration(milliseconds: 220),
          crossFadeState:
              _expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
          firstChild: const SizedBox.shrink(),
          secondChild: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Column(
              children: [
                if (p.barcode != null)
                  _InfoRow(
                    label: 'Código de barras (EAN-13)',
                    value: p.barcode!,
                  ),
                _InfoRow(
                  label: 'Stock mínimo de alerta',
                  value: p.minStockAlert != null
                      ? '${p.minStockAlert} pzs'
                      : 'No configurado',
                ),
                const _InfoRow(
                  label: 'Precio máximo sugerido',
                  value: '—',
                ),
                const _InfoRow(
                  label: 'Unidad de medida',
                  value: 'Pieza / Botella',
                ),
                const _InfoRow(
                  label: 'Proveedor predeterminado',
                  value: '—',
                ),
                const _InfoRow(
                  label: 'Impuesto aplicable (IVA)',
                  value: '16 %',
                ),
                _InfoRow(
                  label: 'Última actualización',
                  value: _formatDate(p.createdAt),
                  isLast: true,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _formatDate(DateTime date) {
    final diff = DateTime.now().difference(date);
    if (diff.inDays == 0) return 'Hoy, ${_time(date)}';
    if (diff.inDays == 1) return 'Ayer, ${_time(date)}';
    return '${date.day}/${date.month}/${date.year}, ${_time(date)}';
  }

  String _time(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:'
      '${d.minute.toString().padLeft(2, '0')} hs';
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
    this.isLast = false,
  });

  final String label;
  final String value;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 5,
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.onSurfaceMuted,
                  ),
                ),
              ),
              Expanded(
                flex: 5,
                child: Text(
                  value,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: AppColors.onSurface,
                  ),
                  textAlign: TextAlign.end,
                ),
              ),
            ],
          ),
        ),
        if (!isLast) const Divider(height: 1, color: AppColors.border),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Chip de categoría / almacén
// ---------------------------------------------------------------------------

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: AppColors.onSurfaceMuted),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.onSurfaceMuted,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Divisor de sección
// ---------------------------------------------------------------------------

class _SectionDivider extends StatelessWidget {
  const _SectionDivider();

  @override
  Widget build(BuildContext context) =>
      const Divider(height: 1, color: AppColors.border);
}

// ---------------------------------------------------------------------------
// Skeleton — estado de carga
// ---------------------------------------------------------------------------

class _DetailSkeleton extends StatefulWidget {
  const _DetailSkeleton();

  @override
  State<_DetailSkeleton> createState() => _DetailSkeletonState();
}

class _DetailSkeletonState extends State<_DetailSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.4, end: 0.9).animate(_ctrl);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Banner
          _box(200, double.infinity, radius: 0),
          const SizedBox(height: 16),
          // Nombre y SKU
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(child: _box(24, double.infinity)),
                const SizedBox(width: 12),
                _box(18, 80),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _box(14, 120),
          ),
          const SizedBox(height: 20),
          // Métricas
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: List.generate(
                3,
                (_) => Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: _box(48, double.infinity),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Tarjetas stock
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(child: _box(90, double.infinity)),
                const SizedBox(width: 10),
                Expanded(child: _box(90, double.infinity)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Grid acciones
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 2.4,
              children: List.generate(4, (_) => _box(52, double.infinity)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _box(double height, double width, {double radius = 8}) {
    return Container(
      height: height,
      width: width == double.infinity ? null : width,
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant.withValues(alpha: _anim.value),
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Pantalla de error completa — CU-06.4.7
// ---------------------------------------------------------------------------

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cloud_off_rounded,
              size: 56,
              color: AppColors.onSurfaceMuted,
            ),
            const SizedBox(height: 16),
            const Text(
              'No se pudo cargar\nel producto',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.onSurface,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Verifica tu conexión e intenta de nuevo.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: AppColors.onSurfaceMuted,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }
}
