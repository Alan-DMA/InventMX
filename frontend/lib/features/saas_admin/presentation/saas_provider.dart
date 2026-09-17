import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/data/auth_repository.dart';
import '../../auth/presentation/login_provider.dart';
import '../data/saas_repository.dart';
import '../domain/founder_metrics.dart';
import '../domain/subscription.dart';

// ---------------------------------------------------------------------------
// Repositorio — real por defecto (igual que auth); mock con
// `--dart-define=SAAS_MOCK=true` y en tests (D9).
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
// Perfil de sesión (GET /me) — se carga al abrir sesión y se limpia al cerrar.
// ---------------------------------------------------------------------------

class SaasProfileNotifier extends AsyncNotifier<SaasProfile?> {
  @override
  Future<SaasProfile?> build() async {
    final hasSession = ref.watch(sessionProvider);
    if (!hasSession) return null;
    return ref.watch(saasRepositoryProvider).getProfile();
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      if (!ref.read(sessionProvider)) return null;
      return ref.read(saasRepositoryProvider).getProfile();
    });
  }
}

final saasProfileProvider =
    AsyncNotifierProvider<SaasProfileNotifier, SaasProfile?>(
  SaasProfileNotifier.new,
);

/// D7 — puerta del panel de fundadores. `false` mientras carga o sin sesión.
final isFounderProvider = Provider<bool>((ref) {
  return ref.watch(saasProfileProvider).valueOrNull?.isFounder ?? false;
});

/// Plan Corporativo — habilita la clonación de catálogo (RF-31, Tarea 15.2.2).
/// `false` mientras carga: la entrada no aparece hasta saberlo, nunca se
/// muestra para luego negar (sin cebo de plan).
final isCorporativoPlanProvider = Provider<bool>((ref) {
  final plan = ref.watch(subscriptionProvider).valueOrNull?.plan;
  return plan?.name.toLowerCase() == 'corporativo';
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

  /// Cambia el plan; el backend recalcula la factura pendiente.
  Future<void> changePlan(String planId) async {
    final updated = await ref.read(saasRepositoryProvider).changePlan(planId);
    state = AsyncData(updated);
  }

  /// "Ya pagué" — deja el aviso en revisión y lo refleja en pantalla.
  Future<PaymentValidation> reportPayment({
    required SaasPaymentMethod method,
    required String reference,
  }) async {
    final current = state.valueOrNull;
    final invoice = current?.pendingInvoice;
    if (current == null || invoice == null) {
      throw const SaasException('No hay una factura pendiente que pagar.');
    }
    final validation = await ref.read(saasRepositoryProvider).reportPayment(
          invoiceId: invoice.id,
          method: method,
          reference: reference,
        );
    state = AsyncData(current.copyWith(pendingValidation: validation));
    return validation;
  }
}

final subscriptionProvider =
    AsyncNotifierProvider<SubscriptionNotifier, Subscription?>(
  SubscriptionNotifier.new,
);

/// Estado de morosidad que gobierna banner, guardas y redirect del router.
/// Mientras carga (o sin sesión) es `active`: nunca bloquear por un spinner.
final subscriptionStatusProvider = Provider<SubscriptionStatus>((ref) {
  final sub = ref.watch(subscriptionProvider).valueOrNull;
  if (sub != null) return sub.status;
  return ref.watch(saasProfileProvider).valueOrNull?.status ??
      SubscriptionStatus.active;
});

/// Planes disponibles (GET /plans).
final saasPlansProvider = FutureProvider<List<SaasPlan>>((ref) {
  return ref.watch(saasRepositoryProvider).getPlans();
});

/// Historial de facturas (GET /invoices).
final saasInvoicesProvider = FutureProvider<List<SubscriptionInvoice>>((ref) {
  ref.watch(subscriptionProvider); // se recarga al cambiar la suscripción
  return ref.watch(saasRepositoryProvider).getInvoices();
});

// ---------------------------------------------------------------------------
// Panel de fundadores
// ---------------------------------------------------------------------------

class FounderDashboard {
  const FounderDashboard({
    required this.metrics,
    required this.inbox,
    required this.tenants,
  });

  final FounderMetrics metrics;
  final List<ValidationInboxItem> inbox;
  final List<TenantSummary> tenants;

  FounderDashboard copyWith({
    FounderMetrics? metrics,
    List<ValidationInboxItem>? inbox,
    List<TenantSummary>? tenants,
  }) =>
      FounderDashboard(
        metrics: metrics ?? this.metrics,
        inbox: inbox ?? this.inbox,
        tenants: tenants ?? this.tenants,
      );
}

final tenantFilterProvider =
    StateProvider<TenantFilter>((_) => const TenantFilter());

class FounderDashboardNotifier extends AsyncNotifier<FounderDashboard> {
  @override
  Future<FounderDashboard> build() async {
    final repo = ref.watch(saasRepositoryProvider);
    final filter = ref.watch(tenantFilterProvider);
    final results = await Future.wait([
      repo.getFounderMetrics(),
      repo.getValidationInbox(),
      repo.getTenants(filter),
    ]);
    return FounderDashboard(
      metrics: results[0] as FounderMetrics,
      inbox: results[1] as List<ValidationInboxItem>,
      tenants: results[2] as List<TenantSummary>,
    );
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(build);
  }

  Future<void> approve(String validationId, {String? notes}) async {
    await ref
        .read(saasRepositoryProvider)
        .approveValidation(validationId, notes: notes);
    await _afterMutation();
  }

  Future<void> reject(String validationId, {required String notes}) async {
    await ref
        .read(saasRepositoryProvider)
        .rejectValidation(validationId, notes: notes);
    await _afterMutation();
  }

  Future<void> setStatus(String tenantId, SubscriptionStatus status) async {
    await ref.read(saasRepositoryProvider).setTenantStatus(tenantId, status);
    await _afterMutation();
  }

  Future<void> extendDue(String tenantId, int days) async {
    await ref.read(saasRepositoryProvider).extendDueDate(tenantId, days);
    await _afterMutation();
  }

  Future<void> _afterMutation() async {
    await refresh();
    // Si el fundador tocó su propio comercio (o el mock), la suscripción
    // del tendero debe reflejarlo sin reiniciar la app.
    ref.invalidate(subscriptionProvider);
  }
}

final founderDashboardProvider =
    AsyncNotifierProvider<FounderDashboardNotifier, FounderDashboard>(
  FounderDashboardNotifier.new,
);
