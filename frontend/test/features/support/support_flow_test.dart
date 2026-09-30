import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_app/core/router/app_router.dart';
import 'package:nexus_app/core/theme/app_theme.dart';
import 'package:nexus_app/features/saas_admin/presentation/hard_lock_screen.dart';
import 'package:nexus_app/features/saas_admin/presentation/subscription_screen.dart';
import 'package:nexus_app/features/support/data/support_repository.dart';
import 'package:nexus_app/features/support/domain/support_models.dart';
import 'package:nexus_app/features/support/presentation/case_detail_screen.dart';
import 'package:nexus_app/features/support/presentation/case_form_screen.dart';
import 'package:nexus_app/features/support/presentation/support_home_screen.dart';
import 'package:nexus_app/features/support/presentation/topic_help_screen.dart';
import 'package:nexus_app/features/support_access/data/support_access_repository.dart';
import 'package:nexus_app/features/support_access/presentation/support_access_screen.dart';

import 'support_app_harness.dart';

/// Soporte estilo Steam, suspensión por abuso y acceso de soporte (Centro de
/// soporte, etapa 2b). Criterios: CA-S2.4 el dueño concede/ve/retira acceso
/// (oculto en el menú) · CA-S2.5 la suspensión por abuso muestra el motivo al
/// dueño y nunca ofrece renovar · CA-S2.7 ayuda antes del formulario, el caso
/// con su número, estado y conversación · insignia de respuestas.
void main() {
  final now = DateTime(2026, 9, 14, 10);

  SupportCase answeredCase({bool unread = true}) => SupportCase(
        id: 'case-1001',
        number: 1001,
        topicKey: 'something_broken',
        topicTitle: 'Algo no funciona',
        status: CaseStatus.answered,
        createdAt: now.subtract(const Duration(days: 1)),
        lastMessageAt: now.subtract(const Duration(hours: 2)),
        unread: unread,
        answers: const [CaseAnswer(label: '¿En qué parte de la app?', value: 'Caja')],
        messages: [
          CaseMessage(
            id: 'm1',
            fromSupport: false,
            authorName: 'Doña Sol',
            body: 'El corte de caja no cuadra.',
            createdAt: now.subtract(const Duration(days: 1)),
          ),
          CaseMessage(
            id: 'm2',
            fromSupport: true,
            authorName: 'Soporte Nexus · Eduardo',
            body: 'Revisa que el turno de ayer esté cerrado.',
            createdAt: now.subtract(const Duration(hours: 2)),
          ),
        ],
      );

  Future<void> openDrawer(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('homeDrawerButton')));
    await tester.pumpAndSettle();
  }

  testWidgets('menú ☰: Soporte para todos, con insignia cuando soporte respondió', (tester) async {
    final support = SupportRepositoryMock(latency: Duration.zero, now: () => now, cases: [answeredCase()]);
    await pumpSupportApp(tester, support: support);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    final badge = tester.widget<Badge>(find.byKey(const Key('homeDrawerSupportBadge')));
    expect(badge.isLabelVisible, isTrue);

    await openDrawer(tester);
    await tester.scrollUntilVisible(find.byKey(const Key('drawerSupport')), 200,
        scrollable: find.descendant(of: find.byType(Drawer), matching: find.byType(Scrollable)).first);
    expect(find.text('AYUDA'), findsOneWidget);
    expect(find.byKey(const Key('drawerSupportUnread')), findsOneWidget);
    expect(find.text('1 respuesta'), findsOneWidget);
    // P26: el acceso de soporte todavía no se ofrece
    expect(find.byKey(const Key('drawerSupportAccess')), findsNothing);

    await tester.tap(find.byKey(const Key('drawerSupport')));
    await tester.pumpAndSettle();
    expect(find.byType(SupportHomeScreen), findsOneWidget);
    // "Mis casos" ya no ocupa el cuerpo: vive en el ícono de la barra
    expect(find.text('Mis casos'), findsNothing);
    final casesBadge = tester.widget<Badge>(find.byKey(const Key('supportCasesBadge')));
    expect(casesBadge.isLabelVisible, isTrue);
    expect(find.descendant(of: find.byKey(const Key('supportCasesBadge')), matching: find.text('1')), findsOneWidget);

    await tester.tap(find.byKey(const Key('supportCasesButton')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('supportCasesSheet')), findsOneWidget);
    expect(find.text('Mis casos'), findsOneWidget);
    expect(find.text('1 respuesta nueva'), findsOneWidget);
    expect(find.byKey(const Key('supportCaseUnreadDot')), findsOneWidget);
    expect(find.text('Respondido'), findsOneWidget);

    // Tocar el caso cierra la hoja y abre su seguimiento
    await tester.tap(find.byKey(const Key('supportCase_case-1001')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('supportCasesSheet')), findsNothing);
    expect(find.byType(CaseDetailScreen), findsOneWidget);
  });

  testWidgets('un cajero también ve Soporte', (tester) async {
    await pumpSupportApp(tester, email: 'jose.ramirez@nexus.mx');
    await openDrawer(tester);
    await tester.scrollUntilVisible(find.byKey(const Key('drawerSupport')), 200,
        scrollable: find.descendant(of: find.byType(Drawer), matching: find.byType(Scrollable)).first);
    expect(find.byKey(const Key('drawerSupport')), findsOneWidget);
    expect(find.byKey(const Key('drawerSupportUnread')), findsNothing);
  });

  testWidgets('ayuda primero, luego el formulario del tema y el caso con su número', (tester) async {
    final app = await pumpSupportApp(tester);
    await goTo(tester, app, AppRoutes.support);
    expect(find.text('¿En qué te ayudamos?'), findsOneWidget);
    // Sin casos el ícono sigue ahí, sin insignia, y la hoja lo dice
    expect(tester.widget<Badge>(find.byKey(const Key('supportCasesBadge'))).isLabelVisible, isFalse);
    await tester.tap(find.byKey(const Key('supportCasesButton')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('supportCasesEmpty')), findsOneWidget);
    expect(find.text('Aún no tienes casos'), findsOneWidget);
    await tester.tap(find.byKey(const Key('supportCasesClose')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('supportCasesSheet')), findsNothing);
    expect(find.byKey(const Key('supportTopic_cannot_login')), findsNothing); // ése es sin sesión

    await tester.tap(find.byKey(const Key('supportTopic_something_broken')));
    await tester.pumpAndSettle();
    expect(find.byType(TopicHelpScreen), findsOneWidget);
    expect(find.text('Antes de escribirnos, prueba esto:'), findsOneWidget);
    expect(find.text('Revisa que tengas internet.'), findsOneWidget); // viñeta

    await tester.scrollUntilVisible(find.byKey(const Key('topicNeedHelp')), 200);
    await tester.tap(find.byKey(const Key('topicNeedHelp')));
    await tester.pumpAndSettle();
    expect(find.byType(CaseFormScreen), findsOneWidget);
    expect(find.text('¿Cuándo pasó? (opcional)'), findsOneWidget);

    await tester.tap(find.byKey(const Key('caseChoice_module_Caja')));
    await tester.enterText(find.byKey(const Key('caseField_when')), 'Hoy en la mañana');
    final list = find.descendant(of: find.byType(CaseFormScreen), matching: find.byType(Scrollable)).first;
    await tester.scrollUntilVisible(find.byKey(const Key('caseDescription')), 200, scrollable: list);
    await tester.enterText(find.byKey(const Key('caseDescription')), 'Al cerrar el turno la app se queda cargando.');
    await tester.scrollUntilVisible(find.byKey(const Key('caseSendButton')), 200, scrollable: list);
    await tester.tap(find.byKey(const Key('caseSendButton')));
    await tester.pumpAndSettle();

    expect(find.byType(CaseDetailScreen), findsOneWidget);
    expect(find.text('Caso 1042'), findsOneWidget);
    expect(find.text('Esperando a soporte'), findsOneWidget);
    expect(find.textContaining('Caja', findRichText: true), findsOneWidget);
    expect(find.text('Al cerrar el turno la app se queda cargando.'), findsOneWidget);
    expect(find.byKey(const Key('caseNextStep')), findsOneWidget);

    // Volver: el caso ya aparece en "Mis casos"
    app.router!.pop();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('supportCasesButton')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('supportCase_case-1042')), findsOneWidget);
    expect(find.text('1 esperando a soporte'), findsOneWidget);
  });

  group('hoja "Mis casos"', () {
    SupportCase item(String id, int number, CaseStatus status, {bool unread = false, int hoursAgo = 1}) =>
        SupportCase(
          id: id,
          number: number,
          topicKey: 'something_broken',
          topicTitle: 'Algo no funciona',
          status: status,
          createdAt: now.subtract(const Duration(days: 3)),
          lastMessageAt: now.subtract(Duration(hours: hoursAgo)),
          unread: unread,
          answers: const [],
          messages: const [],
        );

    testWidgets('orden: sin leer, luego abiertos, luego resueltos; resumen escrito', (tester) async {
      final support = SupportRepositoryMock(latency: Duration.zero, now: () => now, cases: [
        item('c-resolved', 1001, CaseStatus.resolved, hoursAgo: 1), // el más reciente, pero resuelto
        item('c-waiting', 1002, CaseStatus.waitingSupport, hoursAgo: 5),
        item('c-unread', 1003, CaseStatus.answered, unread: true, hoursAgo: 30),
        item('c-answered', 1004, CaseStatus.answered, hoursAgo: 3),
      ]);
      final app = await pumpSupportApp(tester, support: support);
      await goTo(tester, app, AppRoutes.support);
      await tester.tap(find.byKey(const Key('supportCasesButton')));
      await tester.pumpAndSettle();

      final ids = tester
          .widgetList<InkWell>(find.byWidgetPredicate((w) =>
              w is InkWell && w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('supportCase_')))
          .map((w) => (w.key! as ValueKey<String>).value)
          .toList();
      expect(ids, ['supportCase_c-unread', 'supportCase_c-answered', 'supportCase_c-waiting', 'supportCase_c-resolved']);
      expect(find.text('1 respuesta nueva · 1 respondido · 1 esperando a soporte · 1 resuelto'), findsOneWidget);
    });

    testWidgets('insignia con tope 9+', (tester) async {
      final support = SupportRepositoryMock(latency: Duration.zero, now: () => now, cases: [
        for (var i = 0; i < 12; i++) item('c-$i', 1100 + i, CaseStatus.answered, unread: true, hoursAgo: i + 1),
      ]);
      final app = await pumpSupportApp(tester, support: support);
      await goTo(tester, app, AppRoutes.support);
      expect(find.descendant(of: find.byKey(const Key('supportCasesBadge')), matching: find.text('9+')), findsOneWidget);
      expect(find.byTooltip('Mis casos · 12 respuestas nuevas'), findsOneWidget);
    });

    testWidgets('mientras carga muestra el indicador', (tester) async {
      final support = _SlowCases(now: () => now);
      final app = await pumpSupportApp(tester, support: support);
      // El indicador vive sólo en la hoja: la pantalla sí se asienta
      await goTo(tester, app, AppRoutes.support);
      await tester.tap(find.byKey(const Key('supportCasesButton')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const Key('supportCasesLoading')), findsOneWidget);

      support.release.complete();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('supportCasesLoading')), findsNothing);
      expect(find.byKey(const Key('supportCasesEmpty')), findsOneWidget);
    });

    testWidgets('sin red: mensaje en la hoja y "Reintentar" la recupera', (tester) async {
      final support = _FlakyCases(now: () => now, cases: [item('c-1', 1001, CaseStatus.waitingSupport)]);
      final app = await pumpSupportApp(tester, support: support);
      await goTo(tester, app, AppRoutes.support);
      // Sin la lista no hay insignia, pero el ícono sigue disponible
      expect(tester.widget<Badge>(find.byKey(const Key('supportCasesBadge'))).isLabelVisible, isFalse);

      await tester.tap(find.byKey(const Key('supportCasesButton')));
      await tester.pumpAndSettle();
      expect(find.text('No pudimos cargar tus casos.'), findsOneWidget);

      support.failing = false;
      await tester.tap(find.byKey(const Key('supportRetry')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('supportCase_c-1')), findsOneWidget);
    });
  });

  testWidgets('en el caso: responder reabre, resolver lo cierra y el hilo firma a soporte', (tester) async {
    final support = SupportRepositoryMock(latency: Duration.zero, now: () => now, cases: [answeredCase()]);
    final app = await pumpSupportApp(tester, support: support);
    await goTo(tester, app, AppRoutes.supportCasePath('case-1001'));

    expect(find.text('Soporte Nexus · Eduardo · ${caseMoment(now.subtract(const Duration(hours: 2)))}'), findsOneWidget);
    expect(find.text('Respondido'), findsOneWidget);

    await tester.tap(find.byKey(const Key('caseResolveButton')));
    await tester.pumpAndSettle();
    expect(find.text('Resuelto'), findsOneWidget);
    expect(find.byKey(const Key('caseResolveButton')), findsNothing);
    expect(find.text('Escribe para reabrir el caso'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('caseReplyField')), 'Volvió a pasar hoy.');
    await tester.pump();
    await tester.tap(find.byKey(const Key('caseSendReply')));
    await tester.pumpAndSettle();
    expect(find.text('Volvió a pasar hoy.'), findsOneWidget);
    expect(find.text('Esperando a soporte'), findsOneWidget);
  });

  testWidgets('suspendida por soporte: el dueño ve el motivo, nunca "Renovar", y puede escribir a soporte',
      (tester) async {
    final app = await pumpSupportApp(tester, abuseReason: 'Vitrina web con productos prohibidos.');
    expect(find.byType(HardLockScreen), findsOneWidget);
    expect(find.text('Soporte Nexus suspendió tu cuenta'), findsOneWidget);
    expect(find.text('“Vitrina web con productos prohibidos.”'), findsOneWidget);
    expect(find.textContaining('renovar la suscripción no la levanta'), findsOneWidget);
    expect(find.byKey(const Key('hardLockRenewButton')), findsNothing);

    await tester.tap(find.byKey(const Key('abuseLockContactSupport')));
    await tester.pumpAndSettle();
    expect(find.byType(TopicHelpScreen), findsOneWidget);
    expect(find.text('Mi cuenta está suspendida'), findsOneWidget);

    // Soporte queda abierto aun suspendida; lo demás regresa a la suspensión
    await goTo(tester, app, AppRoutes.support);
    expect(find.byType(SupportHomeScreen), findsOneWidget);
    await goTo(tester, app, AppRoutes.sales);
    expect(find.byType(HardLockScreen), findsOneWidget);

    // Mi suscripción lo dice y no ofrece renovar
    await goTo(tester, app, AppRoutes.subscription);
    expect(find.byType(MySubscriptionScreen), findsOneWidget);
    expect(find.text('Suspendida por soporte'), findsOneWidget);
    expect(find.byKey(const Key('subscriptionRenewalSoon')), findsNothing);
    expect(find.byKey(const Key('subscriptionContactSupport')), findsOneWidget);
  });

  testWidgets('suspendida por soporte: un empleado no ve el motivo', (tester) async {
    await pumpSupportApp(tester, abuseReason: 'Motivo sólo para el dueño.', email: 'jose.ramirez@nexus.mx');
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.text('Soporte Nexus suspendió la cuenta de la tienda'), findsOneWidget);
    expect(find.byKey(const Key('abuseLockReason')), findsNothing);
    expect(find.byKey(const Key('abuseLockTellOwner')), findsOneWidget);
  });

  testWidgets('suspendida por falta de pago: sigue igual y ahora ofrece escribir a soporte', (tester) async {
    await pumpSupportApp(tester, daysUntilDue: -15);
    expect(find.text('Tu cuenta está suspendida'), findsOneWidget);
    expect(find.byKey(const Key('hardLockContactSupport')), findsOneWidget);
  });

  group('Acceso de soporte (dueño)', () {
    Future<SupportAccessRepositoryMock> pumpAccess(WidgetTester tester) async {
      tester.view.physicalSize = const Size(412 * 3, 915 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = SupportAccessRepositoryMock(latency: Duration.zero, now: () => now);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          supportAccessRepositoryProvider.overrideWithValue(repo),
          supportAccessClockProvider.overrideWithValue(() => now),
        ],
        child: MaterialApp(theme: AppTheme.dark, home: const SupportAccessScreen()),
      ));
      await tester.pumpAndSettle();
      return repo;
    }

    testWidgets('conceder 1 hora (preseleccionada), ver el estado y quitarlo en un toque', (tester) async {
      await pumpAccess(tester);
      expect(find.text('Soporte Nexus no puede ver tu tienda.'), findsOneWidget);
      expect(find.text('Permitir acceso por 1 hora'), findsOneWidget); // el default que más protege

      await tester.tap(find.byKey(const Key('supportAccessGrant')));
      await tester.pumpAndSettle();
      expect(find.textContaining('puede ver tu tienda hasta el 14 sep 2026 a las 11:00'), findsOneWidget);
      expect(find.textContaining('quedan 60 min'), findsOneWidget);

      await tester.tap(find.byKey(const Key('supportAccessRevoke')));
      await tester.pumpAndSettle();
      expect(find.text('Soporte Nexus no puede ver tu tienda.'), findsOneWidget);
      expect(find.textContaining('Concediste 1 hora'), findsOneWidget);
      expect(find.textContaining('lo quitaste'), findsOneWidget);
    });

    testWidgets('3 días', (tester) async {
      await pumpAccess(tester);
      await tester.tap(find.text('3 días'));
      await tester.pumpAndSettle();
      expect(find.text('Permitir acceso por 3 días'), findsOneWidget);
      await tester.tap(find.byKey(const Key('supportAccessGrant')));
      await tester.pumpAndSettle();
      expect(find.textContaining('quedan 3 días'), findsOneWidget);
    });

    test('la entrada del menú sigue oculta hasta la etapa 4', () {
      expect(kSupportAccessVisible, isFalse);
    });
  });
}

/// `cases()` no responde hasta que el test lo suelta.
class _SlowCases extends SupportRepositoryMock {
  _SlowCases({super.now}) : super(latency: Duration.zero);
  final release = Completer<void>();

  @override
  Future<List<SupportCase>> cases() async {
    await release.future;
    return super.cases();
  }
}

/// `cases()` falla como sin red hasta que el test lo apaga.
class _FlakyCases extends SupportRepositoryMock {
  _FlakyCases({super.now, super.cases}) : super(latency: Duration.zero);
  bool failing = true;

  @override
  Future<List<SupportCase>> cases() async {
    if (failing) throw const SupportException('No pudimos cargar tus casos.');
    return super.cases();
  }
}
