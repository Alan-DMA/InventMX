import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../domain/quick_action_item.dart';
import '../quick_actions_preference.dart';

/// Modal para seleccionar y personalizar los 3 accesos rápidos del Centro de Mando.
Future<void> showCustomizeActionsModal(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.surface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) => const _CustomizeActionsSheet(),
  );
}

class _CustomizeActionsSheet extends ConsumerWidget {
  const _CustomizeActionsSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Se marca y se cuenta sobre lo que el Inicio muestra de verdad (ya
    // filtrado por rol): con el state crudo el contador decía "3/3" aunque
    // en la lista sólo hubiera dos opciones (QA de Eduardo, Sep 23).
    final selected = ref.watch(visibleQuickActionsProvider);
    final catalog = ref.watch(allowedQuickActionsProvider);

    // Conmuta sobre la selección visible y la guarda: lo elegido es
    // exactamente lo que se verá, sin relleno automático.
    void toggle(QuickActionId id) {
      final next = List<QuickActionId>.from(selected);
      if (next.contains(id)) {
        if (next.length > 1) next.remove(id);
      } else if (next.length < 3) {
        next.add(id);
      } else {
        next[2] = id;
      }
      ref.read(quickActionsProvider.notifier).setActions(next);
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.onSurfaceMuted.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Personalizar Acciones Rápidas',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: AppColors.onSurface,
                        ),
                      ),
                      SizedBox(height: 3),
                      Text(
                        'Elige hasta 3 accesos directos para tu mostrador',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: AppColors.onSurfaceMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  '${selected.length}/3',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.emerald,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: catalog.length,
                separatorBuilder: (_, __) => const Divider(
                  height: 1,
                  color: AppColors.border,
                ),
                itemBuilder: (context, index) {
                  final action = catalog[index];
                  final isSelected = selected.contains(action.id);

                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: action.accentColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        action.icon,
                        color: action.accentColor,
                        size: 20,
                      ),
                    ),
                    title: Text(
                      action.title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.onSurface,
                      ),
                    ),
                    subtitle: Text(
                      action.description,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.onSurfaceMuted,
                      ),
                    ),
                    trailing: Checkbox(
                      value: isSelected,
                      activeColor: AppColors.emerald,
                      onChanged: (_) => toggle(action.id),
                    ),
                    onTap: () => toggle(action.id),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.emerald,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () => Navigator.of(context).pop(),
                child: const Text(
                  'Guardar selección',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
