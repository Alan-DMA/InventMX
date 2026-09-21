import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../domain/category.dart';
import 'management_provider.dart';
import 'widgets/category_form_modal.dart';
import 'widgets/management_tile.dart';

/// Preferencias operativas → Categorías (N-03 / PD-03).
class CategoriesScreen extends ConsumerWidget {
  const CategoriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(categoriesProvider);

    return Scaffold(
      backgroundColor: AppColors.darkSlate,
      appBar: AppBar(
        backgroundColor: AppColors.darkSlate,
        title: const Text('Categorías'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('categoryAddFab'),
        heroTag: 'fab-category-add',
        onPressed: () => showCategoryFormModal(context),
        backgroundColor: AppColors.emerald,
        foregroundColor: AppColors.darkSlate,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Nueva categoría'),
      ),
      body: categories.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.emerald)),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Text(
              e.toString().replaceFirst('Exception: ', ''),
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.onSurfaceMuted),
            ),
          ),
        ),
        data: (items) => ListView.builder(
          padding: EdgeInsets.fromLTRB(
              16, 8, 16, 96 + MediaQuery.of(context).padding.bottom),
          itemCount: items.length,
          itemBuilder: (_, i) => _CategoryTile(category: items[i]),
        ),
      ),
    );
  }
}

class _CategoryTile extends ConsumerWidget {
  const _CategoryTile({required this.category});

  final Category category;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = category.productCount;

    return ManagementTile(
      itemKey: Key('category-${category.id}'),
      icon: Icons.sell_outlined,
      title: category.name,
      subtitle: count == 0
          ? 'Sin productos todavía'
          : '$count ${count == 1 ? 'producto' : 'productos'}',
      onEdit: () => showCategoryFormModal(context, initial: category),
      onDeactivate: () => _confirmDelete(context, ref),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);

    // Se avisa antes de abrir el diálogo cuando ya se sabe que no se puede:
    // preguntar "¿seguro?" para luego negar es hacer perder un paso.
    if (category.productCount > 0) {
      messenger.showSnackBar(
        SnackBar(
            content:
                Text(CategoryInUseException(category.productCount).message)),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('¿Eliminar esta categoría?',
            style: TextStyle(color: AppColors.onSurface)),
        content: Text(
          '"${category.name}" dejará de aparecer al dar de alta y al filtrar.',
          style: const TextStyle(color: AppColors.onSurfaceMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            key: const Key('categoryDeleteConfirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Eliminar',
                style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ref.read(categoriesProvider.notifier).remove(category.id);
      messenger.showSnackBar(
        SnackBar(content: Text('${category.name} ya no está en tu lista.')),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }
}
