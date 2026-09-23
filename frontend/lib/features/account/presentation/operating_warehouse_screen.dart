import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../management/domain/warehouse.dart';
import '../../management/presentation/management_provider.dart'
    show canManageStoreProvider;
import 'account_provider.dart';

/// "Dónde opero" — en qué almacén se registran mis ventas y movimientos.
///
/// Es configuración personal, no administración: elegir dónde trabajo es
/// distinto de crear o dar de baja los almacenes del negocio (eso vive en
/// Preferencias operativas). Cambiarlo exige `settings.manage_store` (D15):
/// a un cajero se lo asigna quien administra la tienda, desde Usuarios.
class OperatingWarehouseScreen extends ConsumerWidget {
  const OperatingWarehouseScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(operatingWarehouseProvider);
    final warehouses =
        ref.watch(operatingWarehouseOptionsProvider).valueOrNull ?? const [];
    final canChange = ref.watch(canManageStoreProvider);

    return Scaffold(
      backgroundColor: AppColors.darkSlate,
      appBar: AppBar(
        backgroundColor: AppColors.darkSlate,
        title: const Text('Dónde opero'),
      ),
      body: current.isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.emerald))
          : ListView(
              padding: EdgeInsets.fromLTRB(
                  16, 16, 16, 32 + MediaQuery.of(context).padding.bottom),
              children: [
                Text(
                  canChange
                      ? 'Tus ventas, ajustes y traslados se registran en el '
                          'almacén que elijas aquí.'
                      : 'Tus ventas, ajustes y traslados se registran en este '
                          'almacén.',
                  style: const TextStyle(
                      fontSize: 13,
                      height: 1.4,
                      color: AppColors.onSurfaceMuted),
                ),
                const SizedBox(height: 20),
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Material(
                    type: MaterialType.transparency,
                    child: Column(
                      children: [
                        for (var i = 0; i < warehouses.length; i++) ...[
                          if (i > 0)
                            const Divider(
                                height: 1,
                                thickness: 1,
                                color: AppColors.border),
                          _WarehouseOption(
                            warehouse: warehouses[i],
                            isCurrent:
                                warehouses[i].id == current.valueOrNull?.id,
                            enabled: canChange,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                // Fail-closed: sin el permiso no se ofrece el cambio, y se
                // dice por qué en vez de dejar una lista muerta.
                if (!canChange) ...[
                  const SizedBox(height: 14),
                  const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline_rounded,
                          size: 15, color: AppColors.onSurfaceMuted),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Te lo asigna quien administra la tienda.',
                          key: Key('warehouseLockedHint'),
                          style: TextStyle(
                              fontSize: 12, color: AppColors.onSurfaceMuted),
                        ),
                      ),
                    ],
                  ),
                ],
                if (canChange) ...[
                  const SizedBox(height: 20),
                  TextButton.icon(
                    key: const Key('warehouseManageLink'),
                    onPressed: () => context.push(AppRoutes.warehouses),
                    icon: const Icon(Icons.tune_rounded,
                        size: 18, color: AppColors.skyBlue),
                    label: const Text(
                      'Administrar los almacenes del negocio',
                      style:
                          TextStyle(color: AppColors.skyBlue, fontSize: 13.5),
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}

class _WarehouseOption extends ConsumerWidget {
  const _WarehouseOption({
    required this.warehouse,
    required this.isCurrent,
    required this.enabled,
  });

  final Warehouse warehouse;
  final bool isCurrent;
  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      key: Key('warehouseOption-${warehouse.id}'),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      leading: Icon(
        Icons.warehouse_outlined,
        size: 21,
        color: isCurrent ? AppColors.emerald : AppColors.onSurfaceMuted,
      ),
      title: Text(
        warehouse.name,
        style: TextStyle(
          fontSize: 15,
          fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
          color: enabled || isCurrent
              ? AppColors.onSurface
              : AppColors.onSurfaceMuted,
        ),
      ),
      trailing: isCurrent
          ? const Icon(Icons.check_circle_rounded,
              size: 20, color: AppColors.emerald)
          : null,
      onTap: enabled && !isCurrent
          ? () async {
              final messenger = ScaffoldMessenger.of(context);
              await ref
                  .read(operatingWarehouseProvider.notifier)
                  .select(warehouse);
              messenger.showSnackBar(
                SnackBar(content: Text('Ahora operas en ${warehouse.name}.')),
              );
            }
          : null,
    );
  }
}
