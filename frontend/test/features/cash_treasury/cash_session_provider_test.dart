import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_app/features/auth/presentation/login_provider.dart';
import 'package:nexus_app/features/cash_treasury/data/cash_repository.dart';
import 'package:nexus_app/features/cash_treasury/domain/banxico_denomination.dart';
import 'package:nexus_app/features/cash_treasury/domain/cash_movement.dart';
import 'package:nexus_app/features/cash_treasury/domain/cash_session.dart';
import 'package:nexus_app/features/cash_treasury/presentation/cash_session_provider.dart';
import 'package:nexus_app/features/sales_pos/domain/payment_entry.dart';

/// Integración de Caja (Oct 2026): el turno y su esperado los manda el
/// servidor; la app retoma el turno abierto, el cajero declara su fondo y un
/// error nunca deja la pantalla cargando.

/// Falla al consultar el turno (sin red, servidor caído).
class _FailingRepo extends CashRepositoryMock {
  _FailingRepo() : super(fakeDelay: Duration.zero);

  bool fail = true;

  @override
  Future<CashSession?> getActiveSession() async {
    if (fail) throw const CashException('Sin conexión con el servidor. Verifique su red.');
    return super.getActiveSession();
  }
}

ProviderContainer _container(CashRepository repo) {
  final container = ProviderContainer(
    overrides: [
      currentUserNameProvider.overrideWith((ref) => 'Ana García'),
      cashRepositoryProvider.overrideWith((ref) => repo),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

CashSession _shift({double opening = 500, double expected = 500, CashShiftSummary? summary}) => CashSession(
      id: 'cash-server',
      cashierName: 'Ana García',
      status: CashSessionStatus.open,
      openingAmountMxn: opening,
      expectedCashMxn: expected,
      openedAt: DateTime(2026, 10, 1, 8),
      summary: summary ?? const CashShiftSummary(),
    );

Future<ProviderContainer> _openContainer() async {
  final container = _container(CashRepositoryMock(fakeDelay: Duration.zero));
  await container.read(cashSessionProvider.notifier).load();
  await container.read(cashSessionProvider.notifier).openSession(500);
  return container;
}

void main() {
  test('sin turno en el servidor: queda listo para abrir, sin cargar para siempre', () async {
    final container = _container(CashRepositoryMock(fakeDelay: Duration.zero));
    expect(container.read(cashLoadProvider).loading, isTrue);
    await container.read(cashSessionProvider.notifier).load();
    expect(container.read(cashSessionProvider), isNull);
    expect(container.read(cashLoadProvider).loading, isFalse);
    expect(container.read(cashLoadProvider).error, isNull);
  });

  test('un turno abierto en el servidor se retoma con su fondo y su esperado', () async {
    final container = _container(CashRepositoryMock(
      fakeDelay: Duration.zero,
      activeSession: _shift(opening: 600, expected: 586),
    ));
    await container.read(cashSessionProvider.notifier).load();
    final session = container.read(cashSessionProvider)!;
    expect(session.id, 'cash-server');
    expect(session.openingAmountMxn, 600);
    expect(await container.read(expectedCashMxnProvider.future), 586);
  });

  test('si no se puede consultar, se dice el error y reintentar lo resuelve', () async {
    final repo = _FailingRepo();
    final container = _container(repo);
    await container.read(cashSessionProvider.notifier).load();
    expect(container.read(cashLoadProvider).error, contains('Sin conexión'));
    expect(container.read(cashLoadProvider).loading, isFalse);

    repo.fail = false;
    await container.read(cashSessionProvider.notifier).load();
    expect(container.read(cashLoadProvider).error, isNull);
  });

  test('el cajero abre con el fondo que declara', () async {
    final container = _container(CashRepositoryMock(fakeDelay: Duration.zero));
    await container.read(cashSessionProvider.notifier).load();
    await container.read(cashSessionProvider.notifier).openSession(350.5);
    expect(container.read(cashSessionProvider)!.openingAmountMxn, 350.5);
    expect(await container.read(expectedCashMxnProvider.future), 350.5);
  });

  test('si ya había un turno abierto (doble toque, otro teléfono), se retoma en vez de fallar', () async {
    final repo = CashRepositoryMock(fakeDelay: Duration.zero, activeSession: _shift(opening: 600, expected: 600));
    final container = _container(repo);
    // La app aún no lo sabía (p. ej. se abrió desde otro teléfono)
    await container.read(cashSessionProvider.notifier).openSession(100);
    expect(container.read(cashSessionProvider)!.id, 'cash-server');
    expect(container.read(cashSessionProvider)!.openingAmountMxn, 600);
    expect(container.read(cashLoadProvider).error, isNull);
  });

  test('un depósito sube el esperado del servidor y queda primero en la lista', () async {
    final container = await _openContainer();
    await container.read(cashMovementsProvider.notifier).addMovement(
          type: CashMovementType.deposit,
          amountMxn: 100,
          description: 'Entrada de cambio',
        );
    expect(await container.read(expectedCashMxnProvider.future), 600.0);
    final movements = container.read(cashMovementsProvider);
    expect(movements.first.description, 'Entrada de cambio');
  });

  test('un retiro dentro del disponible baja el esperado', () async {
    final container = await _openContainer();
    await container.read(cashMovementsProvider.notifier).addMovement(
          type: CashMovementType.withdrawal,
          amountMxn: 50,
          description: 'Pago de hielo al proveedor',
        );
    expect(await container.read(expectedCashMxnProvider.future), 450.0);
  });

  test('un retiro mayor al efectivo no se registra', () async {
    final container = await _openContainer();
    await expectLater(
      container.read(cashMovementsProvider.notifier).addMovement(
            type: CashMovementType.withdrawal,
            amountMxn: 999,
            description: 'Retiro excesivo',
          ),
      throwsException,
    );
    expect(container.read(cashMovementsProvider), isEmpty);
    expect(await container.read(expectedCashMxnProvider.future), 500.0);
  });

  test('los digitales del turno salen del resumen del servidor', () async {
    final container = _container(CashRepositoryMock(
      fakeDelay: Duration.zero,
      activeSession: _shift(summary: const CashShiftSummary(digitalTotalsMxn: {'SPEI': 18, 'CARD_TPV': 40})),
    ));
    await container.read(cashSessionProvider.notifier).load();
    final digital = await container.read(digitalPaymentTotalsProvider.future);
    expect(digital, {PaymentMethodMxn.spei: 18.0, PaymentMethodMxn.cardTpv: 40.0});
  });

  test('cerrar usa el esperado del servidor; después no queda turno y se ofrece abrir otro', () async {
    final container = await _openContainer();
    await container.read(cashMovementsProvider.notifier).addMovement(
          type: CashMovementType.withdrawal,
          amountMxn: 100,
          description: 'Pago proveedor',
        );
    final closed = await container.read(cashSessionProvider.notifier).closeSession(
          const BanxicoCount({'bills_100': 3, 'bills_50': 1}),
          movements: container.read(cashMovementsProvider),
        );
    // 500 − 100 = 400 esperado; físico 350 → faltan 50
    expect(closed.expectedCashMxn, 400.0);
    expect(closed.differenceMxn, -50.0);
    expect(closed.balanceResult, CashBalanceResult.short);

    container.read(cashSessionProvider.notifier).startNewSession();
    expect(container.read(cashSessionProvider), isNull);
    expect(container.read(cashMovementsProvider), isEmpty);
    expect(container.read(cashLoadProvider).loading, isFalse);
  });
}
