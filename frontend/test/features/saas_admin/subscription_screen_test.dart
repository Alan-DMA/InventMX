import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_app/core/theme/app_theme.dart';
import 'package:nexus_app/features/auth/presentation/login_provider.dart';
import 'package:nexus_app/features/saas_admin/data/saas_repository.dart';
import 'package:nexus_app/features/saas_admin/domain/subscription.dart';
import 'package:nexus_app/features/saas_admin/presentation/saas_provider.dart';
import 'package:nexus_app/features/saas_admin/presentation/subscription_screen.dart';

/// Mi suscripción informativa (P9–P13): plan, línea del ciclo, sin formas de
/// pago mientras no haya canal, uso del plan y actividad de soporte (P8).
void main() {
  final now = DateTime(2026, 9, 14);

  Future<void> pump(
    WidgetTester tester,
    SaasRepositoryMock repo, {
    Future<void> Function(BuildContext)? renewal,
  }) async {
    tester.view.physicalSize = const Size(412 * 3, 1400 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        sessionProvider.overrideWith((ref) => true),
        saasRepositoryProvider.overrideWithValue(repo),
        clockProvider.overrideWithValue(() => now),
        if (renewal != null) renewalActionProvider.overrideWithValue(renewal),
      ],
      child: MaterialApp(theme: AppTheme.dark, home: const MySubscriptionScreen()),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('vigente: plan, precio, fechas, uso y la actividad con su motivo', (tester) async {
    await pump(tester, SaasRepositoryMock(latency: Duration.zero, now: () => now));

    expect(find.text('Plan Comercio'), findsOneWidget);
    expect(find.text(r'$399.00 MXN al mes'), findsOneWidget);
    expect(find.text('Activa'), findsOneWidget);
    expect(find.text('Vence el 4 oct · faltan 20 días'), findsOneWidget);
    expect(find.textContaining('pagado hasta el 4 oct 2026'), findsOneWidget);
    expect(find.text('2 de 5 usuarios'), findsOneWidget);

    // Sin canal de renovación: ni botón ni instrucciones de pago
    expect(find.byKey(const Key('subscriptionRenewButton')), findsNothing);
    expect(find.byKey(const Key('subscriptionRenewalSoon')), findsOneWidget);

    expect(find.text('Te dimos un mes sin costo.'), findsOneWidget);
    expect(find.text('Motivo: Compensación por la caída del servicio del 16 de septiembre.'), findsOneWidget);
    expect(find.textContaining('Soporte Nexus · Eduardo'), findsOneWidget);
  });

  testWidgets('en gracia: chip y línea lo dicen, con acceso completo', (tester) async {
    await pump(tester, SaasRepositoryMock(latency: Duration.zero, now: () => now, daysUntilDue: -4));
    expect(find.text('En gracia'), findsOneWidget);
    expect(find.text('En gracia · 6 días con acceso completo'), findsOneWidget);
    expect(find.textContaining('Conservas acceso completo hasta el 20 sep 2026'), findsOneWidget);
  });

  testWidgets('sin actividad lo dice en vez de dejar un hueco', (tester) async {
    await pump(tester, SaasRepositoryMock(latency: Duration.zero, now: () => now, activity: const []));
    expect(find.byKey(const Key('supportActivityEmpty')), findsOneWidget);
  });

  testWidgets('con canal de Google Play, "Renovar" llama al punto de conexión', (tester) async {
    var launched = 0;
    await pump(
      tester,
      SaasRepositoryMock(latency: Duration.zero, now: () => now, renewalChannel: RenewalChannel.googlePlay),
      renewal: (_) async => launched++,
    );
    expect(find.text(r'Renovar por $399.00'), findsOneWidget);
    await tester.tap(find.byKey(const Key('subscriptionRenewButton')));
    await tester.pumpAndSettle();
    expect(launched, 1);
  });
}
