import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../../core/theme/app_colors.dart';
import '../../domain/inventory_movement.dart';
import '../kardex_provider.dart';

// ---------------------------------------------------------------------------
// Función de conveniencia
// ---------------------------------------------------------------------------

Future<void> showKardexBottomSheet(
  BuildContext context, {
  required String productId,
  required String productName,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    backgroundColor: Colors.transparent,
    builder: (_) => KardexBottomSheet(
      productId: productId,
      productName: productName,
    ),
  );
}

// ---------------------------------------------------------------------------
// Widget principal
// ---------------------------------------------------------------------------

class KardexBottomSheet extends ConsumerStatefulWidget {
  const KardexBottomSheet({
    super.key,
    required this.productId,
    required this.productName,
  });

  final String productId;
  final String productName;

  @override
  ConsumerState<KardexBottomSheet> createState() => _KardexBottomSheetState();
}

class _KardexBottomSheetState extends ConsumerState<KardexBottomSheet> {
  final _scrollController = ScrollController();
  bool _filtersVisible = false;

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

  // ── Scroll infinito al 80% ───────────────────────────────────────────────

  void _onScroll() {
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent * 0.8) {
      ref.read(kardexProvider(widget.productId).notifier).loadMore();
    }
  }

  // ── Selectores de fecha ──────────────────────────────────────────────────

  Future<void> _pickDateFrom() async {
    final state = ref.read(kardexProvider(widget.productId));
    final picked = await showDatePicker(
      context: context,
      initialDate: state.params.dateFrom ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (ctx, child) => _datePickerTheme(ctx, child),
    );
    if (picked != null && mounted) {
      ref.read(kardexProvider(widget.productId).notifier).setDateFrom(picked);
    }
  }

  Future<void> _pickDateTo() async {
    final state = ref.read(kardexProvider(widget.productId));
    final picked = await showDatePicker(
      context: context,
      initialDate: state.params.dateTo ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (ctx, child) => _datePickerTheme(ctx, child),
    );
    if (picked != null && mounted) {
      ref.read(kardexProvider(widget.productId).notifier).setDateTo(picked);
    }
  }

  Widget _datePickerTheme(BuildContext ctx, Widget? child) {
    return Theme(
      data: Theme.of(ctx).copyWith(
        colorScheme: const ColorScheme.dark(
          primary: AppColors.emerald,
          onPrimary: AppColors.darkSlate,
          surface: AppColors.surface,
          onSurface: AppColors.onSurface,
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      child: child!,
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;

    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.35,
      maxChildSize: 0.92,
      snap: true,
      snapSizes: const [0.55, 0.92],
      builder: (_, __) => _buildContent(context, screenHeight),
    );
  }

  Widget _buildContent(BuildContext context, double screenHeight) {
    final state = ref.watch(kardexProvider(widget.productId));

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // ── Handle ──────────────────────────────────────────────────────
          _handle(),

          // ── Header fijo ─────────────────────────────────────────────────
          _header(state),

          // ── Panel de filtros colapsable ──────────────────────────────────────────
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeInOut,
            child: _filtersVisible
                ? _filtersPanel(state)
                : const SizedBox.shrink(),
          ),

          const Divider(height: 1, color: AppColors.border),

          // ── Cuerpo scrolleable ───────────────────────────────────────────
          Expanded(
            child: _buildBody(state),
          ),
        ],
      ),
    );
  }

  // ── Handle ────────────────────────────────────────────────────────────────

  Widget _handle() => Center(
        child: Container(
          width: 40,
          height: 4,
          margin: const EdgeInsets.only(top: 12, bottom: 8),
          decoration: BoxDecoration(
            color: AppColors.border,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      );

  // ── Header ────────────────────────────────────────────────────────────────

  Widget _header(KardexState state) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 8, 8),
      child: Row(
        children: [
          const Icon(
            Icons.history_rounded,
            size: 18,
            color: AppColors.onSurfaceMuted,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Movimientos',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.onSurface,
                  ),
                ),
                Text(
                  widget.productName,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.onSurfaceMuted,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          // Badge de filtros activos
          if (state.hasActiveFilters)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              margin: const EdgeInsets.only(right: 4),
              decoration: BoxDecoration(
                color: AppColors.emerald.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                'Filtros activos',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: AppColors.emerald,
                ),
              ),
            ),
          // Botón embudo
          IconButton(
            onPressed: () => setState(() => _filtersVisible = !_filtersVisible),
            icon: Icon(
              Icons.filter_list_rounded,
              size: 22,
              color: _filtersVisible || state.hasActiveFilters
                  ? AppColors.emerald
                  : AppColors.onSurfaceMuted,
            ),
            tooltip: 'Filtros',
          ),
        ],
      ),
    );
  }

  // ── Panel de filtros ──────────────────────────────────────────────────────

  Widget _filtersPanel(KardexState state) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      decoration: BoxDecoration(
        color: AppColors.darkSlate.withValues(alpha: 0.5),
        border: const Border(
          bottom: BorderSide(color: AppColors.border),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Filtro por tipo
          _filterRow(
            label: 'Tipo',
            child: _typeDropdown(state),
          ),
          const SizedBox(height: 8),
          // Filtros de fecha
          Row(
            children: [
              Expanded(
                child: _filterRow(
                  label: 'Desde',
                  child: _datePicker(
                    value: state.params.dateFrom,
                    hint: 'Cualquier fecha',
                    onTap: _pickDateFrom,
                    onClear: () => ref
                        .read(kardexProvider(widget.productId).notifier)
                        .setDateFrom(null),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _filterRow(
                  label: 'Hasta',
                  child: _datePicker(
                    value: state.params.dateTo,
                    hint: 'Hoy',
                    onTap: _pickDateTo,
                    onClear: () => ref
                        .read(kardexProvider(widget.productId).notifier)
                        .setDateTo(null),
                  ),
                ),
              ),
            ],
          ),
          if (state.hasActiveFilters) ...[
            const SizedBox(height: 10),
            TextButton.icon(
              onPressed: () => ref
                  .read(kardexProvider(widget.productId).notifier)
                  .clearFilters(),
              icon: const Icon(Icons.clear_all_rounded, size: 16),
              label: const Text('Limpiar filtros'),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.error,
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _filterRow({required String label, required Widget child}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: AppColors.onSurfaceMuted,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 4),
        child,
      ],
    );
  }

  Widget _typeDropdown(KardexState state) {
    const allTypes = MovementType.values;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          value: state.params.movementType,
          isExpanded: true,
          dropdownColor: AppColors.surface,
          style: const TextStyle(
            fontSize: 12,
            color: AppColors.onSurface,
          ),
          hint: const Text(
            'Todos los tipos',
            style: TextStyle(fontSize: 12, color: AppColors.onSurfaceMuted),
          ),
          icon: const Icon(
            Icons.expand_more_rounded,
            size: 16,
            color: AppColors.onSurfaceMuted,
          ),
          items: [
            const DropdownMenuItem<String?>(
              value: null,
              child: Text(
                'Todos los tipos',
                style: TextStyle(fontSize: 12),
              ),
            ),
            ...allTypes.map(
              (t) => DropdownMenuItem<String?>(
                value: t.apiCode,
                child: Row(
                  children: [
                    Icon(t.icon, size: 14, color: t.color),
                    const SizedBox(width: 6),
                    Text(t.label, style: const TextStyle(fontSize: 12)),
                  ],
                ),
              ),
            ),
          ],
          onChanged: (v) => ref
              .read(kardexProvider(widget.productId).notifier)
              .setMovementTypeFilter(v),
        ),
      ),
    );
  }

  Widget _datePicker({
    required DateTime? value,
    required String hint,
    required VoidCallback onTap,
    required VoidCallback onClear,
  }) {
    final label = value != null
        ? '${value.day.toString().padLeft(2, '0')}/'
            '${value.month.toString().padLeft(2, '0')}/'
            '${value.year}'
        : hint;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: value != null
                      ? AppColors.onSurface
                      : AppColors.onSurfaceMuted,
                ),
              ),
            ),
            if (value != null)
              GestureDetector(
                onTap: onClear,
                child: const Icon(
                  Icons.close_rounded,
                  size: 14,
                  color: AppColors.onSurfaceMuted,
                ),
              )
            else
              const Icon(
                Icons.calendar_today_rounded,
                size: 13,
                color: AppColors.onSurfaceMuted,
              ),
          ],
        ),
      ),
    );
  }

  // ── Cuerpo principal ──────────────────────────────────────────────────────

  Widget _buildBody(KardexState state) {
    if (state.isLoading) return _buildSkeleton();

    if (state.hasError) {
      return _buildErrorState(state.error!);
    }

    if (!state.hasMovements) {
      return _buildEmptyState(state.hasActiveFilters);
    }

    return _buildList(state);
  }

  // ── Lista de movimientos ──────────────────────────────────────────────────

  Widget _buildList(KardexState state) {
    return ListView.separated(
      controller: _scrollController,
      padding: const EdgeInsets.only(bottom: 32),
      itemCount: state.movements.length + (state.isLoadingMore ? 1 : 0),
      separatorBuilder: (_, __) => const Divider(
        height: 1,
        indent: 56,
        endIndent: 16,
        color: AppColors.border,
      ),
      itemBuilder: (ctx, index) {
        if (index == state.movements.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
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
        return _MovementTile(movement: state.movements[index]);
      },
    );
  }

  // ── Skeleton ──────────────────────────────────────────────────────────────

  Widget _buildSkeleton() {
    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: 6,
      separatorBuilder: (_, __) => const Divider(
        height: 1,
        indent: 56,
        endIndent: 16,
        color: AppColors.border,
      ),
      itemBuilder: (_, __) => const _MovementTileSkeleton(),
    );
  }

  // ── Empty state ───────────────────────────────────────────────────────────

  Widget _buildEmptyState(bool hasFilters) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              hasFilters
                  ? Icons.filter_list_off_rounded
                  : Icons.history_rounded,
              size: 48,
              color: AppColors.onSurfaceMuted,
            ),
            const SizedBox(height: 12),
            Text(
              hasFilters
                  ? 'Sin movimientos en\neste período'
                  : 'Aún no hay movimientos\nregistrados',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: AppColors.onSurfaceMuted,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Error state ───────────────────────────────────────────────────────────

  Widget _buildErrorState(String error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cloud_off_rounded,
              size: 48,
              color: AppColors.onSurfaceMuted,
            ),
            const SizedBox(height: 12),
            const Text(
              'No se pudo cargar\nel historial',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: AppColors.onSurface,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () =>
                  ref.read(kardexProvider(widget.productId).notifier).retry(),
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tile individual de movimiento
// ---------------------------------------------------------------------------

class _MovementTile extends StatelessWidget {
  const _MovementTile({required this.movement});

  final InventoryMovement movement;

  @override
  Widget build(BuildContext context) {
    final type = movement.movementType;
    final isPositive = movement.quantity >= 0;
    final quantityStr =
        isPositive ? '+${movement.quantity}' : '${movement.quantity}';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Ícono de tipo
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: type.color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(type.icon, size: 18, color: type.color),
          ),
          const SizedBox(width: 12),

          // Info central
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Tipo + cantidad
                Row(
                  children: [
                    Text(
                      type.label,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.onSurface,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      quantityStr,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: type.color,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                // Notas / referencia
                if (movement.notes != null)
                  Text(
                    movement.notes!,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.onSurfaceMuted,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                const SizedBox(height: 4),
                // Stock antes → después + fecha
                Row(
                  children: [
                    Text(
                      '${movement.stockBefore} → ${movement.stockAfter} pzs',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.onSurfaceMuted,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      _formatDate(movement.createdAt),
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.onSurfaceMuted,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final date = DateTime(dt.year, dt.month, dt.day);
    final time =
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

    if (date == today) return 'Hoy $time';
    if (date == yesterday) return 'Ayer $time';
    return '${dt.day.toString().padLeft(2, '0')}/'
        '${dt.month.toString().padLeft(2, '0')} $time';
  }
}

// ---------------------------------------------------------------------------
// Skeleton tile
// ---------------------------------------------------------------------------

class _MovementTileSkeleton extends StatefulWidget {
  const _MovementTileSkeleton();

  @override
  State<_MovementTileSkeleton> createState() => _MovementTileSkeletonState();
}

class _MovementTileSkeletonState extends State<_MovementTileSkeleton>
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
      builder: (_, __) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            _box(36, 36, radius: 8),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _box(13, 120),
                      const Spacer(),
                      _box(14, 40),
                    ],
                  ),
                  const SizedBox(height: 5),
                  _box(11, 180),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      _box(11, 100),
                      const Spacer(),
                      _box(11, 60),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _box(double height, double width, {double radius = 5}) => Container(
        height: height,
        width: width,
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant.withValues(alpha: _anim.value),
          borderRadius: BorderRadius.circular(radius),
        ),
      );
}
