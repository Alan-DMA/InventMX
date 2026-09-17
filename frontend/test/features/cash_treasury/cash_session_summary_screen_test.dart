import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_app/core/theme/app_theme.dart';
import 'package:nexus_app/features/auth/presentation/login_provider.dart';
import 'package:nexus_app/features/cash_treasury/data/cash_repository.dart';
import 'package:nexus_app/features/cash_treasury/domain/banxico_denomination.dart';
import 'package:nexus_app/features/cash_treasury/domain/cash_denomination_entry.dart';
import 'package:nexus_app/features/cash_treasury/domain/cash_movement.dart';
import 'package:nexus_app/features/cash_treasury/domain/cash_session.dart';
import 'package:nexus_app/features/cash_treasury/presentation/cash_session_provider.dart';
import 'package:nexus_app/features/cash_treasury/presentation/cash_session_summary_screen.dart';

CashSession _closedSession({
  required double openingAmountMxn,
  required double expectedCashMxn,
  required double physicalCashMxn,
}) {
  final differenceMxn = physicalCashMxn - expectedCashMxn;
  final balanceResult = differenceMxn.abs() < 0.005
      ? CashBalanceResult.exact
      : (differenceMxn < 0 ? CashBalanceResult.short : CashBalanceResult.over);

  return CashSession(
    id: 'cash-test-1',
    cashierName: 'Ana García',
    status: CashSessionStatus.closed,
    openingAmountMxn: openingAmountMxn,
    expectedCashMxn: expectedCashMxn,
    physicalCashMxn: physicalCashMxn,
    differenceMxn: differenceMxn,
    balanceResult: balanceResult,
    openedAt: DateTime(2026, 9, 15, 8, 0),
    closedAt: DateTime(2026, 9, 15, 20, 0),
  );
}

/// Monta la pantalla de resumen apilada sobre una ruta placeholder — permite
/// verificar que "Nuevo turno" hace `pop()` de regreso a esa ruta.
Widget _buildApp(CashSession session, {List<CashMovement> movements = const []}) {
  return ProviderScope(
    overrides: [
      currentUserNameProvider.overrideWith((ref) => 'Ana García'),
      cashRepositoryProvider.overrideWith((ref) => CashRepositoryMock()),
    ],
    child: MaterialApp(
      theme: AppTheme.dark,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => CashSessionSummaryScreen(
                    session: session,
                    physicalEntries: const [
                      CashDenominationEntry(
                        denomination: BanxicoDenomination(
                          value: 100,
                          kind: DenominationKind.bill,
                          apiKey: 'bills_100',
                        ),
                        quantity: 5,
                      ),
                    ],
                    digitalTotals: const {},
                    movements: movements,
                  ),
                ),
              ),
              child: const Text('Ir al resumen'),
            ),
          ),
        ),
      ),
    ),
  );
}

void _setPhoneViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(412 * 3, 915 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets('cuadre exacto muestra el semáforo verde y el ticket Corte Z', (tester) async {
    _setPhoneViewport(tester);
    final session = _closedSession(openingAmountMxn: 500, expectedCashMxn: 500, physicalCashMxn: 500);

    await tester.pumpWidget(_buildApp(session));
    await tester.tap(find.text('Ir al resumen'));
    await tester.pumpAndSettle();

    expect(find.text('Resultado del Cierre'), findsOneWidget);
    expect(find.text('Cuadre exacto'), findsWidgets); // banner + ticket
    expect(find.text('Ticket Corte Z'), findsOneWidget);
  });

  testWidgets('faltante muestra la etiqueta Faltante', (tester) async {
    _setPhoneViewport(tester);
    final session = _closedSession(openingAmountMxn: 500, expectedCashMxn: 500, physicalCashMxn: 480);

    await tester.pumpWidget(_buildApp(session));
    await tester.tap(find.text('Ir al resumen'));
    await tester.pumpAndSettle();

    expect(find.text('Faltante'), findsWidgets);
    // El banner grande añade el sufijo " MXN" — el ticket no — por eso se
    // distingue de la fila equivalente dentro del ticket Corte Z.
    expect(find.textContaining('-\$20.00 MXN'), findsOneWidget);
  });

  testWidgets('sobrante muestra la etiqueta Sobrante', (tester) async {
    _setPhoneViewport(tester);
    final session = _closedSession(openingAmountMxn: 500, expectedCashMxn: 500, physicalCashMxn: 530);

    await tester.pumpWidget(_buildApp(session));
    await tester.tap(find.text('Ir al resumen'));
    await tester.pumpAndSettle();

    expect(find.text('Sobrante'), findsWidgets);
    expect(find.textContaining('+\$30.00 MXN'), findsOneWidget);
  });

  testWidgets('muestra los movimientos del turno cuando existen', (tester) async {
    _setPhoneViewport(tester);
    final session = _closedSession(openingAmountMxn: 500, expectedCashMxn: 450, physicalCashMxn: 450);
    final movements = [
      CashMovement(
        id: 'mov-1',
        cashSessionId: session.id,
        type: CashMovementType.withdrawal,
        amountMxn: 50,
        description: 'Pago de hielo al proveedor',
        createdAt: DateTime(2026, 9, 15, 12, 0),
      ),
    ];

    await tester.pumpWidget(_buildApp(session, movements: movements));
    await tester.tap(find.text('Ir al resumen'));
    await tester.pumpAndSettle();

    expect(find.text('Pago de hielo al proveedor'), findsWidgets); // resumen + ticket
  });

  testWidgets('"Imprimir" muestra el blocker informativo', (tester) async {
    _setPhoneViewport(tester);
    final session = _closedSession(openingAmountMxn: 500, expectedCashMxn: 500, physicalCashMxn: 500);

    await tester.pumpWidget(_buildApp(session));
    await tester.tap(find.text('Ir al resumen'));
    await tester.pumpAndSettle();

    final printButton = find.widgetWithText(OutlinedButton, 'Imprimir');
    await tester.ensureVisible(printButton);
    await tester.pumpAndSettle();
    await tester.tap(printButton);
    await tester.pump();

    expect(find.textContaining('Impresión térmica y PDF disponibles'), findsOneWidget);
  });

  testWidgets('"Nuevo turno" abre un turno limpio y regresa a la pantalla anterior',
      (tester) async {
    _setPhoneViewport(tester);
    final session = _closedSession(openingAmountMxn: 500, expectedCashMxn: 500, physicalCashMxn: 500);

    await tester.pumpWidget(_buildApp(session));
    await tester.tap(find.text('Ir al resumen'));
    await tester.pumpAndSettle();

    final newSessionButton = find.widgetWithText(ElevatedButton, 'Nuevo turno');
    await tester.ensureVisible(newSessionButton);
    await tester.pumpAndSettle();
    await tester.tap(newSessionButton);
    await tester.pumpAndSettle();

    expect(find.text('Resultado del Cierre'), findsNothing);
    expect(find.text('Ir al resumen'), findsOneWidget);
  });
}
