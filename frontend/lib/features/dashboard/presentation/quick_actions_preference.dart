import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/secure_storage.dart';
import '../../auth/data/auth_repository.dart' show secureStorageProvider;
import '../../auth/presentation/login_provider.dart' show currentUserNameProvider;
import '../../management/presentation/management_provider.dart';
import '../domain/quick_action_item.dart';

/// Clave de almacenamiento local para los accesos directos configurados por el tendero.
const String _kQuickActionsKey = 'nexus_preferred_quick_actions';

/// Notifier para gestionar la lista de acciones rápidas seleccionadas en el Dashboard.
class QuickActionsNotifier extends Notifier<List<QuickActionId>> {
  /// Correo de quien está en sesión. Se **observa**: al cambiar de usuario el
  /// notifier se reconstruye y carga las preferencias de quien entró, en vez
  /// de arrastrar en memoria las del anterior (QA de Eduardo, Sep 23).
  String? get _owner => ref.watch(currentUserNameProvider);

  String get _key => SecureStorage.scopedKey(_kQuickActionsKey, _owner);

  @override
  List<QuickActionId> build() {
    _loadFromStorage();
    return QuickActionDefinition.defaultSelection;
  }

  Future<void> _loadFromStorage() async {
    try {
      final storage = ref.read(secureStorageProvider);
      final raw = await storage.read(_key);
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
    await storage.write(_key, raw);
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

/// Acciones que el rol en sesión puede ejecutar, en el orden del catálogo.
final allowedQuickActionsProvider = Provider<List<QuickActionDefinition>>((ref) {
  final permissions = ref.watch(myPermissionsProvider);
  return QuickActionDefinition.catalog
      .where((a) =>
          permissions.contains(QuickActionDefinition.permissionFor(a.id)))
      .toList();
});

/// Lo que el Inicio muestra: **la selección del usuario tal cual**, quitando
/// sólo lo que su rol no puede hacer.
///
/// No se rellena hasta tres (QA de Eduardo, Sep 23): rellenar hacía que la
/// preferencia pareciera ignorada — un cajero, con sólo dos acciones
/// permitidas, veía siempre las mismas dos eligiera lo que eligiera, y se le
/// colaba "Vitrina web" justo encima de la tarjeta de Pedidos web. Si el
/// filtro deja la fila vacía sí entra la primera permitida: una sección
/// "Acciones rápidas" sin una sola acción no le sirve a nadie.
final visibleQuickActionsProvider = Provider<List<QuickActionId>>((ref) {
  final allowed = ref.watch(allowedQuickActionsProvider).map((a) => a.id);
  final chosen = ref.watch(quickActionsProvider);
  final result = chosen.where(allowed.contains).toList();
  if (result.isEmpty && allowed.isNotEmpty) result.add(allowed.first);
  return result;
});
