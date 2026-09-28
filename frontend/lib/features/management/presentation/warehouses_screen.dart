import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../domain/warehouse.dart';
import 'management_provider.dart';
import 'widgets/management_tile.dart';
import 'widgets/warehouse_form_modal.dart';

/// Gestión → Almacenes (N-02 / PD-04 / W-01).
///
/// Contra el servidor desde Ajustes operativos (D7): la baja es lógica y el
/// servidor la rechaza con su motivo si el almacén no está vacío y sin
/// pendientes; se puede reactivar. El principal (D7b) no se da de baja hasta
/// marcar otro con "Hacer principal".
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
    final isPrincipal = warehouse.isDefault && warehouse.isActive;

    return ManagementTile(
      itemKey: Key('warehouse-${warehouse.id}'),
      icon: Icons.warehouse_outlined,
      title: warehouse.name,
      subtitle: !warehouse.isActive
          ? 'Dado de baja — ya no aparece al operar'
          : isPrincipal
              ? 'Recibe los productos nuevos y a quien no tiene almacén'
              : 'Disponible para ventas y traslados',
      dimmed: !warehouse.isActive,
      badge: !warehouse.isActive
          ? 'Inactivo'
          : isPrincipal
              ? 'Principal'
              : null,
      onEdit: () => showWarehouseFormModal(context, initial: warehouse),
      actions: [
        if (warehouse.isActive && !warehouse.isDefault)
          ManagementTileAction(
            value: 'make-default',
            label: 'Hacer principal',
            onSelected: () => _confirmMakeDefault(context, ref),
          ),
        if (!warehouse.isActive)
          ManagementTileAction(
            value: 'activate',
            label: 'Reactivar',
            onSelected: () => _activate(context, ref),
          ),
      ],
      onDeactivate:
          warehouse.isActive ? () => _confirmDeactivate(context, ref) : null,
    );
  }

  /// "Hacer principal" cambia a dónde van los productos nuevos y quien no
  /// tiene almacén asignado: se dice antes, no se descubre después (D7b).
  Future<void> _confirmMakeDefault(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('¿Hacerlo tu almacén principal?',
            style: TextStyle(color: AppColors.onSurface)),
        content: Text(
          'Los productos nuevos entrarán a "${warehouse.name}", y quien no '
          'tenga un almacén asignado operará ahí.',
          style: const TextStyle(color: AppColors.onSurfaceMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            key: const Key('warehouseMakeDefaultConfirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Hacer principal'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ref.read(warehousesProvider.notifier).makeDefault(warehouse.id);
      messenger.showSnackBar(
        SnackBar(
            content: Text('${warehouse.name} es ahora tu almacén principal.')),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  Future<void> _activate(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(warehousesProvider.notifier).activate(warehouse.id);
      messenger.showSnackBar(
        SnackBar(
            content: Text('${warehouse.name} vuelve a estar en operación.')),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  Future<void> _confirmDeactivate(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);

    // Se avisa antes de abrir el diálogo cuando ya se sabe que no se puede
    // (mismo criterio que Categorías): el principal primero se reemplaza.
    if (warehouse.isDefault) {
      messenger.showSnackBar(
        SnackBar(content: Text(const DefaultWarehouseException().message)),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('¿Dar de baja este almacén?',
            style: TextStyle(color: AppColors.onSurface)),
        content: Text(
          '"${warehouse.name}" dejará de aparecer al vender, comprar o '
          'trasladar mercancía. El historial se conserva y puedes '
          'reactivarlo cuando quieras.',
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
      // El motivo viene armado del servidor (existencias, quién opera ahí,
      // turno abierto, compras sin recibir), no se inventa aquí.
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
