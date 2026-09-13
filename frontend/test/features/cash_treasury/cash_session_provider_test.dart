import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_app/features/auth/presentation/login_provider.dart';
import 'package:nexus_app/features/cash_treasury/domain/banxico_denomination.dart';
import 'package:nexus_app/features/cash_treasury/domain/cash_movement.dart';
import 'package:nexus_app/features/cash_treasury/domain/cash_session.dart';
import 'package:nexus_app/features/cash_treasury/presentation/cash_session_provider.dart';

// ---------------------------------------------------------------------------
// Helper — monta un ProviderContainer con un turno ya abierto.
//
// Se usa el `CashRepositoryMock` real (no mocktail): tanto
// `CashMovementsNotifier.build()` como `_computeExpectedCashMxn` leen los
// movimientos vía `CashRepositoryMock.movementsFor` (acceso estático directo
// — ver decisión técnica en `cash_session_provider.dart`), así que un doble
// mockeado del repositorio dejaría esa lectura desincronizada del mock
// inyectado.
// ---------------------------------------------------------------------------

Future<ProviderContainer> _makeOpenContainer() async {
  final container = ProviderContainer(
    overrides: [currentUserNameProvider.overrideWith((ref) => 'Ana García')],
  );
  addTearDown(container.dispose);
  await container.read(cashSessionProvider.notifier).ensureOpenSession();
  return container;
}

void main() {
  test('el turno abierto inicia con efectivo esperado = fondo inicial', () async {
    final container = await _makeOpenContainer();

    expect(container.read(cashMovementsProvider), isEmpty);
    expect(container.read(expectedCashMxnProvider), 500.0);
  });

  test('un depósito suma al efectivo esperado y queda primero en la lista', () async {
    final container = await _makeOpenContainer();

    await container.read(cashMovementsProvider.notifier).addMovement(
          type: CashMovementType.deposit,
          amountMxn: 100,
          description: 'Entrada de cambio',
        );

    expect(container.read(expectedCashMxnProvider), 600.0);
    final movements = container.read(cashMovementsProvider);
    expect(movements, hasLength(1));
    expect(movements.first.description, 'Entrada de cambio');
    expect(movements.first.type, CashMovementType.deposit);
  });

  test('un retiro dentro del disponible resta del efectivo esperado', () async {
    final container = await _makeOpenContainer();

    await container.read(cashMovementsProvider.notifier).addMovement(
          type: CashMovementType.withdrawal,
          amountMxn: 50,
          description: 'Pago de hielo al proveedor',
        );

    expect(container.read(expectedCashMxnProvider), 450.0);
  });

  test('un retiro que excede el efectivo disponible lanza y no registra el movimiento', () async {
    final container = await _makeOpenContainer();

    await expectLater(
      container.read(cashMovementsProvider.notifier).addMovement(
            type: CashMovementType.withdrawal,
            amountMxn: 999,
            description: 'Retiro excesivo',
          ),
      throwsException,
    );

    expect(container.read(cashMovementsProvider), isEmpty);
    expect(container.read(expectedCashMxnProvider), 500.0);
  });

  test('el movimiento más reciente se inserta primero (segundo movimiento)', () async {
    final container = await _makeOpenContainer();
    final notifier = container.read(cashMovementsProvider.notifier);

    await notifier.addMovement(
      type: CashMovementType.deposit,
      amountMxn: 20,
      description: 'Primero',
    );
    await notifier.addMovement(
      type: CashMovementType.deposit,
      amountMxn: 30,
      description: 'Segundo',
    );

    final movements = container.read(cashMovementsProvider);
    expect(movements.map((m) => m.description).toList(), ['Segundo', 'Primero']);
  });

  test('startNewSession abre un turno limpio sin movimientos del turno anterior', () async {
    final container = await _makeOpenContainer();
    await container.read(cashMovementsProvider.notifier).addMovement(
          type: CashMovementType.deposit,
          amountMxn: 20,
          description: 'Del turno anterior',
        );
    expect(container.read(cashMovementsProvider), hasLength(1));

    await container.read(cashSessionProvider.notifier).startNewSession();

    expect(container.read(cashMovementsProvider), isEmpty);
    expect(container.read(expectedCashMxnProvider), 500.0);
  });

  test('closeSession calcula expectedCashMxn incluyendo movimientos del turno', () async {
    final container = await _makeOpenContainer();
    await container.read(cashMovementsProvider.notifier).addMovement(
          type: CashMovementType.withdrawal,
          amountMxn: 100,
          description: 'Pago proveedor',
        );

    final closed = await container
        .read(cashSessionProvider.notifier)
        .closeSession(const BanxicoCount({'bills_100': 4}));

    // Fondo 500 - retiro 100 = 400 esperado; físico 400 (4 billetes de 100) → cuadre exacto.
    expect(closed.expectedCashMxn, 400.0);
    expect(closed.physicalCashMxn, 400.0);
    expect(closed.balanceResult, CashBalanceResult.exact);
  });
}
