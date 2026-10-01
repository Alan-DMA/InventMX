import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_app/admin/router/admin_routes.dart';
import 'package:nexus_app/admin/session/admin_session.dart';
import 'package:nexus_app/admin/today/domain/today_models.dart';

import 'admin_harness.dart';
import 'fake_cases.dart';
import 'fake_today.dart';

/// Panel de plataforma, etapa 3c — Hoy. Criterios: CA-S3c.1 requiere atención
/// con "te toca" primero y "Todo en orden" vacío · CA-S3c.2 días en la hora del
/// equipo y "Ver días anteriores" sin huecos ni repetidos · CA-S3c.3 Ctrl K
/// desde cualquier sección · CA-S3c.4 ficha sólo con metadatos, Esc, F5 y
/// sesión vencida · CA-S3c.5 ingreso "Sin conectar a Google Play aún".
void main() {
  late TestClock clock;
  late FakeToday today;
  late FakeTenants tenants;
  late FakeCases cases;

  setUp(() {
    clock = TestClock(DateTime(2026, 9, 30, 20)); // miércoles, hora local
    today = FakeToday();
    tenants = FakeTenants()..add(id: 't-luz', name: 'Abarrotes Luz');
    cases = FakeCases(clock);
  });

  Future<AdminTestApp> open(WidgetTester tester,
      {String path = AdminRoutes.today, Size size = const Size(1440, 900)}) async {
    final app = await pumpAdmin(
      tester,
      clock: clock,
      store: signedInStore(clock),
      size: size,
      cases: cases,
      today: today,
      tenants: tenants,
    );
    app.go(path);
    await tester.pumpAndSettle();
    return app;
  }

  AttentionItem item(String kind,
          {String? tenantId, String? refId, bool you = false, int hoursAgo = 2, String summary = 'Algo'}) =>
      AttentionItem(
        kind: kind,
        tenantId: tenantId,
        tenantName: 'Abarrotes Luz',
        since: clock.now.subtract(Duration(hours: hoursAgo)),
        summary: summary,
        refId: refId,
        awaitingYou: you,
      );

  testWidgets('sin pendientes: "Todo en orden", "Sin movimientos hoy" y los conteos escritos', (tester) async {
    await open(tester);
    expect(find.byKey(const Key('todayAllClear')), findsOneWidget);
    expect(find.text('Sin movimientos hoy.'), findsOneWidget);
    expect(find.text('Hoy · miércoles 30 sep'), findsOneWidget);
    expect(find.byKey(const Key('todayMetrics')), findsOneWidget);
    expect(find.text('212'), findsOneWidget);
    expect(find.text('Sin conectar a Google Play aún'), findsOneWidget);
  });

  testWidgets('requiere atención: lo que te toca primero; cada renglón lleva a su lugar', (tester) async {
    cases.add(id: 'c1', number: 1038, hoursAgo: 30);
    today.attention
      ..add(item('CASE_WAITING', refId: 'c1', hoursAgo: 30, summary: 'Caso 1038 · Algo no funciona: espera respuesta'))
      ..add(item('DELETION_PENDING', tenantId: 't-luz', you: true, hoursAgo: 1, summary: 'Eliminar Abarrotes Luz'));
    final app = await open(tester);

    final keys = tester
        .widgetList<InkWell>(find.byWidgetPredicate((w) => w is InkWell && '${w.key}'.contains('todayAttention_')))
        .map((w) => '${w.key}')
        .toList();
    expect(keys.first, contains('DELETION_PENDING')); // te toca, aunque sea más reciente
    expect(find.byKey(const Key('todayAwaitingYou')), findsOneWidget);
    expect(find.text('Requiere atención (2)'), findsOneWidget);

    await tester.tap(find.textContaining('Caso 1038'));
    await tester.pumpAndSettle();
    expect(app.location, AdminRoutes.casePath('c1'));

    app.go(AdminRoutes.today);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Eliminar Abarrotes Luz'));
    await tester.pumpAndSettle();
    expect(app.location, '${AdminRoutes.today}?tienda=t-luz');
    expect(find.byKey(const Key('tenantSheet')), findsOneWidget);
  });

  testWidgets('los días se agrupan en la hora del equipo y "Ver días anteriores" no deja huecos', (tester) async {
    today.events
      ..add(FeedEvent(kind: 'AUDIT', occurredAt: DateTime(2026, 9, 30, 0, 10), summary: 'Pasó a las 00:10 de hoy'))
      ..add(FeedEvent(
          kind: 'SIGNUP',
          occurredAt: DateTime(2026, 9, 29, 23, 50),
          summary: 'Pasó a las 23:50 de ayer',
          tenantId: 't-luz',
          reason: 'Motivo escrito'))
      ..add(FeedEvent(kind: 'AUDIT', occurredAt: DateTime(2026, 9, 26, 12), summary: 'Pasó el sábado 26'));
    await open(tester);

    // Rango inicial: hoy y dos días antes, desde medianoche local
    expect(today.ranges.first.$1, DateTime(2026, 9, 28));
    Offset y(String text) => tester.getTopLeft(find.text(text));
    expect(y('Hoy · miércoles 30 sep').dy, lessThan(y('Pasó a las 00:10 de hoy').dy));
    expect(y('Pasó a las 00:10 de hoy').dy, lessThan(y('Ayer · martes 29 sep').dy));
    expect(y('Ayer · martes 29 sep').dy, lessThan(y('Pasó a las 23:50 de ayer').dy));
    expect(find.text('"Motivo escrito"'), findsOneWidget);
    expect(find.text('Pasó el sábado 26'), findsNothing);

    await tester.scrollUntilVisible(find.byKey(const Key('todayEarlier')), 300,
        scrollable: find.descendant(of: find.byKey(const Key('todayList')), matching: find.byType(Scrollable)));
    await tester.tap(find.byKey(const Key('todayEarlier')));
    await tester.pumpAndSettle();
    // El rango siguiente empieza justo donde terminó el anterior
    expect(today.ranges[1], (DateTime(2026, 9, 25), DateTime(2026, 9, 28)));
    expect(find.text('Pasó el sábado 26'), findsOneWidget);
    expect(find.text('Sábado 26 sep'), findsOneWidget);

    await tester.scrollUntilVisible(find.byKey(const Key('todayEarlier')), 300,
        scrollable: find.descendant(of: find.byKey(const Key('todayList')), matching: find.byType(Scrollable)));
    await tester.tap(find.byKey(const Key('todayEarlier')));
    await tester.pumpAndSettle();
    expect(today.ranges[2], (DateTime(2026, 9, 22), DateTime(2026, 9, 25)));
    expect(find.text('Sin movimientos del martes 22 sep al jueves 24 sep.'), findsOneWidget);
  });

  testWidgets('Ctrl K desde Casos: buscar, Enter abre la ficha; Esc la cierra', (tester) async {
    tenants.add(id: 't-paty', name: 'Miscelánea Paty', ownerEmail: 'paty@tienda.mx');
    final app = await open(tester, path: AdminRoutes.cases);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('storeSearchDialog')), findsOneWidget);

    await tester.enterText(find.byKey(const Key('storeSearchField')), 'p');
    await tester.pump();
    expect(find.text('Escribe al menos 2 letras.'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('storeSearchField')), 'zzz');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.textContaining('Sin resultados'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('storeSearchField')), 'paty@');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('storeResult_t-paty')), findsOneWidget);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(app.location, '${AdminRoutes.cases}?tienda=t-paty');
    expect(find.text('Miscelánea Paty'), findsWidgets);
    expect(tenants.views, 1); // abrirla queda en la bitácora (una lectura)

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('tenantSheet')), findsNothing);
    expect(app.location, AdminRoutes.cases);
  });

  testWidgets('la ficha: sólo metadatos, sus casos y su actividad en palabras', (tester) async {
    cases.add(id: 'c1', number: 1042, hoursAgo: 3);
    tenants.add(id: 't-c1', name: 'Abarrotes Luz'); // la tienda del caso de prueba
    await open(tester, path: '${AdminRoutes.today}?tienda=t-c1');

    final status = tester.widget<Text>(find.byKey(const Key('tenantSheetStatus'))).textSpan!.toPlainText();
    expect(status, contains('Activa'));
    expect(status, contains('Plan Comercio'));
    expect(find.text('Vigente hasta 27 oct 2026'), findsOneWidget);
    expect(find.text('Sin conectar a Google Play aún · periodo de prueba'), findsOneWidget);
    expect(find.text('Encendido'), findsOneWidget); // catálogo web
    expect(find.textContaining('Almacén Principal · principal'), findsOneWidget);
    expect(find.textContaining('Doña Sol · Dueño · sol@tiendita.mx'), findsOneWidget); // rol en palabras
    await tester.scrollUntilVisible(find.byKey(const Key('tenantCase_c1')), 300,
        scrollable: find.descendant(of: find.byKey(const Key('tenantSheetBody')), matching: find.byType(Scrollable)));
    // La actividad va al final (la ficha creció con la sesión de soporte, etapa 4)
    await tester.scrollUntilVisible(find.text('Eduardo regaló 7 días a Abarrotes Luz'), 300,
        scrollable: find.descendant(of: find.byKey(const Key('tenantSheetBody')), matching: find.byType(Scrollable)));
    expect(find.text('Eduardo regaló 7 días a Abarrotes Luz'), findsOneWidget);
    expect(find.textContaining('"Compensación por la falla del cierre de turno"'), findsOneWidget);
  });

  testWidgets('suspendida por soporte: el motivo en la ficha', (tester) async {
    tenants.add(
        id: 't-x', name: 'Tienda X', status: 'HARD_LOCK', lockReason: 'ABUSE', suspensionReason: 'Pedidos falsos');
    await open(tester, path: '${AdminRoutes.today}?tienda=t-x');
    expect(find.text('Suspendida por soporte: Pedidos falsos'), findsOneWidget);
  });

  testWidgets('la ficha sobrevive al vencimiento de la sesión', (tester) async {
    final app = await open(tester, path: '${AdminRoutes.today}?tienda=t-luz');
    expect(find.byKey(const Key('tenantSheet')), findsOneWidget);
    app.container.read(adminSessionProvider.notifier).expire();
    await tester.pumpAndSettle();
    expect(app.location, startsWith(AdminRoutes.access));
    await signIn(tester);
    expect(app.location, '${AdminRoutes.today}?tienda=t-luz');
    expect(find.byKey(const Key('tenantSheet')), findsOneWidget);
  });

  testWidgets('una tienda que ya no existe lo dice', (tester) async {
    await open(tester, path: '${AdminRoutes.today}?tienda=nada');
    expect(find.text('Esta tienda ya no existe.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('tenantSheetClose')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('tenantSheet')), findsNothing);
  });

  testWidgets('desde un caso: "Ver ficha de la tienda" abre la ficha encima', (tester) async {
    cases.add(id: 'c1', number: 1042, hoursAgo: 3);
    tenants.add(id: 't-c1', name: 'Abarrotes Luz');
    final app = await open(tester, path: AdminRoutes.casePath('c1'));
    await tester.tap(find.byKey(const Key('caseOpenStore')));
    await tester.pumpAndSettle();
    expect(app.location, '${AdminRoutes.casePath('c1')}?tienda=t-c1');
    expect(find.byKey(const Key('tenantSheet')), findsOneWidget);
  });

  testWidgets('sin red: mensaje y Reintentar', (tester) async {
    today.failFeed = true;
    await open(tester);
    expect(find.textContaining('Sin conexión con el servidor'), findsOneWidget);
    today.failFeed = false;
    await tester.tap(find.byKey(const Key('casesRetry')).first);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('todayAllClear')), findsOneWidget);
  });

  testWidgets('pantalla chica: conteos debajo y ficha a pantalla completa', (tester) async {
    await open(tester, path: '${AdminRoutes.today}?tienda=t-luz', size: const Size(420, 860));
    expect(tester.getSize(find.byKey(const Key('tenantSheet'))).width, 420);
    await tester.tap(find.byKey(const Key('tenantSheetClose')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byKey(const Key('todayMetrics')), 400,
        scrollable: find.descendant(of: find.byKey(const Key('todayList')), matching: find.byType(Scrollable)));
    expect(find.byKey(const Key('todayMetrics')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
