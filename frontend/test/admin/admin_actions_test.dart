import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_app/admin/core/admin_http.dart';
import 'package:nexus_app/admin/router/admin_routes.dart';
import 'package:nexus_app/admin/tenants/domain/tenant_models.dart';

import 'admin_harness.dart';
import 'fake_today.dart';

/// Panel de plataforma, etapa 3d — acciones de soporte. Criterios: CA-S3.4 cada
/// acción muestra "Así lo verá la tienda" y exige motivo · CA-S3.5 eliminar exige
/// a dos fundadores (quien la pidió no ve "Aprobar") · la recuperación no se
/// envía sin validar y el operador nunca ve el código · P35 aprobar pide el
/// slug · P36 acciones arriba · rechazos del servidor dentro del diálogo.
void main() {
  late TestClock clock;
  late FakeTenants tenants;
  late FakeActions actions;

  const reason = 'Compensación por la falla del cierre de turno';

  setUp(() {
    clock = TestClock(DateTime(2026, 9, 30, 20));
    tenants = FakeTenants()..add(id: 't-luz', name: 'Abarrotes Luz');
    actions = FakeActions(tenants, () => clock.now);
  });

  Future<AdminTestApp> open(WidgetTester tester, {String tenant = 't-luz'}) async {
    final app = await pumpAdmin(
      tester,
      clock: clock,
      store: signedInStore(clock),
      tenants: tenants,
      actions: actions,
    );
    app.go('${AdminRoutes.today}?tienda=$tenant');
    await tester.pumpAndSettle();
    return app;
  }

  Future<void> tapAction(WidgetTester tester, String key) async {
    await tester.ensureVisible(find.byKey(Key(key)));
    await tester.tap(find.byKey(Key(key)));
    await tester.pumpAndSettle();
  }

  FilledButton confirm(WidgetTester tester) => tester.widget<FilledButton>(find.byKey(const Key('actionConfirm')));

  testWidgets('las acciones van arriba, antes de la suscripción (P36)', (tester) async {
    await open(tester);
    final actionsY = tester.getTopLeft(find.text('Acciones')).dy;
    expect(actionsY, lessThan(tester.getTopLeft(find.text('Suscripción')).dy));
    expect(find.byKey(const Key('tenantActionSuspend')), findsOneWidget);
    expect(find.byKey(const Key('tenantActionLift')), findsNothing);
  });

  testWidgets('regalar días: vista previa del dueño, motivo mínimo y la ficha se actualiza sin volver a pedirla',
      (tester) async {
    await open(tester);
    expect(tenants.views, 1);
    await tapAction(tester, 'tenantActionGift');
    expect(find.text('Regalar días a Abarrotes Luz'), findsOneWidget);
    expect(confirm(tester).onPressed, isNull);

    await tester.enterText(find.byKey(const Key('actionDays')), '7');
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pumpAndSettle();
    expect(find.text('Soporte Nexus te regaló 7 días.'), findsOneWidget); // "Así lo verá la tienda"
    expect(find.text('Soporte Nexus · Eduardo'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('actionReason')), 'Corto');
    await tester.pump();
    expect(find.text('Mínimo 10 caracteres (5)'), findsOneWidget);
    expect(confirm(tester).onPressed, isNull);

    await tester.enterText(find.byKey(const Key('actionReason')), reason);
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pumpAndSettle();
    expect(find.text('"$reason"'), findsOneWidget);
    expect(find.text('Regalar 7 días'), findsOneWidget);
    await tester.tap(find.byKey(const Key('actionConfirm')));
    await tester.pumpAndSettle();

    expect(actions.calls, ['gift:7']);
    expect(find.byKey(const Key('tenantSheetNotice')), findsOneWidget);
    expect(find.textContaining('Listo: regalaste 7 días; vigente hasta 3 nov 2026'), findsOneWidget);
    expect(find.text('Vigente hasta 3 nov 2026'), findsOneWidget);
    expect(tenants.views, 1); // no se volvió a pedir la ficha (otra lectura en la bitácora)
  });

  testWidgets('recuperación: las 4 casillas empiezan sin marcar; el código nunca se ve', (tester) async {
    await open(tester);
    await tapAction(tester, 'tenantActionRecovery');
    for (final key in ['store_name', 'owner_email', 'signup_date', 'employees']) {
      expect(tester.widget<CheckboxListTile>(find.byKey(Key('actionCheck_$key'))).value, isFalse);
    }
    expect(find.text('Debe coincidir con: Abarrotes Luz'), findsOneWidget);
    expect(find.text('Debe coincidir con: sol@tiendita.mx'), findsOneWidget);
    expect(find.byKey(const Key('actionOrder')), findsNothing); // no paga con Google Play

    await tester.enterText(find.byKey(const Key('actionReason')), 'La dueña perdió su contraseña y su teléfono');
    await tester.pump();
    for (final key in ['store_name', 'owner_email', 'signup_date']) {
      await tester.tap(find.byKey(Key('actionCheck_$key')));
    }
    await tester.pump();
    expect(confirm(tester).onPressed, isNull); // falta una
    await tester.ensureVisible(find.byKey(const Key('actionCheck_employees')));
    await tester.tap(find.byKey(const Key('actionCheck_employees')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('actionConfirm')));
    await tester.pumpAndSettle();

    expect(actions.calls.single, startsWith('recovery:true'));
    expect(find.textContaining('Código enviado a s•••@tiendita.mx'), findsOneWidget);
    expect(find.textContaining('Tú no lo ves'), findsOneWidget);
  });

  testWidgets('recuperación de quien paga con Google Play: pide el número de orden', (tester) async {
    tenants.add(id: 't-play', name: 'Tienda Play', subscriptionSource: 'GOOGLE_PLAY');
    await open(tester, tenant: 't-play');
    await tapAction(tester, 'tenantActionRecovery');
    expect(find.byKey(const Key('actionOrder')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('actionReason')), 'El dueño no puede entrar desde ayer');
    for (final key in ['store_name', 'owner_email', 'signup_date', 'employees']) {
      await tester.ensureVisible(find.byKey(Key('actionCheck_$key')));
      await tester.tap(find.byKey(Key('actionCheck_$key')));
    }
    await tester.pump();
    expect(confirm(tester).onPressed, isNull);
    await tester.enterText(find.byKey(const Key('actionOrder')), 'GPA.3312-4455-6677-88990');
    await tester.pump();
    expect(confirm(tester).onPressed, isNotNull);
  });

  testWidgets('un rechazo del servidor se dice en el diálogo, sin cerrarlo ni perder lo escrito', (tester) async {
    await open(tester);
    await tapAction(tester, 'tenantActionSuspend');
    await tester.enterText(find.byKey(const Key('actionReason')), 'Pedidos falsos repetidos desde la vitrina');
    await tester.pump();
    actions.failNext = const AdminApiException('La tienda ya está suspendida por soporte.', statusCode: 422);
    await tester.tap(find.byKey(const Key('actionConfirm')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('actionDialog_suspend')), findsOneWidget);
    expect(find.text('La tienda ya está suspendida por soporte.'), findsOneWidget);
    expect(tester.widget<TextField>(find.byKey(const Key('actionReason'))).controller!.text,
        'Pedidos falsos repetidos desde la vitrina');
  });

  testWidgets('suspender: botón rojo que dice qué pasa; luego la ficha ofrece "Levantar la suspensión"',
      (tester) async {
    await open(tester);
    await tapAction(tester, 'tenantActionSuspend');
    await tester.enterText(find.byKey(const Key('actionReason')), 'Pedidos falsos repetidos desde la vitrina');
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pumpAndSettle();
    expect(find.text('Suspender Abarrotes Luz'), findsOneWidget);
    expect(find.text('Soporte Nexus suspendió tu tienda.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('actionConfirm')));
    await tester.pumpAndSettle();

    expect(find.text('Suspendida por soporte: Pedidos falsos repetidos desde la vitrina'), findsOneWidget);
    expect(find.byKey(const Key('tenantActionLift')), findsOneWidget);
    expect(find.byKey(const Key('tenantActionSuspend')), findsNothing);
  });

  testWidgets('exportar: después, exportar y eliminar quedan desactivados con el porqué', (tester) async {
    await open(tester);
    await tapAction(tester, 'tenantActionExport');
    await tester.enterText(find.byKey(const Key('actionReason')), 'El dueño pidió una copia de sus datos');
    await tester.pump();
    await tester.tap(find.byKey(const Key('actionConfirm')));
    await tester.pumpAndSettle();

    expect(find.text('Exportación en proceso: le llegará al dueño por correo.'), findsOneWidget);
    expect(tester.widget<OutlinedButton>(find.byKey(const Key('tenantActionExport'))).onPressed, isNull);
    expect(find.text('Ya hay una exportación en proceso.'), findsOneWidget);
    expect(tester.widget<OutlinedButton>(find.byKey(const Key('tenantActionDelete'))).onPressed, isNull);
  });

  testWidgets('pedir la eliminación: el slug exacto; quien la pidió sólo puede cancelarla (CA-S3.5)', (tester) async {
    await open(tester);
    await tapAction(tester, 'tenantActionDelete');
    await tester.enterText(find.byKey(const Key('actionReason')), 'El dueño pidió cerrar su cuenta por escrito');
    await tester.enterText(find.byKey(const Key('actionSlug')), 'abarrotes');
    await tester.pump();
    expect(confirm(tester).onPressed, isNull);
    await tester.enterText(find.byKey(const Key('actionSlug')), 'abarrotes-luz');
    await tester.pump();
    expect(find.text('Pedir la eliminación (1 de 2)'), findsOneWidget);
    await tester.tap(find.byKey(const Key('actionConfirm')));
    await tester.pumpAndSettle();

    expect(actions.calls, ['delete:abarrotes-luz']);
    expect(find.textContaining('Pediste eliminarla'), findsWidgets);
    expect(find.byKey(const Key('tenantActionApprove')), findsNothing);
    expect(find.byKey(const Key('tenantActionCancelDeletion')), findsOneWidget);
  });

  testWidgets('aprobar la eliminación pedida por el otro fundador: motivo + slug (P35); la ficha se cierra',
      (tester) async {
    tenants.add(
      id: 't-paty',
      name: 'Miscelánea Paty',
      support: SupportState(
        deletionRequestId: 'req-9',
        deletionRequestedById: 'op-alan',
        deletionRequestedBy: 'Alan',
        deletionReason: 'La dueña cerró el negocio',
        deletionExpiresAt: DateTime(2026, 10, 2, 12),
      ),
    );
    final app = await open(tester, tenant: 't-paty');
    expect(find.textContaining('Alan pidió eliminarla: "La dueña cerró el negocio"'), findsOneWidget);
    await tapAction(tester, 'tenantActionApprove');

    expect(find.textContaining('sin vuelta atrás'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('actionReason')), 'Confirmado con la dueña por teléfono');
    await tester.pump();
    expect(confirm(tester).onPressed, isNull); // falta el slug
    await tester.enterText(find.byKey(const Key('actionSlug')), 'miscelánea-paty');
    await tester.pump();
    expect(find.text('Eliminar Miscelánea Paty para siempre'), findsOneWidget);
    await tester.tap(find.byKey(const Key('actionConfirm')));
    await tester.pumpAndSettle();

    expect(actions.calls, ['approve:req-9']);
    expect(find.byKey(const Key('tenantSheet')), findsNothing);
    expect(app.location, AdminRoutes.today);
    expect(find.textContaining('Se eliminó Miscelánea Paty'), findsOneWidget);
  });

  testWidgets('Esc cierra el diálogo sin cerrar la ficha; la vista previa caída no impide enviar', (tester) async {
    actions.failPreview = true;
    await open(tester);
    await tapAction(tester, 'tenantActionExport');
    await tester.pumpAndSettle();
    expect(find.textContaining('No pudimos mostrar la vista previa; puedes enviar igual'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('actionReason')), 'El dueño pidió una copia de sus datos');
    await tester.pump();
    expect(confirm(tester).onPressed, isNotNull);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('actionDialog_export')), findsNothing);
    expect(find.byKey(const Key('tenantSheet')), findsOneWidget);
    expect(actions.calls, isEmpty);
  });

  testWidgets('doble clic no manda la acción dos veces', (tester) async {
    await open(tester);
    await tapAction(tester, 'tenantActionExport');
    await tester.enterText(find.byKey(const Key('actionReason')), 'El dueño pidió una copia de sus datos');
    await tester.pump();
    await tester.tap(find.byKey(const Key('actionConfirm')));
    await tester.tap(find.byKey(const Key('actionConfirm')), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(actions.calls, ['export']);
  });
}
