import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_app/core/theme/app_theme.dart';
import 'package:nexus_app/features/auth/presentation/login_provider.dart';
import 'package:nexus_app/features/saas_admin/data/saas_repository.dart';
import 'package:nexus_app/features/saas_admin/presentation/saas_provider.dart';
import 'package:nexus_app/features/saas_admin/presentation/subscription_checkout_screen.dart';
import 'package:nexus_app/features/saas_admin/presentation/widgets/cycle_line.dart';

/// Tarea 14.2.1 — CA-01 (planes), CA-02 (SPEI + copiar), CA-03 (OXXO),
/// CA-04 ("Ya pagué" → en revisión).
void main() {
  final now = DateTime(2026, 9, 14);

  Future<List<String>> pump(
    WidgetTester tester, {
    String tenant = 't-sol',
    SaasRepositoryMock? repo,
  }) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final clipboard = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboard.add((call.arguments as Map)['text'] as String);
        }
        return null;
      },
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));

    final mock = repo ??
        SaasRepositoryMock(
          currentEmail: 'sol@tiendita.mx',
          currentTenantId: tenant,
          latency: Duration.zero,
          now: () => now,
        );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionProvider.overrideWith((ref) => true),
          saasRepositoryProvider.overrideWithValue(mock),
          clockProvider.overrideWithValue(() => now),
        ],
        child: MaterialApp(
          theme: AppTheme.dark,
          home: const SubscriptionCheckoutScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return clipboard;
  }

  testWidgets('CA-01: plan actual, monto exacto y línea del ciclo con fechas', (tester) async {
    await pump(tester);
    expect(find.byKey(const Key('planHeader')), findsOneWidget);
    expect(find.text('Plan Comercio'), findsOneWidget);
    expect(find.byKey(const Key('statusChip')), findsOneWidget);
    expect(find.text('Activa'), findsOneWidget);
    expect(find.byKey(const Key('amountDue')), findsOneWidget);
    expect(find.text('\$399.00'), findsWidgets);
    // Línea del ciclo: vence 30 sep (14 + 16), solo lectura 1 oct, bloqueo 11 oct
    expect(find.byType(CycleLine), findsOneWidget);
    expect(find.textContaining('Vence el 30 sep'), findsOneWidget);
    expect(find.textContaining('Solo lectura 1 oct'), findsOneWidget);
    expect(find.textContaining('Bloqueo 11 oct'), findsOneWidget);
  });

  testWidgets('CA-01: tres planes con precios de Constitución; el actual marcado; cambiar recalcula', (tester) async {
    await pump(tester);
    await tester.scrollUntilVisible(find.text('Cambiar plan'), 300);
    await tester.pumpAndSettle();
    expect(find.text('Emprendedor'), findsOneWidget);
    expect(find.text('Comercio'), findsOneWidget);
    expect(find.text('Corporativo'), findsOneWidget);
    expect(find.text('\$199.00'), findsOneWidget);
    expect(find.text('\$699.00'), findsOneWidget);
    expect(find.text('Tu plan'), findsOneWidget);
    // El plan actual no tiene botón "Elegir"
    expect(find.byKey(const Key('selectPlan-plan-comercio')), findsNothing);

    await tester.scrollUntilVisible(find.byKey(const Key('selectPlan-plan-emprendedor')), 200);
    await tester.tap(find.byKey(const Key('selectPlan-plan-emprendedor')));
    await tester.pumpAndSettle();
    expect(find.textContaining('pasa a \$199.00 MXN'), findsOneWidget);
    await tester.tap(find.byKey(const Key('confirmChangePlan')));
    await tester.pumpAndSettle();
    expect(find.text('Ahora tienes el plan Emprendedor.'), findsOneWidget);
    // La cabecera (fuera de pantalla, ListView perezoso) refleja el plan nuevo
    await tester.scrollUntilVisible(find.byKey(const Key('planHeader')), -300);
    await tester.pumpAndSettle();
    expect(find.text('Plan Emprendedor'), findsOneWidget);
    expect(find.text('\$199.00'), findsWidgets);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('CA-02: SPEI muestra CLABE agrupada, concepto = código y copia sin espacios', (tester) async {
    final clipboard = await pump(tester);
    expect(find.text('6461 8015 7000 0000 04'), findsOneWidget);
    expect(find.text('150467'), findsOneWidget);
    expect(find.text('\$399.00 MXN'), findsOneWidget);

    await tester.tap(find.byKey(const Key('copyClabe')));
    await tester.pump();
    expect(clipboard, ['646180157000000004']);
    expect(find.text('CLABE copiado'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('copyConcept')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('copyConcept')));
    await tester.pump();
    expect(clipboard.last, '150467');
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('CA-03: OXXO muestra referencia, código de barras y vigencia; copia la referencia', (tester) async {
    final clipboard = await pump(tester);
    await tester.tap(find.text('OXXO'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('oxxoBarcode')), findsOneWidget);
    expect(find.textContaining('Vigente hasta el'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('copyOxxoReference')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('copyOxxoReference')));
    await tester.pump();
    expect(clipboard.single, startsWith('93150467'));
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('CA-03: sin referencia OXXO del backend se dice "próximamente"', (tester) async {
    await pump(
      tester,
      repo: SaasRepositoryMock(
        currentEmail: 'sol@tiendita.mx',
        latency: Duration.zero,
        includeOxxo: false,
        now: () => now,
      ),
    );
    await tester.tap(find.text('OXXO'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('oxxoUnavailable')), findsOneWidget);
    expect(find.byKey(const Key('oxxoBarcode')), findsNothing);
  });

  testWidgets('CA-04: "Ya pagué" registra la referencia y deja el aviso visible en revisión', (tester) async {
    await pump(tester);
    await tester.scrollUntilVisible(find.byKey(const Key('reportPaymentButton')), 200);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('reportPaymentButton')));
    await tester.pumpAndSettle();
    expect(find.text('Avísanos que ya pagaste'), findsOneWidget);

    // Referencia demasiado corta → error en el campo, no se envía
    await tester.enterText(find.byKey(const Key('paymentReferenceField')), 'AB');
    await tester.tap(find.byKey(const Key('submitPaymentReport')));
    await tester.pumpAndSettle();
    expect(find.text('Escribe la referencia (mínimo 4 caracteres).'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('paymentReferenceField')), 'RAST20260914');
    await tester.tap(find.byKey(const Key('submitPaymentReport')));
    await tester.pumpAndSettle();

    expect(find.text('Recibimos tu aviso. Te avisamos cuando esté validado.'), findsOneWidget);
    expect(find.text('Aviso en revisión'), findsOneWidget);
    // Con aviso en revisión el botón queda deshabilitado
    final btn = tester.widget<FilledButton>(find.byKey(const Key('reportPaymentButton')));
    expect(btn.onPressed, isNull);
    // El estado del aviso queda visible en la tarjeta del monto (arriba)
    await tester.scrollUntilVisible(find.byKey(const Key('reviewStrip')), -200);
    await tester.pumpAndSettle();
    expect(find.text('Recibimos tu aviso'), findsOneWidget);
    expect(find.textContaining('ref. RAST20260914'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('Moroso en solo lectura: chip, titular con día N y vencimiento pasado', (tester) async {
    await pump(tester, tenant: 't-lupita');
    expect(find.text('Solo lectura'), findsOneWidget); // chip
    expect(find.textContaining('Solo lectura · día 4 de 10'), findsOneWidget);
  });

  testWidgets('Historial: facturas pagadas y la pendiente', (tester) async {
    await pump(tester);
    await tester.scrollUntilVisible(find.text('Historial de pagos'), 300);
    await tester.pumpAndSettle();
    expect(find.text('Pagada'), findsNWidgets(2));
    expect(find.text('Pendiente'), findsOneWidget);
  });
}
