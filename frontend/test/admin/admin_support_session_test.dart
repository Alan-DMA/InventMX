import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_app/admin/core/admin_http.dart';
import 'package:nexus_app/admin/core/browser/open_tab.dart';
import 'package:nexus_app/admin/router/admin_routes.dart';
import 'package:nexus_app/admin/tenants/domain/tenant_models.dart';
import 'package:nexus_app/admin/tenants/presentation/support_session_dialog.dart';

import 'admin_harness.dart';
import 'fake_today.dart';

/// Panel de plataforma, etapa 4c — "Ver la tienda (sólo lectura)" (P37–P42):
/// sin permiso del dueño el botón dice por qué · motivo y "Así lo verá la
/// tienda" · el diálogo pasa a "Lista" y la pestaña se abre con un clic
/// explícito (P42) · "Abrir de nuevo" y "Terminar" en la ficha · la sesión de
/// otro operador se ve sin botones.
class _Tabs {
  final opened = <String>[];
  final pending = <_FakePending>[];

  PendingTab openPending() {
    final tab = _FakePending();
    pending.add(tab);
    return tab;
  }
}

class _FakePending implements PendingTab {
  String? url;
  bool closed = false;

  @override
  void navigate(String value) => url = value;

  @override
  void close() => closed = true;
}

