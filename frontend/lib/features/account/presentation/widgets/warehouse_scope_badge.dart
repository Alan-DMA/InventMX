import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../inventory/presentation/inventory_provider.dart'
    show warehousesProvider;
import '../../../management/presentation/management_provider.dart'
    show canViewAllWarehousesProvider;
import '../account_provider.dart';
import '../data_scope_provider.dart';

/// Leyenda del almacén donde se está operando (D22, W4).
///
/// Línea pequeña bajo el título del encabezado en Inicio, Inventario,
/// Ventas, Caja y Compras, para que nadie pierda de vista a qué almacén
/// pertenece lo que ve y lo que registra.
///
/// Con [switchable], en pantallas cuyos datos siguen el alcance
/// ([dataScopeProvider]), Dueño y Encargado ven el alcance —"Todos los
/// almacenes" o uno— y lo cambian tocándola (D28). Para los demás sigue
/// siendo informativa.
class WarehouseScopeBadge extends ConsumerWidget {
  const WarehouseScopeBadge({super.key, this.switchable = false});

  final bool switchable;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (switchable && ref.watch(canViewAllWarehousesProvider)) {
      return _ScopeSwitcher();
    }

    final warehouse = ref.watch(operatingWarehouseProvider).valueOrNull;
    if (warehouse == null) return const SizedBox.shrink();

    return Semantics(
      label: 'Operando en ${warehouse.name}',
      excludeSemantics: true,
      child: _Legend(key: const Key('warehouseScopeBadge'), text: warehouse.name),
    );
  }
}

class _ScopeSwitcher extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scope = ref.watch(dataScopeProvider);
    final options = ref.watch(warehousesProvider).valueOrNull ?? const [];
    final name = scope == null
        ? 'Todos los almacenes'
        : options.where((w) => w.id == scope).firstOrNull?.name ??
            'Todos los almacenes';

    return Semantics(
      button: true,
      label: 'Viendo $name. Cambiar almacén',
      excludeSemantics: true,
      child: InkWell(
        key: const Key('warehouseScopeSwitcher'),
        borderRadius: BorderRadius.circular(6),
        onTap: () => _pick(context, ref),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: _Legend(text: name, trailing: Icons.expand_more_rounded),
        ),
      ),
    );
  }

  Future<void> _pick(BuildContext context, WidgetRef ref) async {
    final options = ref.read(warehousesProvider).valueOrNull ?? const [];
    final current = ref.read(dataScopeProvider);

    // Un valor centinela distingue "Todos" (null) de "cerró sin elegir".
    const all = '__all__';
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surface,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Ver datos de',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.onSurfaceMuted,
                  ),
                ),
              ),
            ),
            _option(sheetContext, all, 'Todos los almacenes', current == null),
            for (final w in options)
              _option(sheetContext, w.id, w.name, current == w.id),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (picked == null) return;
    ref.read(dataScopeProvider.notifier).select(picked == all ? null : picked);
  }

  Widget _option(BuildContext context, String value, String label, bool selected) =>
      ListTile(
        key: Key('scopeOption-$value'),
        title: Text(label, style: const TextStyle(color: AppColors.onSurface)),
        trailing: selected
            ? const Icon(Icons.check_rounded, color: AppColors.emerald)
            : null,
        onTap: () => Navigator.of(context).pop(value),
      );
}

class _Legend extends StatelessWidget {
  const _Legend({super.key, required this.text, this.trailing});

  final String text;
  final IconData? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.place_outlined, size: 13, color: AppColors.onSurfaceMuted),
        const SizedBox(width: 3),
        Flexible(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: AppColors.onSurfaceMuted,
              letterSpacing: 0.2,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (trailing != null)
          Icon(trailing, size: 16, color: AppColors.onSurfaceMuted),
      ],
    );
  }
}

/// Título de encabezado con la leyenda del almacén debajo.
class ScopedAppBarTitle extends StatelessWidget {
  const ScopedAppBarTitle({super.key, required this.title, this.switchable = false});

  final Widget title;

  /// La leyenda cambia el alcance de los datos (ver [WarehouseScopeBadge]).
  final bool switchable;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        title,
        WarehouseScopeBadge(switchable: switchable),
      ],
    );
  }
}
