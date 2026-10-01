import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_app/core/theme/app_theme.dart';
import 'package:nexus_app/features/auth/presentation/login_provider.dart';
import 'package:nexus_app/features/cash_treasury/data/cash_repository.dart';
import 'package:nexus_app/features/cash_treasury/domain/cash_session.dart';
import 'package:nexus_app/features/cash_treasury/presentation/cash_session_provider.dart';
import 'package:nexus_app/features/cash_treasury/presentation/cash_session_screen.dart';

/// Integración de Caja (Oct 2026) — CA-C1: entrar a Caja nunca se queda
/// cargando · CA-C3: el cajero declara su fondo.

class _FlakyRepo extends CashRepositoryMock {
  _FlakyRepo() : super(fakeDelay: Duration.zero);
  bool fail = true;

  @override
  Future<CashSession?> getActiveSession() async {
    if (fail) throw const CashException('Sin conexión con el servidor. Verifique su red.');
    return super.getActiveSession();
  }
}

Future<void> _pump(WidgetTester tester, CashRepository repo) async {
  tester.view.physicalSize = const Size(412 * 3, 915 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      currentUserNameProvider.overrideWith((ref) => 'Ana García'),
      cashRepositoryProvider.overrideWith((ref) => repo),
    ],
    child: MaterialApp(theme: AppTheme.dark, home: const CashSessionScreen()),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('si no se puede consultar el turno, lo dice y "Reintentar" lo resuelve (no carga infinita)', (tester) async {
    final repo = _FlakyRepo();
    await _pump(tester, repo);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('No pudimos consultar tu turno'), findsOneWidget);
    expect(find.textContaining('Sin conexión'), findsOneWidget);

    repo.fail = false;
    await tester.tap(find.byKey(const Key('cashLoadRetry')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('cashOpenShiftForm')), findsOneWidget);
  });

  testWidgets('sin turno: el cajero escribe su fondo y abre; vacío o inválido se explica', (tester) async {
    final repo = CashRepositoryMock(fakeDelay: Duration.zero);
    await _pump(tester, repo);
    expect(find.text('¿Con cuánto efectivo empiezas? Es el dinero que ya está en la caja.'), findsOneWidget);

    await tester.tap(find.byKey(const Key('cashOpenShift')));
    await tester.pump();
    expect(find.textContaining('puede ser 0'), findsOneWidget);
    expect(repo.active, isNull);

    await tester.enterText(find.byKey(const Key('cashOpeningAmount')), '0');
    await tester.tap(find.byKey(const Key('cashOpenShift')));
    await tester.pumpAndSettle();
    expect(find.text('TURNO ABIERTO'), findsOneWidget);
    expect(repo.active!.openingAmountMxn, 0);
  });

  testWidgets('un fondo inusual pide confirmar antes de abrir', (tester) async {
    final repo = CashRepositoryMock(fakeDelay: Duration.zero);
    await _pump(tester, repo);
    await tester.enterText(find.byKey(const Key('cashOpeningAmount')), '75000');
    await tester.tap(find.byKey(const Key('cashOpenShift')));
    await tester.pumpAndSettle();
    expect(find.text('¿El fondo es correcto?'), findsOneWidget);

    await tester.tap(find.text('Corregir'));
    await tester.pumpAndSettle();
    expect(repo.active, isNull);

    await tester.tap(find.byKey(const Key('cashOpenShift')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sí, abrir turno'));
    await tester.pumpAndSettle();
    expect(repo.active!.openingAmountMxn, 75000);
  });

  testWidgets('con turno abierto en el servidor, Caja lo retoma directo', (tester) async {
    final repo = CashRepositoryMock(
      fakeDelay: Duration.zero,
      activeSession: CashSession(
        id: 'cash-server',
        cashierName: 'Ana García',
        status: CashSessionStatus.open,
        openingAmountMxn: 600,
        expectedCashMxn: 586,
        openedAt: DateTime(2026, 10, 1, 8),
      ),
    );
    await _pump(tester, repo);
    expect(find.text('TURNO ABIERTO'), findsOneWidget);
    expect(find.text('\$586.00'), findsOneWidget);
    expect(find.byKey(const Key('cashOpenShiftForm')), findsNothing);
  });

  testWidgets('V1: Caja dice lo recibido y el cambio ya descontado; V4: el retiro avisa que el cambio no va ahí',
      (tester) async {
    final repo = CashRepositoryMock(
      fakeDelay: Duration.zero,
      activeSession: CashSession(
        id: 'cash-server',
        cashierName: 'Ana García',
        status: CashSessionStatus.open,
        openingAmountMxn: 500,
        expectedCashMxn: 536,
        openedAt: DateTime(2026, 10, 1, 8),
        summary: const CashShiftSummary(cashSalesMxn: 36, cashReceivedMxn: 50, changeGivenMxn: 14),
      ),
    );
    await _pump(tester, repo);
    expect(find.text('Ventas en efectivo \$36.00 · recibido \$50.00 · cambio entregado \$14.00'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Registrar'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('cashMovementChangeHint')), findsOneWidget);
  });
}
