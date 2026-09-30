import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/data/auth_repository.dart';
import '../../auth/presentation/login_provider.dart';
import '../data/support_repository.dart';
import '../domain/support_models.dart';

/// Real por omisión; mock con `--dart-define=SUPPORT_MOCK=true`.
const bool kSupportUseMock = bool.fromEnvironment('SUPPORT_MOCK', defaultValue: false);

final supportRepositoryProvider = Provider<SupportRepository>((ref) {
  if (kSupportUseMock) return SupportRepositoryMock();
  return SupportRepositoryImpl(client: ref.watch(dioClientProvider));
});

/// Temas para el rol en sesión (servidos por el servidor, P27).
final supportTopicsProvider = FutureProvider.autoDispose<List<HelpTopic>>(
  (ref) => ref.watch(supportRepositoryProvider).topics(),
);

/// Temas para quien no puede entrar (P24).
final publicTopicsProvider = FutureProvider.autoDispose<List<HelpTopic>>(
  (ref) => ref.watch(supportRepositoryProvider).publicTopics(),
);

/// Mis casos (el dueño: los de la tienda).
final supportCasesProvider = FutureProvider.autoDispose<List<SupportCase>>(
  (ref) => ref.watch(supportRepositoryProvider).cases(),
);

/// Un caso con su conversación. Abrirlo limpia la insignia en el servidor.
final supportCaseProvider = FutureProvider.autoDispose.family<SupportCase, String>((ref, id) async {
  final detail = await ref.watch(supportRepositoryProvider).caseDetail(id);
  ref.invalidate(supportUnreadProvider);
  return detail;
});

/// Respuestas de soporte sin abrir: la insignia del ☰ y de "Soporte". Sin
/// sesión es 0; un fallo de red también (una insignia no debe romper el menú).
final supportUnreadProvider = FutureProvider<int>((ref) async {
  if (!ref.watch(sessionProvider) || ref.watch(mustChangePasswordProvider)) return 0;
  try {
    return await ref.watch(supportRepositoryProvider).unreadCount();
  } catch (_) {
    return 0;
  }
});

/// Casos con respuesta de soporte sin abrir: los avisos de soporte en
/// "Avisos". Sale de la misma cuenta que las insignias (☰, Soporte, Mis
/// casos), así todas coinciden; sin nada pendiente ni se consulta la lista.
/// Un fallo de red deja la lista vacía: un aviso no debe romper "Avisos".
final supportRepliesProvider = FutureProvider<List<SupportCase>>((ref) async {
  final unread = await ref.watch(supportUnreadProvider.future);
  if (unread == 0) return const [];
  try {
    final cases = await ref.watch(supportRepositoryProvider).cases();
    return cases.where((c) => c.unread).toList();
  } catch (_) {
    return const [];
  }
});
