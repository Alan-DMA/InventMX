import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/settings_group.dart';
import '../../account/presentation/account_provider.dart';
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
    final maxMargin = ref.watch(maxMarginPercentProvider);

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
          // Grupo real, aparte de "Inventario" (mock por decisión de Eduardo,
          // Sep 2026): el margen máximo sí persiste contra el backend.
          SettingsGroup(
            label: 'Precios',
            rows: [
              SettingsRow(
                rowKey: const Key('preferencesMaxMargin'),
                icon: Icons.percent_rounded,
                title: 'Margen máximo sugerido',
                subtitle: maxMargin.when(
                  data: (value) =>
                      'Piso del precio máximo sugerido sin historial: ${value.toStringAsFixed(0)}%',
                  loading: () => 'Cargando…',
                  error: (_, __) => 'No se pudo cargar',
                ),
                onTap: maxMargin.hasValue
                    ? () => _showEditMarginDialog(context, ref, maxMargin.value!)
                    : () {},
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _showEditMarginDialog(
    BuildContext context,
    WidgetRef ref,
    double currentValue,
  ) async {
    final controller =
        TextEditingController(text: currentValue.toStringAsFixed(0));
    String? errorText;

    final newValue = await showDialog<double>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setState) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: const Text('Margen máximo sugerido'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Cuando un producto aún no tiene suficiente historial de '
                'ventas, el precio máximo sugerido se calcula con este '
                'margen sobre su costo.',
                style: TextStyle(fontSize: 12.5, color: AppColors.onSurfaceMuted),
              ),
              const SizedBox(height: 16),
              TextField(
                key: const Key('maxMarginField'),
                controller: controller,
                autofocus: true,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Margen (%)',
                  suffixText: '%',
                  errorText: errorText,
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancelar'),
            ),
            TextButton(
              key: const Key('saveMaxMarginButton'),
              onPressed: () {
                final parsed = double.tryParse(
                    controller.text.trim().replaceAll(',', '.'));
                if (parsed == null || parsed < 0) {
                  setState(() => errorText = 'Ingresa un número válido (≥ 0)');
                  return;
                }
                Navigator.of(dialogContext).pop(parsed);
              },
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );

    if (newValue == null || !context.mounted) return;
    await ref.read(maxMarginPercentProvider.notifier).setPercent(newValue);
  }
}
