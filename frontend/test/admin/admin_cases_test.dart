import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_app/admin/cases/domain/desk_case.dart';
import 'package:nexus_app/admin/core/admin_colors.dart';
import 'package:nexus_app/admin/router/admin_routes.dart';
import 'package:nexus_app/admin/session/admin_session.dart';

import 'admin_harness.dart';
import 'fake_cases.dart';

/// Los textos de espera y fechas usan espacio de no separación.
String nb(String s) => s.replaceAll(' ', '\u00A0');

/// Panel de plataforma, etapa 3b — Casos. Criterios: P31 esperando del más
/// antiguo · P32 Enviar principal, Enviar y resolver secundario, estado en ⋯ ·
/// P33 novedades sin recargar bajo los dedos · P34 borrador que sobrevive ·
/// la respuesta se ve como la leerá el tendero · CA-S3.3 (lado del panel).
void main() {
  late TestClock clock;
  late FakeCases cases;

  setUp(() {
    clock = TestClock(DateTime(2026, 9, 30, 20));
    cases = FakeCases(clock);
  });

  Future<AdminTestApp> open(WidgetTester tester,
      {String path = AdminRoutes.cases, Size size = const Size(1440, 900)}) async {
    final app = await pumpAdmin(
      tester,
      clock: clock,
      store: signedInStore(clock),
      size: size,
      cases: cases,
    );
    app.go(path);
    await tester.pumpAndSettle();
    return app;
  }

  testWidgets('la cola: esperando del más antiguo al más reciente, con cuánto espera y el contador', (tester) async {
    cases
      ..add(id: 'a', number: 1042, hoursAgo: 3, store: 'Tiendita Doña Sol')
      ..add(id: 'b', number: 1038, hoursAgo: 30, store: 'Abarrotes Luz')
      ..add(id: 'c', number: 1044, hoursAgo: 1, store: 'Miscelánea Paty')
      ..add(id: 'd', number: 1021, hoursAgo: 50, status: DeskCaseStatus.resolved);
    await open(tester);

    final rows = tester
        .widgetList<InkWell>(find.byWidgetPredicate((w) => w is InkWell && '${w.key}'.contains('casesRow_')))
        .map((w) => '${w.key}')
        .toList();
    expect(rows, ["[<'casesRow_b'>]", "[<'casesRow_a'>]", "[<'casesRow_c'>]"]);
    expect(find.text('espera ${nb('1 día')}'), findsOneWidget);
    expect(find.text('espera ${nb('3 h')}'), findsOneWidget);
    // Pasadas 24 h, en ámbar (y escrito: "espera 1 día")
    expect(tester.widget<Text>(find.byKey(const Key('casesRowWhen_b'))).style!.color, AdminColors.amber);
    expect(tester.widget<Text>(find.byKey(const Key('casesRowWhen_a'))).style!.color, isNot(AdminColors.amber));
    // Contador de la navegación y de la pestaña: sólo lo que espera
    expect(find.byKey(const Key('adminNavCasesCount')), findsOneWidget);
    expect(find.text('Esperando 3'), findsOneWidget);
    // Sin caso abierto: cuántos esperan y el más antiguo
    expect(find.text('3 casos esperan respuesta'), findsOneWidget);
    expect(find.textContaining('Caso 1038 · Abarrotes Luz · espera ${nb('1 día')}'), findsOneWidget);
  });

  testWidgets('abrir un caso: contexto de la tienda (sólo metadatos), formulario y conversación', (tester) async {
    cases.add(id: 'a', number: 1042, hoursAgo: 3, store: 'Tiendita Doña Sol');
    final app = await open(tester);
    await tester.tap(find.byKey(const Key('casesOpenOldest')));
    await tester.pumpAndSettle();

    expect(app.location, AdminRoutes.casePath('a'));
    expect(find.text('Caso 1042 · Algo no funciona'), findsOneWidget);
    final storeLine = tester.widget<Text>(find.byKey(const Key('caseStoreLine'))).textSpan!.toPlainText();
    expect(storeLine, contains('Tiendita Doña Sol'));
    expect(storeLine, contains('Activa'));
    expect(storeLine, contains('Plan Comercio'));
    expect(storeLine, contains('vigente hasta ${nb('27 oct 2026')}'));
    expect(find.textContaining('desde la app'), findsOneWidget);
    expect(find.byKey(const Key('caseAnswers')), findsOneWidget);
    expect(find.text('Caja'), findsOneWidget);
    expect(find.text('El corte de caja no cuadra.'), findsWidgets);
  });

  testWidgets('responder: Enviar agrega la respuesta firmada y la cola baja', (tester) async {
    cases
      ..add(id: 'a', number: 1042, hoursAgo: 3)
      ..add(id: 'b', number: 1043, hoursAgo: 2);
    final app = await open(tester, path: AdminRoutes.casePath('a'));

    await tester.enterText(find.byKey(const Key('caseReplyField')), 'Revisa que el turno de ayer esté cerrado.');
    await tester.pump();
    // El borrador ya está en la pestaña
    expect(app.store.read('nexus.admin.draft.a'), 'Revisa que el turno de ayer esté cerrado.');

    await tester.tap(find.byKey(const Key('caseSend')));
    await tester.pumpAndSettle();
    expect(cases.statusOf('a'), DeskCaseStatus.answered);
    expect(find.text('Respondido'), findsOneWidget);
    expect(find.text('Soporte Nexus · Eduardo Cristancho · 30 sep · 20:00'), findsOneWidget);
    expect(app.store.read('nexus.admin.draft.a'), isNull);
    // Sale de "Esperando"
    expect(find.byKey(const Key('casesRow_a')), findsNothing);
    expect(find.text('Esperando 1'), findsOneWidget);
  });

  testWidgets('si no se envía, lo dice y la respuesta sigue ahí', (tester) async {
    cases.add(id: 'a', number: 1042, hoursAgo: 3);
    final app = await open(tester, path: AdminRoutes.casePath('a'));
    cases.failNextReply = true;
    await tester.enterText(find.byKey(const Key('caseReplyField')), 'Ya lo revisamos.');
    await tester.tap(find.byKey(const Key('caseSend')));
    await tester.pumpAndSettle();

    expect(find.textContaining('No se envió'), findsOneWidget);
    expect(find.textContaining('Tu respuesta sigue aquí'), findsOneWidget);
    expect(tester.widget<TextField>(find.byKey(const Key('caseReplyField'))).controller!.text, 'Ya lo revisamos.');
    expect(app.store.read('nexus.admin.draft.a'), 'Ya lo revisamos.');
    expect(cases.statusOf('a'), DeskCaseStatus.waiting);
  });

  testWidgets('Ctrl+Enter envía; vacío no envía y lo explica', (tester) async {
    cases.add(id: 'a', number: 1042, hoursAgo: 3);
    await open(tester, path: AdminRoutes.casePath('a'));
    await tester.tap(find.byKey(const Key('caseSend')));
    await tester.pump();
    expect(find.text('Escribe la respuesta antes de enviar.'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('caseReplyField')), 'Listo, ya quedó.');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(cases.replies, 1);
  });

  testWidgets('Enviar y resolver cierra el caso; ⋯ lo reabre', (tester) async {
    cases.add(id: 'a', number: 1042, hoursAgo: 3);
    await open(tester, path: AdminRoutes.casePath('a'));
    await tester.enterText(find.byKey(const Key('caseReplyField')), 'Quedó resuelto con la actualización.');
    await tester.tap(find.byKey(const Key('caseSendResolve')));
    await tester.pumpAndSettle();
    expect(cases.statusOf('a'), DeskCaseStatus.resolved);
    expect(find.text('Resuelto'), findsOneWidget);

    await tester.tap(find.byKey(const Key('caseMenu')));
    await tester.pumpAndSettle();
    expect(find.text('Marcar como resuelto'), findsNothing);
    await tester.tap(find.byKey(const Key('caseMarkWaiting')));
    await tester.pumpAndSettle();
    expect(cases.statusOf('a'), DeskCaseStatus.waiting);
    expect(find.text('Esperando a soporte'), findsOneWidget);
  });

  testWidgets('el borrador sobrevive a cambiar de caso y al vencimiento de la sesión', (tester) async {
    cases
      ..add(id: 'a', number: 1042, hoursAgo: 3)
      ..add(id: 'b', number: 1043, hoursAgo: 2);
    final app = await open(tester, path: AdminRoutes.casePath('a'));
    await tester.enterText(find.byKey(const Key('caseReplyField')), 'A medio escribir…');
    await tester.tap(find.byKey(const Key('casesRow_b')));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byKey(const Key('caseReplyField'))).controller!.text, isEmpty);
    await tester.tap(find.byKey(const Key('casesRow_a')));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byKey(const Key('caseReplyField'))).controller!.text, 'A medio escribir…');

    // La sesión vence: al acceso y de regreso al mismo caso, con el borrador
    app.container.read(adminSessionProvider.notifier).expire();
    await tester.pumpAndSettle();
    expect(app.location, startsWith(AdminRoutes.access));
    await signIn(tester);
    expect(app.location, AdminRoutes.casePath('a'));
    expect(tester.widget<TextField>(find.byKey(const Key('caseReplyField'))).controller!.text, 'A medio escribir…');
  });

  testWidgets('mensaje nuevo mientras se lee: se ofrece "Actualizar", no cambia solo', (tester) async {
    cases.add(id: 'a', number: 1042, hoursAgo: 3);
    await open(tester, path: AdminRoutes.casePath('a'));
    clock.advance(const Duration(minutes: 2));
    cases.requesterWrites('a', 'Ya actualicé y sigue igual.');

    await tester.pump(const Duration(seconds: 61));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('caseNewMessage')), findsOneWidget);
    final inThread = find.descendant(
      of: find.byKey(const Key('caseConversation')),
      matching: find.text('Ya actualicé y sigue igual.'),
    );
    expect(inThread, findsNothing); // el hilo no cambió bajo los dedos (la cola sí lo muestra)
    await tester.tap(find.byKey(const Key('caseApplyNew')));
    await tester.pumpAndSettle();
    expect(inThread, findsOneWidget);
  });

  testWidgets('caso sin sesión: se responde por correo y la tienda es sólo una coincidencia por validar',
      (tester) async {
    cases.add(
        id: 'p',
        number: 1050,
        hoursAgo: 1,
        fromApp: false,
        store: 'Abarrotes Doña Chuy',
        topic: 'No puedo entrar a mi cuenta');
    await open(tester, path: AdminRoutes.casePath('p'));
    final storeLine = tester.widget<Text>(find.byKey(const Key('caseStoreLine'))).textSpan!.toPlainText();
    expect(storeLine, contains('Responde por correo a sol@tiendita.mx'));
    expect(storeLine, contains('(hay que validar)'));
    expect(find.textContaining('Sin sesión · Abarrotes Doña Chuy'), findsOneWidget); // en la cola
    // El campo avisa que la respuesta va por correo (sin vista previa, decisión de Eduardo)
    expect(find.text('Escribe la respuesta (le llegará por correo)'), findsOneWidget);
    expect(find.byKey(const Key('caseReaderPreview')), findsNothing);
  });

  testWidgets('suspendida por soporte se dice en la línea de la tienda', (tester) async {
    cases.add(id: 'a', number: 1042, hoursAgo: 3, storeStatus: 'HARD_LOCK', lockReason: 'ABUSE');
    await open(tester, path: AdminRoutes.casePath('a'));
    final storeLine = tester.widget<Text>(find.byKey(const Key('caseStoreLine'))).textSpan!.toPlainText();
    expect(storeLine, contains('Suspendida por soporte'));
  });

  testWidgets('J y K recorren la cola; R lleva a la respuesta', (tester) async {
    cases
      ..add(id: 'a', number: 1042, hoursAgo: 3)
      ..add(id: 'b', number: 1043, hoursAgo: 2);
    final app = await open(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
    await tester.pumpAndSettle();
    expect(app.location, AdminRoutes.casePath('a'));
    await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
    await tester.pumpAndSettle();
    expect(app.location, AdminRoutes.casePath('b'));
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.pumpAndSettle();
    expect(app.location, AdminRoutes.casePath('a'));
    await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
    await tester.pump();
    final field = tester.widget<TextField>(find.byKey(const Key('caseReplyField')));
    expect(field.focusNode!.hasFocus, isTrue);
  });

  testWidgets('pestañas, búsqueda y "Cargar más"', (tester) async {
    for (var i = 0; i < 35; i++) {
      cases.add(id: 'w$i', number: 1100 + i, hoursAgo: 40 - i);
    }
    cases.add(id: 'r1', number: 1001, hoursAgo: 60, status: DeskCaseStatus.resolved, store: 'Cremería Rosy');
    await open(tester);
    await tester.scrollUntilVisible(find.byKey(const Key('casesLoadMore')), 400,
        scrollable: find.descendant(of: find.byKey(const Key('casesList')), matching: find.byType(Scrollable)));
    expect(find.text('Cargar más (30 de 35)'), findsOneWidget);
    await tester.tap(find.byKey(const Key('casesLoadMore')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('casesLoadMore')), findsNothing);

    await tester.tap(find.byKey(const Key('casesTab_resolved')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('casesRow_r1')), findsOneWidget);

    await tester.tap(find.byKey(const Key('casesTab_waiting')));
    await tester.enterText(find.byKey(const Key('casesSearch')), '1105');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('casesRow_w5')), findsOneWidget);
    expect(find.byKey(const Key('casesRow_w6')), findsNothing);

    await tester.enterText(find.byKey(const Key('casesSearch')), 'no existe');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.text('Sin resultados'), findsOneWidget);
  });

  testWidgets('sin casos: "Todo en orden"; sin red: mensaje y Reintentar', (tester) async {
    await open(tester);
    expect(find.text('Sin casos esperando'), findsWidgets);
    expect(find.text('Todo en orden: nadie espera respuesta de soporte.'), findsWidgets);
    expect(find.byKey(const Key('adminNavCasesCount')), findsNothing);

    cases.failList = true;
    await tester.tap(find.byKey(const Key('casesTab_answered')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Sin conexión con el servidor'), findsOneWidget);
    cases
      ..failList = false
      ..add(id: 'r', number: 1042, hoursAgo: 3, status: DeskCaseStatus.answered);
    await tester.tap(find.byKey(const Key('casesRetry')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('casesRow_r')), findsOneWidget);
  });

  testWidgets('pantalla chica: la cola, luego el caso con "volver"', (tester) async {
    cases.add(id: 'a', number: 1042, hoursAgo: 3);
    final app = await open(tester, size: const Size(420, 860));
    await tester.tap(find.byKey(const Key('casesRow_a')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('casesList')), findsNothing);
    expect(find.text('Caso 1042 · Algo no funciona'), findsOneWidget);
    await tester.tap(find.byKey(const Key('caseBack')));
    await tester.pumpAndSettle();
    expect(app.location, AdminRoutes.cases);
    expect(tester.takeException(), isNull);
  });

  testWidgets('un caso que no existe lo dice', (tester) async {
    await open(tester, path: AdminRoutes.casePath('nada'));
    expect(find.text('Ese caso no existe o ya no está disponible.'), findsOneWidget);
  });
}
