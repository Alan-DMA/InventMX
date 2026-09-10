import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_colors.dart';
import 'onboarding_provider.dart';
import 'pages/step1_business_name_page.dart';
import 'pages/step2_operations_page.dart';
import 'pages/step3_plan_selection_page.dart';
import 'widgets/onboarding_progress_dots.dart';

/// Shell del wizard de onboarding.
///
/// ARQUITECTURA DE NAVEGACIÓN:
/// El PageController es la única fuente de verdad para el movimiento visual.
/// - El estado lógico (currentPage) vive en OnboardingNotifier.
/// - El shell escucha los cambios con ref.listen registrado en build()
///   usando [listen] de Riverpod que es seguro llamar en build
///   (Riverpod lo deduplica automáticamente entre rebuilds).
/// - Todo botón de navegación (Siguiente, Omitir, Atrás) llama SOLO al
///   notifier. El shell reacciona al cambio de estado y mueve el PageController.
/// - Los pasos hijos NUNCA llaman nextPage() directamente — solo notifican
///   al notifier y el shell decide el movimiento.
class OnboardingWizardScreen extends ConsumerStatefulWidget {
  const OnboardingWizardScreen({super.key});

  static const routePath = '/onboarding';

  @override
  ConsumerState<OnboardingWizardScreen> createState() =>
      _OnboardingWizardScreenState();
}

class _OnboardingWizardScreenState
    extends ConsumerState<OnboardingWizardScreen> {
  late final PageController _pageController;

  static const _subtitles = [
    'Business Info',
    'Inventory Setup',
    'Payment Methods',
    'Setup completado',
  ];

  @override
  void initState() {
    super.initState();
    final initialPage = ref.read(onboardingProvider).currentPage;
    _pageController = PageController(initialPage: initialPage);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(onboardingProvider);
    final currentPage = state.currentPage;
    const isLastPage = false;

    // ref.listen en build() es el patrón correcto en Riverpod —
    // no es un antipatrón, Riverpod garantiza que solo hay un listener activo.
    // Movemos el PageController AQUÍ para asegurar que siempre se ejecuta
    // después de que el estado ya se actualizó.
    ref.listen<OnboardingWizardState>(onboardingProvider, (prev, next) {
      if ((prev?.currentPage ?? -1) != next.currentPage) {
        // jumpToPage es instantáneo y no tiene condición de carrera
        // con el estado del widget — más confiable que animateToPage
        // cuando el salto viene desde un hijo que se desmonta.
        _pageController.jumpToPage(next.currentPage);
      }
    });

    return Scaffold(
      backgroundColor: AppColors.darkSlate,
      appBar: _buildAppBar(currentPage, isLastPage),
      body: Column(
        children: [
          if (!isLastPage)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
              child: OnboardingProgressIndicator(
                currentStep: currentPage,
                totalSteps: 3,
              ),
            ),
          Expanded(
            child: PageView(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(),
              children: const [
                Step1BusinessNamePage(),
                Step2OperationsPage(),
                Step3PlanSelectionPage(),
              ],
            ),
          ),
          if (!isLastPage) _buildFooter(state),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- AppBar

  PreferredSizeWidget _buildAppBar(int currentPage, bool isLastPage) {
    return AppBar(
      backgroundColor: AppColors.darkSlate,
      elevation: 0,
      centerTitle: true,
      leading: currentPage > 0 && !isLastPage
          ? IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded,
                  size: 20, color: AppColors.onSurface),
              onPressed: () =>
                  ref.read(onboardingProvider.notifier).previousPage(),
            )
          : const SizedBox.shrink(),
      title: Column(
        children: [
          const Text(
            'Nexus Express',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.onSurface,
            ),
          ),
          Text(
            _subtitles[currentPage],
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w400,
              color: AppColors.onSurfaceMuted,
            ),
          ),
        ],
      ),
    );
  }

  // --------------------------------------------------------------- Footer

  Widget _buildFooter(OnboardingWizardState state) {
    final isStep3 = state.currentPage == 2;
    final canProceed = _canProceed(state);

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Botón principal
            ElevatedButton(
              onPressed: canProceed ? () => _onNext(state) : null,
              child: Text(isStep3 ? 'Elegir plan  →' : 'Siguiente  →'),
            ),

            // Botón omitir — SOLO en paso 3, dentro del footer del shell
            if (isStep3) ...[
              const SizedBox(height: 8),
              TextButton(
                onPressed: _onSkipPlan,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.onSurfaceMuted,
                ),
                child: const Text(
                  'Omitir por ahora y explorar el sistema →',
                  style: TextStyle(fontSize: 13),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------ Helpers

  bool _canProceed(OnboardingWizardState state) {
    switch (state.currentPage) {
      case 0:
        return ref.read(onboardingProvider.notifier).step1Valid;
      case 1:
        return ref.read(onboardingProvider.notifier).step2Valid;
      default:
        return true;
    }
  }

  void _onNext(OnboardingWizardState state) {
    if (state.currentPage == 2) {
      context.go(AppRoutes.onboardingSuccess);
    } else {
      ref.read(onboardingProvider.notifier).nextPage();
    }
  }

  void _onSkipPlan() {
    ref.read(onboardingProvider.notifier).skipPlan();
    context.go(AppRoutes.onboardingSuccess);
  }
}