void main() {
  late TestClock clock;
  late FakeTenants tenants;
  late FakeActions actions;
  late _Tabs tabs;

  const reason = 'Revisar por qué no le cuadra el inventario de refrescos';

  setUp(() {
    clock = TestClock(DateTime(2026, 9, 30, 20));
    tenants = FakeTenants()
      ..add(id: 't-luz', name: 'Abarrotes Luz')
      ..add(
        id: 't-rosy',
        name: 'Abarrotes Rosy',
        support: SupportState(accessGrantedUntil: DateTime(2026, 9, 30, 21)),
      );
    actions = FakeActions(tenants, () => clock.now);
    tabs = _Tabs();
  });

  Future<AdminTestApp> open(WidgetTester tester, String tenant) async {
    final app = await pumpAdmin(
      tester,
      clock: clock,
      store: signedInStore(clock),
      tenants: tenants,
      actions: actions,
      overrides: [
        openTabProvider.overrideWithValue(tabs.opened.add),
        openPendingTabProvider.overrideWithValue(tabs.openPending),
      ],
    );
    app.go('${AdminRoutes.today}?tienda=$tenant');
    await tester.pumpAndSettle();
    return app;
  }

  Future<void> tap(WidgetTester tester, String key) async {
    await tester.ensureVisible(find.byKey(Key(key)));
    await tester.tap(find.byKey(Key(key)));
    await tester.pumpAndSettle();
  }

  testWidgets('sin permiso del dueño: el botón está apagado y dice por qué', (tester) async {
    await open(tester, 't-luz');
    final button = tester.widget<ButtonStyleButton>(find.byKey(const Key('tenantActionViewStore')));
    expect(button.onPressed, isNull);
    expect(find.text('El dueño no ha dado acceso. Pídeselo desde su caso.'), findsOneWidget);
  });

  testWidgets('con permiso: motivo, "Así lo verá la tienda", y la pestaña se abre con un clic explícito',
      (tester) async {
    await open(tester, 't-rosy');
    expect(find.textContaining('Con el permiso del dueño, vigente hasta'), findsOneWidget);
    await tap(tester, 'tenantActionViewStore');

    expect(find.text('Ver Abarrotes Rosy (sólo lectura)'), findsOneWidget);
    expect(find.textContaining('sólo para consultar'), findsOneWidget); // vista previa del dueño
    final confirm = find.byKey(const Key('sessionConfirm'));
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull, reason: 'sin motivo no se abre');

    await tester.enterText(find.byKey(const Key('sessionReason')), reason);
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pumpAndSettle();
    await tester.tap(confirm);
    await tester.pumpAndSettle();

    // Lista: todavía no se abrió ninguna pestaña (P42)
    expect(find.byKey(const Key('sessionDialogReady')), findsOneWidget);
    expect(find.textContaining('vale hasta las 20:10'), findsOneWidget);
    expect(tabs.opened, isEmpty);
    expect(actions.calls, ['session:start:']);

    await tester.tap(find.byKey(const Key('sessionOpenStore')));
    await tester.pumpAndSettle();
    expect(tabs.opened, [supportTabUrl('codigo-1')]);
    expect(tabs.opened.single, contains('c=codigo-1'));

    // La ficha muestra mi sesión sin volver a pedirla
    expect(find.textContaining('enlace listo, sin abrir (vale hasta las 20:10)'), findsOneWidget);
    expect(find.byKey(const Key('tenantActionViewStore')), findsNothing);
  });

  testWidgets('"Más tarde" deja la sesión en la ficha; "Abrir de nuevo" abre la pestaña dentro del clic',
      (tester) async {
    await open(tester, 't-rosy');
    await tap(tester, 'tenantActionViewStore');
    await tester.enterText(find.byKey(const Key('sessionReason')), reason);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sessionConfirm')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sessionLater')));
    await tester.pumpAndSettle();
    expect(tabs.opened, isEmpty);

    await tap(tester, 'tenantSessionReopen');
    expect(tabs.pending, hasLength(1));
    expect(tabs.pending.single.url, supportTabUrl('codigo-2'));
    expect(actions.calls.last, 'session:link:s1');

    // Si el servidor dice que ya terminó, la pestaña en blanco se cierra y se explica
    actions.failNext = const AdminApiException('Esta sesión ya terminó. Abre una nueva con su motivo.', statusCode: 401);
    await tap(tester, 'tenantSessionReopen');
    expect(tabs.pending.last.closed, isTrue);
    expect(find.text('Esta sesión ya terminó. Abre una nueva con su motivo.'), findsOneWidget);
    expect(find.byKey(const Key('tenantActionViewStore')), findsOneWidget);
  });

  testWidgets('Terminar la quita de la ficha', (tester) async {
    await open(tester, 't-rosy');
    await tap(tester, 'tenantActionViewStore');
    await tester.enterText(find.byKey(const Key('sessionReason')), reason);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sessionConfirm')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sessionLater')));
    await tester.pumpAndSettle();

    await tap(tester, 'tenantSessionEnd');
    expect(actions.calls.last, 'session:end:s1');
    expect(find.byKey(const Key('tenantSessionMine')), findsNothing);
    expect(find.byKey(const Key('tenantActionViewStore')), findsOneWidget);
  });

  testWidgets('la sesión de otro operador se ve, sin botones', (tester) async {
    tenants.add(
      id: 't-mar',
      name: 'Miscelánea Mar',
      support: SupportState(
        accessGrantedUntil: DateTime(2026, 9, 30, 23),
        sessions: [
          SupportSessionInfo(
            id: 'x1',
            operatorId: 'op-alan',
            operatorName: 'Alan',
            reason: 'Ver por qué no salen las ventas',
            waiting: false,
            openedAt: DateTime(2026, 9, 30, 19, 50),
            expiresAt: DateTime(2026, 9, 30, 20, 20),
          ),
        ],
      ),
    );
    await open(tester, 't-mar');
    expect(find.text('Alan está viendo la tienda (sólo lectura) · quedan 20 min.'), findsOneWidget);
    expect(find.byKey(const Key('tenantSessionReopen')), findsNothing);
    // Yo puedo abrir la mía (una por operador)
    expect(find.byKey(const Key('tenantActionViewStore')), findsOneWidget);
  });

  testWidgets('un rechazo del servidor se explica dentro del diálogo', (tester) async {
    await open(tester, 't-rosy');
    await tap(tester, 'tenantActionViewStore');
    await tester.enterText(find.byKey(const Key('sessionReason')), reason);
    await tester.pumpAndSettle();
    actions.failNext = const AdminApiException(
      'El dueño no ha dado acceso de soporte, o ya venció. Pídeselo desde su caso.',
      statusCode: 409,
    );
    await tester.tap(find.byKey(const Key('sessionConfirm')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('sessionError')), findsOneWidget);
    expect(find.textContaining('ya venció'), findsOneWidget);
    expect(find.byKey(const Key('sessionDialog')), findsOneWidget, reason: 'sigue en el formulario');
  });
}
