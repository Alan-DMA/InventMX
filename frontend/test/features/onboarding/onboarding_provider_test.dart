import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nexus_app/features/onboarding/data/onboarding_repository.dart';
import 'package:nexus_app/features/onboarding/domain/onboarding_state.dart';
import 'package:nexus_app/features/onboarding/domain/plan_option.dart';
import 'package:nexus_app/features/onboarding/presentation/onboarding_provider.dart';

// ---------------------------------------------------------------------------
// Mock y Fake
// ---------------------------------------------------------------------------

class MockOnboardingRepository extends Mock implements OnboardingRepository {}

/// Fake requerido por mocktail para usar any() con OnboardingData.
/// Misma causa que en auth_interceptor_test con RequestOptions.
class FakeOnboardingData extends Fake implements OnboardingData {}

// ---------------------------------------------------------------------------
// Helper: ProviderContainer con repo mockeado
// ---------------------------------------------------------------------------

ProviderContainer _buildContainer(OnboardingRepository repo) {
  return ProviderContainer(
    overrides: [onboardingRepositoryProvider.overrideWithValue(repo)],
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // Registrar fallback ANTES de cualquier setUp o test
  setUpAll(() {
    registerFallbackValue(FakeOnboardingData());
  });

  late MockOnboardingRepository mockRepo;
  late ProviderContainer container;

  setUp(() {
    mockRepo = MockOnboardingRepository();
    when(() => mockRepo.load()).thenAnswer((_) async => const OnboardingData());
    when(() => mockRepo.save(any())).thenAnswer((_) async {});
    container = _buildContainer(mockRepo);
  });

  tearDown(() => container.dispose());

  // ---------- Paso 1 ----------

  group('step1 — nombre de la tienda', () {
    test('estado inicial: businessName vacío, step1Valid false', () {
      final notifier = container.read(onboardingProvider.notifier);
      expect(container.read(onboardingProvider).data.businessName, '');
      expect(notifier.step1Valid, isFalse);
    });

    test('setBusinessName con 1 char: step1Valid sigue false', () {
      final notifier = container.read(onboardingProvider.notifier);
      notifier.setBusinessName('A');
      expect(notifier.step1Valid, isFalse);
    });

    test('setBusinessName con 2+ chars: step1Valid es true', () {
      final notifier = container.read(onboardingProvider.notifier);
      notifier.setBusinessName('Mi Tienda');
      expect(notifier.step1Valid, isTrue);
      expect(
        container.read(onboardingProvider).data.businessName,
        'Mi Tienda',
      );
    });

    test('setBusinessName con espacios al inicio/fin: se hace trim', () {
      final notifier = container.read(onboardingProvider.notifier);
      notifier.setBusinessName('  Abarrotes  ');
      expect(
        container.read(onboardingProvider).data.businessName,
        'Abarrotes',
      );
    });
  });

  // ---------- Paso 2 ----------

  group('step2 — operaciones', () {
    test('step2Valid siempre true', () {
      final notifier = container.read(onboardingProvider.notifier);
      expect(notifier.step2Valid, isTrue);
    });

    test('setWarehouseName vacío usa default "Almacén Principal"', () {
      final notifier = container.read(onboardingProvider.notifier);
      notifier.setWarehouseName('');
      expect(
        container.read(onboardingProvider).data.warehouseName,
        'Almacén Principal',
      );
    });

    test('setWarehouseName con valor usa ese valor', () {
      final notifier = container.read(onboardingProvider.notifier);
      notifier.setWarehouseName('Bodega Central');
      expect(
        container.read(onboardingProvider).data.warehouseName,
        'Bodega Central',
      );
    });

    test('setTicketHeader persiste el valor', () {
      final notifier = container.read(onboardingProvider.notifier);
      notifier.setTicketHeader('¡Gracias por su compra!');
      expect(
        container.read(onboardingProvider).data.ticketHeader,
        '¡Gracias por su compra!',
      );
    });
  });

  // ---------- Paso 3 ----------

  group('step3 — selección de plan', () {
    test('selectPlan(comercio) actualiza el estado', () {
      final notifier = container.read(onboardingProvider.notifier);
      notifier.selectPlan(PlanOption.comercio);
      expect(
        container.read(onboardingProvider).data.selectedPlan,
        PlanOption.comercio,
      );
    });

    test('skipPlan asigna PlanOption.skipped', () {
      final notifier = container.read(onboardingProvider.notifier);
      notifier.skipPlan();
      expect(
        container.read(onboardingProvider).data.selectedPlan,
        PlanOption.skipped,
      );
    });
  });

  // ---------- Navegación ----------

  group('navegación entre páginas', () {
    test('currentPage inicial es 0', () {
      expect(container.read(onboardingProvider).currentPage, 0);
    });

    test('nextPage incrementa currentPage', () {
      container.read(onboardingProvider.notifier).nextPage();
      expect(container.read(onboardingProvider).currentPage, 1);
    });

    test('previousPage decrementa currentPage', () {
      final notifier = container.read(onboardingProvider.notifier);
      notifier.nextPage();
      notifier.nextPage();
      notifier.previousPage();
      expect(container.read(onboardingProvider).currentPage, 1);
    });

    test('previousPage no baja de 0', () {
      container.read(onboardingProvider.notifier).previousPage();
      expect(container.read(onboardingProvider).currentPage, 0);
    });

    test('nextPage no sube más allá de 3', () {
      final notifier = container.read(onboardingProvider.notifier);
      for (var i = 0; i < 10; i++) {
        notifier.nextPage();
      }
      expect(container.read(onboardingProvider).currentPage, 3);
    });

    test('isFirstPage true en página 0', () {
      expect(
        container.read(onboardingProvider.notifier).isFirstPage,
        isTrue,
      );
    });

    test('isLastPage true en página 3', () {
      final notifier = container.read(onboardingProvider.notifier);
      notifier.goToPage(3);
      expect(notifier.isLastPage, isTrue);
    });
  });

  // ---------- Bug Condition — Navegación atómica desde Paso 3 ----------
  // Validates: Requirements 1.1, 1.2, 1.3, 2.1, 2.2, 2.3
  // Verifica que skipPlanAndAdvance() emite UN ÚNICO estado atómico
  // con currentPage = 3 y selectedPlan = skipped desde currentPage = 2.

  group('bug condition — skipPlanAndAdvance() desde currentPage = 2', () {
    test(
      'skipPlanAndAdvance() produce currentPage = 3 y selectedPlan = skipped '
      'en una única emisión atómica',
      () {
        final notifier = container.read(onboardingProvider.notifier);
        // Avanzar hasta el Paso 3 (currentPage = 2)
        notifier.nextPage(); // 0 → 1
        notifier.nextPage(); // 1 → 2
        expect(container.read(onboardingProvider).currentPage, 2,
            reason: 'precondición: debemos estar en currentPage = 2');

        // Capturar todos los estados emitidos
        final emittedStates = <OnboardingWizardState>[];
        final sub = container.listen<OnboardingWizardState>(
          onboardingProvider,
          (_, next) => emittedStates.add(next),
        );

        // Fix: una única llamada atómica (reemplaza skipPlan() + nextPage())
        notifier.skipPlanAndAdvance();

        sub.close();

        final finalState = container.read(onboardingProvider);

        // Property 1 (Fix): debe emitir exactamente 1 estado atómico
        expect(
          emittedStates.length,
          1,
          reason:
              'skipPlanAndAdvance() debe emitir exactamente 1 estado atómico, '
              'no 2 emisiones intermedias como skipPlan() + nextPage()',
        );
        expect(
          finalState.currentPage,
          3,
          reason: 'currentPage debe ser 3 tras skipPlanAndAdvance()',
        );
        expect(
          finalState.data.selectedPlan,
          PlanOption.skipped,
          reason: 'selectedPlan debe ser PlanOption.skipped',
        );
        expect(emittedStates.single.currentPage, 3);
        expect(emittedStates.single.data.selectedPlan, PlanOption.skipped);
      },
    );

    test(
      'skipPlanAndAdvance() no afecta otros campos del estado '
      '(no-interferencia)',
      () {
        final notifier = container.read(onboardingProvider.notifier);
        notifier.setBusinessName('Tienda Test');
        notifier.setWarehouseName('Bodega A');
        notifier.goToPage(2);

        notifier.skipPlanAndAdvance();

        final state = container.read(onboardingProvider);
        expect(state.data.businessName, 'Tienda Test',
            reason: 'businessName no debe cambiar');
        expect(state.data.warehouseName, 'Bodega A',
            reason: 'warehouseName no debe cambiar');
        expect(state.isSaving, isFalse, reason: 'isSaving no debe cambiar');
      },
    );
  });

  // ---------- Preservation — Navegación en Pasos 1, 2 y botón Atrás ----------
  // Validates: Requirements 3.1, 3.2, 3.3, 3.4, 3.5, 3.6
  // Estos tests deben pasar tanto ANTES como DESPUÉS del fix.

  group('preservation — nextPage() en páginas 0, 1, 2', () {
    test('nextPage() desde currentPage = 0 produce currentPage = 1', () {
      final notifier = container.read(onboardingProvider.notifier);
      expect(container.read(onboardingProvider).currentPage, 0);
      notifier.nextPage();
      expect(container.read(onboardingProvider).currentPage, 1);
    });

    test('nextPage() desde currentPage = 1 produce currentPage = 2', () {
      final notifier = container.read(onboardingProvider.notifier);
      notifier.goToPage(1);
      notifier.nextPage();
      expect(container.read(onboardingProvider).currentPage, 2);
    });

    test('nextPage() desde currentPage = 2 produce currentPage = 3', () {
      final notifier = container.read(onboardingProvider.notifier);
      notifier.goToPage(2);
      notifier.nextPage();
      expect(container.read(onboardingProvider).currentPage, 3);
    });
  });

  group('preservation — previousPage() en páginas 1, 2, 3', () {
    test('previousPage() desde currentPage = 1 produce currentPage = 0', () {
      final notifier = container.read(onboardingProvider.notifier);
      notifier.goToPage(1);
      notifier.previousPage();
      expect(container.read(onboardingProvider).currentPage, 0);
    });

    test('previousPage() desde currentPage = 2 produce currentPage = 1', () {
      final notifier = container.read(onboardingProvider.notifier);
      notifier.goToPage(2);
      notifier.previousPage();
      expect(container.read(onboardingProvider).currentPage, 1);
    });

    test('previousPage() desde currentPage = 3 produce currentPage = 2', () {
      final notifier = container.read(onboardingProvider.notifier);
      notifier.goToPage(3);
      notifier.previousPage();
      expect(container.read(onboardingProvider).currentPage, 2);
    });
  });

  group('preservation — step1Valid según longitud de businessName', () {
    test('step1Valid = false cuando businessName tiene 0 chars', () {
      expect(container.read(onboardingProvider.notifier).step1Valid, isFalse);
    });

    test('step1Valid = false cuando businessName tiene 1 char', () {
      container.read(onboardingProvider.notifier).setBusinessName('X');
      expect(container.read(onboardingProvider.notifier).step1Valid, isFalse);
    });

    test('step1Valid = true cuando businessName tiene 2+ chars', () {
      container.read(onboardingProvider.notifier).setBusinessName('AB');
      expect(container.read(onboardingProvider.notifier).step1Valid, isTrue);
    });
  });

  // ---------- Completar onboarding ----------

  group('completeOnboarding', () {
    test(
        'persiste isCompleted=true en repo y actualiza onboardingCompleteProvider',
        () async {
      final notifier = container.read(onboardingProvider.notifier);
      notifier.setBusinessName('Don Pepe');

      await notifier.completeOnboarding();

      final captured = verify(() => mockRepo.save(captureAny())).captured;
      expect(captured.length, 1);
      expect((captured.first as OnboardingData).isCompleted, isTrue);
      expect(container.read(onboardingCompleteProvider), isTrue);
    });

    test('isSaving es false después de completar', () async {
      await container.read(onboardingProvider.notifier).completeOnboarding();
      expect(container.read(onboardingProvider).isSaving, isFalse);
    });
  });
}
