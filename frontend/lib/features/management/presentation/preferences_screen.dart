import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/settings_group.dart';
import 'management_provider.dart';

/// "Preferencias operativas" — cómo está montado el negocio por dentro.
///
/// Scope de un solo tenant: almacenes y categorías propias, nunca de otro
/// comercio. No confundir con el panel de fundadores, que opera la plataforma.
class PreferencesScreen extends ConsumerWidget {
  const PreferencesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final warehouses = ref.watch(activeWarehousesProvider);
    final categories = ref.watch(categoriesProvider).valueOrNull;

    return Scaffold(
      backgroundColor: AppColors.darkSlate,
      appBar: AppBar(
        backgroundColor: AppColors.darkSlate,
        title: const Text('Preferencias operativas'),
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
            16, 16, 16, 32 + MediaQuery.of(context).padding.bottom),
        children: [
          const Text(
            'Lo que configuras aquí aplica a todo tu comercio.',
            style: TextStyle(fontSize: 13, color: AppColors.onSurfaceMuted),
          ),
          const SizedBox(height: 20),
          SettingsGroup(
            label: 'Inventario',
            rows: [
              SettingsRow(
                rowKey: const Key('preferencesWarehouses'),
                icon: Icons.warehouse_outlined,
                title: 'Almacenes',
                subtitle: warehouses.isEmpty
                    ? 'Dónde guardas y mueves la mercancía'
                    : '${warehouses.length} ${warehouses.length == 1 ? 'almacén activo' : 'almacenes activos'}',
                onTap: () => context.push(AppRoutes.warehouses),
              ),
              SettingsRow(
                rowKey: const Key('preferencesCategories'),
                icon: Icons.sell_outlined,
                title: 'Categorías',
                subtitle: categories == null
                    ? 'Cómo agrupas tus productos'
                    : '${categories.length} ${categories.length == 1 ? 'categoría' : 'categorías'}',
                onTap: () => context.push(AppRoutes.categories),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
