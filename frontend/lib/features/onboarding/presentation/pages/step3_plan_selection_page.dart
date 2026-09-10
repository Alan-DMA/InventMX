import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../domain/plan_option.dart';
import '../onboarding_provider.dart';
import '../widgets/plan_card.dart';

/// Paso 3 — Selección de Plan
///
/// Responsabilidad de este widget: SOLO mostrar las cards y registrar
/// la selección en el provider. La navegación (Siguiente / Omitir) la
/// maneja exclusivamente el shell (OnboardingWizardScreen).
class Step3PlanSelectionPage extends ConsumerWidget {
  const Step3PlanSelectionPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(onboardingProvider).data.selectedPlan;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 28),
          _buildHeadline(context),
          const SizedBox(height: 24),

          PlanCard(
            plan: PlanOption.emprendedor,
            isSelected: selected == PlanOption.emprendedor,
            onTap: () => ref
                .read(onboardingProvider.notifier)
                .selectPlan(PlanOption.emprendedor),
          ),
          const SizedBox(height: 12),

          PlanCard(
            plan: PlanOption.comercio,
            isSelected: selected == PlanOption.comercio,
            onTap: () => ref
                .read(onboardingProvider.notifier)
                .selectPlan(PlanOption.comercio),
          ),
          const SizedBox(height: 12),

          PlanCard(
            plan: PlanOption.corporativo,
            isSelected: selected == PlanOption.corporativo,
            onTap: () => ref
                .read(onboardingProvider.notifier)
                .selectPlan(PlanOption.corporativo),
          ),
          // Sin botón Omitir aquí — está en el footer del shell
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildHeadline(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Elige el plan ideal para ti',
          style: Theme.of(context).textTheme.headlineLarge,
        ),
        const SizedBox(height: 8),
        Text(
          'Puedes cambiarlo en cualquier momento.\nTodos los planes incluyen 14 días de prueba gratis.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppColors.onSurfaceMuted,
                height: 1.5,
              ),
        ),
      ],
    );
  }
}
