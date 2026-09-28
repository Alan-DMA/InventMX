import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/data/auth_repository.dart';
import '../../auth/presentation/login_provider.dart';
import '../data/saas_repository.dart';
import '../domain/subscription.dart';

// ---------------------------------------------------------------------------
// Repositorio — real por defecto; mock con `--dart-define=SAAS_MOCK=true`.
// ---------------------------------------------------------------------------

const bool kSaasUseMock =
    bool.fromEnvironment('SAAS_MOCK', defaultValue: false);

/// "Hoy" para la línea del ciclo y el banner. Inyectable en tests para que
/// pantalla y mock compartan el mismo reloj (la fecha real cambia a medianoche).
final clockProvider = Provider<DateTime Function()>((_) => DateTime.now);

final saasRepositoryProvider = Provider<SaasRepository>((ref) {
  if (kSaasUseMock) {
    return SaasRepositoryMock(
      currentEmail: ref.watch(currentUserNameProvider) ?? 'demo@nexus.mx',
    );
  }
  return SaasRepositoryImpl(client: ref.watch(dioClientProvider));
});

// ---------------------------------------------------------------------------
// Suscripción del comercio (GET /subscription)
// ---------------------------------------------------------------------------

class SubscriptionNotifier extends AsyncNotifier<Subscription?> {
  @override
  Future<Subscription?> build() async {
    final hasSession = ref.watch(sessionProvider);
    if (!hasSession) return null;
    return ref.watch(saasRepositoryProvider).getSubscription();
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(() async {
      if (!ref.read(sessionProvider)) return null;
      return ref.read(saasRepositoryProvider).getSubscription();
    });
  }
}

final subscriptionProvider =
    AsyncNotifierProvider<SubscriptionNotifier, Subscription?>(
  SubscriptionNotifier.new,
);

/// Lo que soporte cambió en la suscripción, con su motivo (P8). Sólo lo pide
/// la pantalla del Dueño; se recarga cada vez que se abre.
final supportActivityProvider =
    FutureProvider.autoDispose<List<SupportActivity>>((ref) {
  return ref.watch(saasRepositoryProvider).getSupportActivity();
});

/// Estado que gobierna banner, guardas y redirect del router.
/// Mientras carga (o sin sesión) es `active`: nunca bloquear por un spinner.
final subscriptionStatusProvider = Provider<SubscriptionStatus>((ref) {
  return ref.watch(subscriptionProvider).valueOrNull?.status ??
      SubscriptionStatus.active;
});

/// Nombre del comercio en sesión (lo muestra "Datos personales").
final tenantNameProvider = Provider<String?>((ref) {
  return ref.watch(subscriptionProvider).valueOrNull?.tenantName;
});

/// Plan Corporativo — habilita la clonación de catálogo (RF-31, Tarea 15.2.2).
/// `false` mientras carga: la entrada no aparece hasta saberlo, nunca se
/// muestra para luego negar (sin cebo de plan).
final isCorporativoPlanProvider = Provider<bool>((ref) {
  return ref.watch(subscriptionProvider).valueOrNull?.plan ==
      SaasPlanId.corporativo;
});
