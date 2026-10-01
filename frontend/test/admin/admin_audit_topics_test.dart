import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_app/admin/audit/domain/audit_models.dart';
import 'package:nexus_app/admin/core/admin_http.dart';
import 'package:nexus_app/admin/router/admin_routes.dart';

import 'admin_harness.dart';
import 'fake_audit.dart';
import 'fake_today.dart';

/// Panel de plataforma, etapa 3e — Bitácora y Temas de ayuda. Criterios: la
/// bitácora filtra por tipo, tienda y "mis acciones", sin el ruido por omisión ·
/// la cadena rota se ve en todo el panel (y no se confunde con "no se pudo
/// verificar") · editar un tema exige motivo, se ve como lo verá el tendero,
/// conserva botones y formulario (P29) y no pierde cambios sin avisar.
void main() {
  late TestClock clock;
  late FakeAudit audit;
  late FakeTopics topics;
  late FakeTenants tenants;

  setUp(() {
    clock = TestClock(DateTime(2026, 9, 30, 20));
    audit = FakeAudit();
    topics = FakeTopics();
    tenants = FakeTenants()..add(id: 't-luz', name: 'Abarrotes Luz');
  });

  Future<AdminTestApp> open(WidgetTester tester, String path, {Size size = const Size(1440, 900)}) async {
    final app = await pumpAdmin(
      tester,
      clock: clock,
      store: signedInStore(clock),
      size: size,
      audit: audit,
      topics: topics,
      tenants: tenants,
    );
    app.go(path);
    await tester.pumpAndSettle();
    return app;
  }

  AuditEntry entry(int id, String action, String summary, {String? tenant, String? reason, int minutesAgo = 10}) =>
      AuditEntry(
        id: id,
        occurredAt: clock.now.subtract(Duration(minutes: minutesAgo)),
        action: action,
        summary: summary,
        operatorName: 'Eduardo',
        targetTenantId: tenant,
        reason: reason,
        ipAddress: '10.0.0.7',
      );

  group('Bitácora', () {
    setUp(() {
      audit.entries.addAll([
        entry(1, 'DAYS_GIFTED', 'Eduardo regaló 7 días a Abarrotes Luz',
            tenant: 't-luz', reason: 'Compensación', minutesAgo: 5),
        entry(2, 'TENANT_VIEWED', 'Eduardo abrió la ficha de Abarrotes Luz', tenant: 't-luz', minutesAgo: 6),
        entry(3, 'LOGIN_FAILED', 'Acceso fallido al panel', minutesAgo: 30),
        entry(4, 'ABUSE_SUSPENDED', 'Alan suspendió Tienda X por abuso',
            tenant: 't-x', reason: 'Pedidos falsos', minutesAgo: 60),
      ]);
      audit.operatorOf.addAll({1: 'op-me', 2: 'op-me', 3: 'op-me', 4: 'op-alan'});
    });

    testWidgets('en palabras, con motivo, sin el ruido por omisión; verifica la integridad al abrir', (tester) async {
      await open(tester, AdminRoutes.audit);
      expect(find.text('Eduardo regaló 7 días a Abarrotes Luz'), findsOneWidget);
      expect(find.text('"Compensación"'), findsOneWidget);
      expect(find.text('Eduardo abrió la ficha de Abarrotes Luz'), findsNothing); // ruido oculto
      expect(audit.queries.first['noise'], isFalse);
      expect(audit.verifications, 1);
      expect(find.text('Íntegra: 42 registros verificados.'), findsOneWidget);

      await tester.tap(find.byKey(const Key('auditShowNoise')));
      await tester.pumpAndSettle();
      expect(find.text('Eduardo abrió la ficha de Abarrotes Luz'), findsOneWidget);
    });

    testWidgets('filtros: tipo de acción, "Sólo mis acciones" y vacío con salida', (tester) async {
      await open(tester, AdminRoutes.audit);
      await tester.tap(find.byKey(const Key('auditActionFilter')));
      await tester.pumpAndSettle();
      expect(find.text('Acciones sobre tiendas'), findsOneWidget); // grupos en palabras
      await tester.tap(find.byKey(const Key('auditAction_ABUSE_SUSPENDED')));
      await tester.pumpAndSettle();
      expect(find.text('Alan suspendió Tienda X por abuso'), findsOneWidget);
      expect(find.text('Eduardo regaló 7 días a Abarrotes Luz'), findsNothing);
      expect(find.text('Suspendió por abuso'), findsOneWidget); // el botón dice el filtro

      await tester.tap(find.byKey(const Key('auditOnlyMine')));
      await tester.pumpAndSettle();
      expect(audit.queries.last['operator'], 'op-me');
      expect(find.text('Sin registros con este filtro.'), findsOneWidget);
      await tester.tap(find.byKey(const Key('auditClearFilters')));
      await tester.pumpAndSettle();
      expect(find.text('Alan suspendió Tienda X por abuso'), findsOneWidget);
    });

    testWidgets('filtro por tienda con el buscador; un renglón abre su ficha', (tester) async {
      final app = await open(tester, AdminRoutes.audit);
      await tester.tap(find.byKey(const Key('auditTenantFilter')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('storeSearchField')), 'luz');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('storeResult_t-luz')));
      await tester.pumpAndSettle();
      expect(audit.queries.last['tenant'], 't-luz');
      expect(find.text('Tienda: Abarrotes Luz'), findsOneWidget);
      expect(find.text('Alan suspendió Tienda X por abuso'), findsNothing);

      await tester.tap(find.byKey(const Key('auditEntry_1')));
      await tester.pumpAndSettle();
      expect(app.location, '${AdminRoutes.audit}?tienda=t-luz');
    });

    testWidgets('cadena rota: alerta roja fija en todo el panel', (tester) async {
      audit.chain = const ChainVerification(intact: false, checked: 42, brokenAtId: 17);
      final app = await open(tester, AdminRoutes.audit);
      expect(find.textContaining('Alterada fuera del panel a partir del registro #17'), findsOneWidget);
      expect(find.byKey(const Key('adminChainBroken')), findsOneWidget);
      app.go(AdminRoutes.today);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('adminChainBroken')), findsOneWidget); // sigue en otra sección
    });

    testWidgets('no poder verificar no es una cadena rota', (tester) async {
      audit.failVerify = true;
      await open(tester, AdminRoutes.audit);
      expect(find.textContaining('No pudimos verificar'), findsOneWidget);
      expect(find.byKey(const Key('adminChainBroken')), findsNothing);
      audit.failVerify = false;
      await tester.tap(find.byKey(const Key('auditVerify')));
      await tester.pumpAndSettle();
      expect(find.text('Íntegra: 42 registros verificados.'), findsOneWidget);
    });
  });

  group('Temas de ayuda', () {
    setUp(() {
      topics
        ..add('something_broken', 'Algo no funciona', order: 30, by: 'Alan')
        ..add('subscription', 'Mi suscripción y pagos', audience: 'OWNER', order: 20)
        ..add('cannot_login', 'No puedo entrar a mi cuenta', audience: 'ANONYMOUS', order: 90, active: false);
    });

    testWidgets('la lista en el orden del tendero, con a quién se muestra y si está inactivo', (tester) async {
      await open(tester, AdminRoutes.helpTopics);
      Offset y(String t) => tester.getTopLeft(find.text(t));
      expect(y('Mi suscripción y pagos').dy, lessThan(y('Algo no funciona').dy));
      expect(find.text('Sólo dueños'), findsOneWidget);
      expect(find.text('Sin sesión (No puedo entrar) · Inactivo'), findsOneWidget);
    });

    testWidgets('editar: vista previa del tendero, motivo obligatorio, conserva botones y formulario', (tester) async {
      await open(tester, '${AdminRoutes.helpTopics}/something_broken');
      expect(find.text('Editado por Alan el 29 sep · 10:00.'), findsOneWidget);
      expect(find.byKey(const Key('topicPreview')), findsOneWidget);
      expect(find.text('Revisa que tengas internet.'), findsWidgets); // viñeta en la vista previa
      expect(find.textContaining('Botones: Ir a Mi suscripción'), findsOneWidget);
      FilledButton save() => tester.widget<FilledButton>(find.byKey(const Key('topicSave')));
      expect(save().onPressed, isNull); // sin cambios

      await tester.enterText(find.byKey(const Key('topicTitle')), 'Algo no funciona en la app');
      await tester.pump();
      expect(find.text('Algo no funciona en la app'), findsWidgets); // la vista previa sigue al título
      expect(save().onPressed, isNull); // falta el motivo
      await tester.enterText(find.byKey(const Key('topicReason')), 'Más claro para los tenderos');
      await tester.pump();
      await tester.ensureVisible(find.byKey(const Key('topicSave')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('topicSave')));
      await tester.pumpAndSettle();

      expect(topics.saves.single['title'], 'Algo no funciona en la app');
      expect(topics.saves.single['actions'], isNotEmpty); // se reenvían tal cual (P29)
      expect(topics.saves.single['form_fields'], isNotEmpty);
      expect(find.text('Guardado. Los tenderos lo ven al abrir Soporte.'), findsOneWidget);
      await tester.scrollUntilVisible(find.byKey(const Key('topicLastEdit')), -300,
          scrollable:
              find.descendant(of: find.byKey(const Key('topicEditor')), matching: find.byType(Scrollable)).first);
      expect(find.text('Editado por Eduardo Cristancho el 30 sep · 20:00.'), findsOneWidget);
      expect(save().onPressed, isNull); // ya no hay cambios pendientes
    });

    testWidgets('desactivar avisa que el tendero dejará de verlo', (tester) async {
      await open(tester, '${AdminRoutes.helpTopics}/something_broken');
      await tester.ensureVisible(find.byKey(const Key('topicActive')));
      await tester.tap(find.byKey(const Key('topicActive')));
      await tester.pump();
      expect(find.text('Los tenderos dejarán de verlo en Soporte.'), findsOneWidget);
    });

    testWidgets('cambiar de tema con cambios pendientes lo pregunta', (tester) async {
      final app = await open(tester, '${AdminRoutes.helpTopics}/something_broken');
      await tester.enterText(find.byKey(const Key('topicTitle')), 'Otro título');
      await tester.pump();
      await tester.tap(find.byKey(const Key('topicRow_subscription')));
      await tester.pumpAndSettle();
      expect(find.text('Tienes cambios sin guardar'), findsOneWidget);
      await tester.tap(find.byKey(const Key('topicsKeepEditing')));
      await tester.pumpAndSettle();
      expect(app.location, '${AdminRoutes.helpTopics}/something_broken');
      expect(tester.widget<TextField>(find.byKey(const Key('topicTitle'))).controller!.text, 'Otro título');

      await tester.tap(find.byKey(const Key('topicRow_subscription')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('topicsDiscard')));
      await tester.pumpAndSettle();
      expect(app.location, '${AdminRoutes.helpTopics}/subscription');
    });

    testWidgets('un rechazo del servidor se dice sin perder lo escrito', (tester) async {
      await open(tester, '${AdminRoutes.helpTopics}/something_broken');
      topics.failNext = const AdminApiException('Sin conexión con el servidor. Revisa tu red y vuelve a intentar.');
      await tester.enterText(find.byKey(const Key('topicSummary')), 'Resumen nuevo');
      await tester.enterText(find.byKey(const Key('topicReason')), 'Más claro para los tenderos');
      await tester.pump();
      await tester.ensureVisible(find.byKey(const Key('topicSave')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('topicSave')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('topicError')), findsOneWidget);
      expect(tester.widget<TextField>(find.byKey(const Key('topicSummary'))).controller!.text, 'Resumen nuevo');
    });

    testWidgets('el tema sin sesión dice que es el formulario de "No puedo entrar"', (tester) async {
      await open(tester, '${AdminRoutes.helpTopics}/cannot_login');
      expect(find.textContaining('Es el formulario de "No puedo entrar"'), findsOneWidget);
    });

    testWidgets('pantalla chica: lista y luego el editor con volver', (tester) async {
      final app = await open(tester, AdminRoutes.helpTopics, size: const Size(420, 860));
      await tester.tap(find.byKey(const Key('topicRow_subscription')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('topicEditor')), findsOneWidget);
      await tester.tap(find.byTooltip('Volver a los temas'));
      await tester.pumpAndSettle();
      expect(app.location, AdminRoutes.helpTopics);
      expect(tester.takeException(), isNull);
    });
  });
}
