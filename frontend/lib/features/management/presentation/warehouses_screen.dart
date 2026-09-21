import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../domain/warehouse.dart';
import 'management_provider.dart';
import 'widgets/management_tile.dart';
import 'widgets/warehouse_form_modal.dart';

/// Gestión → Almacenes (N-02 / PD-04 / W-01).
///
/// Es la fuente de la lista que el selector de Perfil y, más adelante, el
/// modal de traslados consumen — por eso la baja de un almacén está protegida
/// (no se puede dejar al comercio sin ninguno activo).
class WarehousesScreen extends ConsumerWidget {
  const WarehousesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final warehouses = ref.watch(warehousesProvider);

    return Scaffold(
      backgroundColor: AppColors.darkSlate,
      appBar: AppBar(
        backgroundColor: AppColors.darkSlate,
        title: const Text('Almacenes'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('warehouseAddFab'),
        heroTag: 'fab-warehouse-add',
        onPressed: () => showWarehouseFormModal(context),
        backgroundColor: AppColors.emerald,
        foregroundColor: AppColors.darkSlate,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Nuevo almacén'),
      ),
      body: warehouses.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.emerald)),
        error: (e, _) => _ErrorState(message: e.toString()),
        data: (items) => ListView.builder(
          padding: EdgeInsets.fromLTRB(
              16, 8, 16, 96 + MediaQuery.of(context).padding.bottom),
          itemCount: items.length,
          itemBuilder: (_, i) => _WarehouseTile(warehouse: items[i]),
        ),
      ),
    );
  }
}

class _WarehouseTile extends ConsumerWidget {
  const _WarehouseTile({required this.warehouse});

  final Warehouse warehouse;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ManagementTile(
      itemKey: Key('warehouse-${warehouse.id}'),
      icon: Icons.warehouse_outlined,
      title: warehouse.name,
      subtitle: warehouse.isActive
          ? 'Disponible para ventas y traslados'
          : 'Dado de baja — ya no aparece al operar',
      dimmed: !warehouse.isActive,
      badge: warehouse.isActive ? null : 'Inactivo',
      onEdit: () => showWarehouseFormModal(context, initial: warehouse),
      onDeactivate:
          warehouse.isActive ? () => _confirmDeactivate(context, ref) : null,
    );
  }

  Future<void> _confirmDeactivate(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('¿Dar de baja este almacén?',
            style: TextStyle(color: AppColors.onSurface)),
        content: Text(
          '"${warehouse.name}" dejará de aparecer al vender, ajustar stock o '
          'trasladar mercancía. El historial se conserva.',
          style: const TextStyle(color: AppColors.onSurfaceMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            key: const Key('warehouseDeactivateConfirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Dar de baja',
                style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ref.read(warehousesProvider.notifier).deactivate(warehouse.id);
      messenger.showSnackBar(
        SnackBar(content: Text('${warehouse.name} quedó fuera de operación.')),
      );
    } catch (e) {
      // El mensaje viene armado desde el dominio (p. ej. el último almacén
      // activo), no se inventa aquí.
      messenger.showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            message.replaceFirst('Exception: ', ''),
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.onSurfaceMuted),
          ),
        ),
      );
}
