import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/onboarding_repository.dart';
import '../domain/onboarding_state.dart';
import '../domain/plan_option.dart';

// ---------------------------------------------------------------------------
// Estado del wizard (página activa + datos del formulario)
// ---------------------------------------------------------------------------

class OnboardingWizardState {
  const OnboardingWizardState({
    this.currentPage = 0,
    this.data = const OnboardingData(),
    this.isSaving = false,
  });

  final int currentPage;
  final OnboardingData data;
  final bool isSaving;

  OnboardingWizardState copyWith({
    int? currentPage,
    OnboardingData? data,
    bool? isSaving,
  }) {
    return OnboardingWizardState(
      currentPage: currentPage ?? this.currentPage,
      data: data ?? this.data,
      isSaving: isSaving ?? this.isSaving,
    );
  }
}

// ---------------------------------------------------------------------------
// Notifier
// ---------------------------------------------------------------------------

class OnboardingNotifier extends Notifier<OnboardingWizardState> {
  @override
  OnboardingWizardState build() => const OnboardingWizardState();

  // ---------- Paso 1 ----------

  void setBusinessName(String value) {
    state = state.copyWith(
      data: state.data.copyWith(businessName: value.trim()),
    );
  }

  void setLogoPath(String? path) {
    state = state.copyWith(
      data: state.data.copyWith(logoPath: path),
    );
  }

  /// Paso 1 válido cuando el nombre tiene al menos 2 caracteres.
  bool get step1Valid => state.data.businessName.trim().length >= 2;

  // ---------- Paso 2 ----------

  void setWarehouseName(String value) {
    state = state.copyWith(
      data: state.data.copyWith(
        warehouseName:
            value.trim().isEmpty ? 'Almacén Principal' : value.trim(),
      ),
    );
  }

  void setTicketHeader(String value) {
    state = state.copyWith(
      data: state.data.copyWith(ticketHeader: value),
    );
  }

  /// Paso 2 siempre válido (campos opcionales con defaults).
  bool get step2Valid => true;

  // ---------- Paso 3 ----------

  void selectPlan(PlanOption plan) {
    state = state.copyWith(
      data: state.data.copyWith(selectedPlan: plan),
    );
  }

  void skipPlan() {
    state = state.copyWith(
      data: state.data.copyWith(selectedPlan: PlanOption.skipped),
    );
  }

  /// Atómico: registra PlanOption.skipped Y avanza a la página 3 en una sola emisión.
  /// Reemplaza la doble llamada skipPlan() + nextPage() desde el shell.
  void skipPlanAndAdvance() {
    state = state.copyWith(
      data: state.data.copyWith(selectedPlan: PlanOption.skipped),
      currentPage: 3,
    );
  }

  // ---------- Navegación ----------

  void goToPage(int page) {
    state = state.copyWith(currentPage: page);
  }

  void nextPage() {
    if (state.currentPage < 3) {
      state = state.copyWith(currentPage: state.currentPage + 1);
    }
  }

  void previousPage() {
    if (state.currentPage > 0) {
      state = state.copyWith(currentPage: state.currentPage - 1);
    }
  }

  bool get isFirstPage => state.currentPage == 0;
  bool get isLastPage => state.currentPage == 3;

  // ---------- Completar onboarding ----------

  Future<void> completeOnboarding() async {
    state = state.copyWith(isSaving: true);

    final completed = state.data.copyWith(isCompleted: true);
    final repo = ref.read(onboardingRepositoryProvider);
    await repo.save(completed);

    state = state.copyWith(data: completed, isSaving: false);

    // Notifica al provider de estado de onboarding para que el router reaccione
    ref.read(onboardingCompleteProvider.notifier).state = true;
  }
}

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------

final onboardingProvider =
    NotifierProvider<OnboardingNotifier, OnboardingWizardState>(
  OnboardingNotifier.new,
);

/// FutureProvider que verifica Hive al iniciar — alimenta el redirect del router.
final onboardingInitProvider = FutureProvider<bool>((ref) async {
  final repo = ref.read(onboardingRepositoryProvider);
  final data = await repo.load();
  // Si ya estaba completo, sincroniza el StateProvider
  if (data.isCompleted) {
    ref.read(onboardingCompleteProvider.notifier).state = true;
  }
  return data.isCompleted;
});

/// StateProvider<bool> — fuente de verdad reactiva para GoRouter.
/// Se actualiza tanto desde onboardingInitProvider (arranque)
/// como desde OnboardingNotifier.completeOnboarding().
final onboardingCompleteProvider = StateProvider<bool>((ref) => false);
