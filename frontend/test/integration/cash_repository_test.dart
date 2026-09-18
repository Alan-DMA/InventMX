import 'package:flutter_test/flutter_test.dart';
import 'package:hive_test/hive_test.dart';
import 'package:nexus_app/features/cash_treasury/data/cash_repository.dart';
import 'package:nexus_app/features/cash_treasury/domain/banxico_denomination.dart';
import 'package:nexus_app/features/cash_treasury/domain/cash_movement.dart';
import 'package:nexus_app/features/cash_treasury/domain/cash_session.dart';

import '_harness.dart';

/// Fase actual (Sep 2026) — `CashRepositoryImpl` cubre los 5 métodos del
/// contrato sin `UnimplementedError`. Nota aparte (fuera de alcance de este
/// test): `CashSessionNotifier` en la app sigue leyendo estáticos de
/// `CashRepositoryMock`/`SalesRepositoryMock` para el efectivo esperado —
/// ver bitácora, es un bug de la capa de provider, no del repositorio.
void main() {
  late bool backendUp;

  setUpAll(() async {
    await setUpTestHive();
    backendUp = await isBackendUp();
  });

  tearDownAll(() async {
    await tearDownTestHive();
  });

  group('CashRepositoryImpl — contra backend real', () {
    test(
        'openSession → getActiveSession → addMovement → listMovements → closeSession',
        () async {
      if (!backendUp) {
        markTestSkipped('Backend no disponible en $integrationBaseUrl');
        return;
      }

      final session = await signInIntegrationTenant();
      final repo = CashRepositoryImpl(client: session.client);

      // Repetible entre corridas: si quedó un turno abierto de una corrida
      // anterior (p. ej. el test se interrumpió), se cierra primero.
      final stale = await repo.getActiveSession();
      if (stale != null) {
        await repo.closeSession(
          session: stale,
          physicalDenominations: BanxicoCount.empty,
        );
      }

      final opened = await repo.openSession(
        cashierName: 'Integration Test',
        openingAmountMxn: 500.0,
      );
      expect(opened.status, CashSessionStatus.open);
      expect(opened.openingAmountMxn, 500.0);

      final active = await repo.getActiveSession();
      expect(active, isNotNull);
      expect(active!.id, opened.id);

      final movement = await repo.addMovement(
        sessionId: opened.id,
        type: CashMovementType.withdrawal,
        amountMxn: 100.0,
        description: 'Retiro de prueba de integración',
      );
      expect(movement.amountMxn, 100.0);

      final movements = await repo.listMovements(opened.id);
      expect(movements.any((m) => m.id == movement.id), isTrue);

      final closed = await repo.closeSession(
        session: opened,
        physicalDenominations: BanxicoCount.empty,
      );
      expect(closed.status, CashSessionStatus.closed);

      final afterClose = await repo.getActiveSession();
      expect(afterClose, isNull);
    });
  });
}
