import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/data/auth_repository.dart' show secureStorageProvider;
import '../domain/quick_action_item.dart';

/// Clave de almacenamiento local para los accesos directos configurados por el tendero.
const String _kQuickActionsKey = 'nexus_preferred_quick_actions';

/// Notifier para gestionar la lista de acciones rápidas seleccionadas en el Dashboard.
class QuickActionsNotifier extends Notifier<List<QuickActionId>> {
  @override
  List<QuickActionId> build() {
    _loadFromStorage();
    return QuickActionDefinition.defaultSelection;
  }

  Future<void> _loadFromStorage() async {
    try {
      final storage = ref.read(secureStorageProvider);
      final raw = await storage.read(_kQuickActionsKey);
      if (raw != null && raw.trim().isNotEmpty) {
        final ids = raw
            .split(',')
            .map((s) => s.trim())
            .map((name) {
              for (final val in QuickActionId.values) {
                if (val.name == name) return val;
              }
              return null;
            })
            .whereType<QuickActionId>()
            .toList();

        if (ids.isNotEmpty) {
          state = ids.take(3).toList();
        }
      }
    } catch (_) {}
  }

  /// Guarda una nueva selección de hasta 3 acciones rápidas.
  Future<void> setActions(List<QuickActionId> newActions) async {
    final trimmed = newActions.take(3).toList();
    if (trimmed.isEmpty) return;
    state = trimmed;

    final storage = ref.read(secureStorageProvider);
    final raw = trimmed.map((a) => a.name).join(',');
    await storage.write(_kQuickActionsKey, raw);
  }

  /// Conmuta una acción en la lista (agrega o quita).
  Future<void> toggleAction(QuickActionId action) async {
    final current = List<QuickActionId>.from(state);
    if (current.contains(action)) {
      if (current.length > 1) {
        current.remove(action);
        await setActions(current);
      }
    } else {
      if (current.length < 3) {
        current.add(action);
      } else {
        // Reemplaza el último si ya hay 3
        current[2] = action;
      }
      await setActions(current);
    }
  }
}

/// Provider para observar y modificar los accesos rápidos activos en el Centro de Mando.
final quickActionsProvider =
    NotifierProvider<QuickActionsNotifier, List<QuickActionId>>(
  QuickActionsNotifier.new,
);
