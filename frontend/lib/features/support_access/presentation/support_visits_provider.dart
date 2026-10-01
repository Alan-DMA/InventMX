import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/secure_storage.dart';
import '../../../core/support_mode/support_mode.dart';
import '../../auth/data/auth_repository.dart';
import '../../auth/presentation/login_provider.dart';
import '../../management/presentation/management_provider.dart';
import '../data/support_access_repository.dart';
import 'support_access_screen.dart' show supportAccessRepositoryProvider;

/// Entradas de soporte a la tienda (etapa 4, P41): sólo el dueño las recibe,
/// como aviso en "Avisos" con número en el ☰. El poller de soporte las relee
/// cada minuto. En la pestaña de soporte no se piden: quien mira es soporte.
final supportVisitsProvider = FutureProvider<List<SupportVisit>>((ref) async {
  if (ref.watch(supportModeProvider) || !ref.watch(isOwnerProvider)) return const [];
  try {
    return (await ref.watch(supportAccessRepositoryProvider).status()).visits;
  } catch (_) {
    return const [];
  }
});

/// Hasta cuándo el dueño ya vio las entradas de soporte (al abrir Acceso de
/// soporte o tocar el aviso). Guardado por dueño en el teléfono: reabrir la app
/// no vuelve a anunciar lo ya visto.
final supportVisitsSeenProvider = AsyncNotifierProvider<SupportVisitsSeenNotifier, DateTime?>(
  SupportVisitsSeenNotifier.new,
);

class SupportVisitsSeenNotifier extends AsyncNotifier<DateTime?> {
  static const _key = 'nexus_support_visits_seen_at';

  String get _scopedKey => SecureStorage.scopedKey(_key, ref.read(currentUserNameProvider));

  @override
  Future<DateTime?> build() async {
    final raw = await ref.read(secureStorageProvider).read(_scopedKey);
    return raw == null ? null : DateTime.tryParse(raw);
  }

  /// Marca como vistas todas las entradas hasta ahora.
  Future<void> markSeen(DateTime now) async {
    state = AsyncData(now);
    await ref.read(secureStorageProvider).write(_scopedKey, now.toIso8601String());
  }
}

/// Entradas que el dueño aún no ha visto. `[]` mientras se sabe qué vio.
final unseenSupportVisitsProvider = Provider<List<SupportVisit>>((ref) {
  final visits = ref.watch(supportVisitsProvider).valueOrNull ?? const [];
  final seen = ref.watch(supportVisitsSeenProvider);
  if (!seen.hasValue) return const [];
  final at = seen.value;
  return visits.where((v) => v.openedAt != null && (at == null || v.openedAt!.isAfter(at))).toList();
});
