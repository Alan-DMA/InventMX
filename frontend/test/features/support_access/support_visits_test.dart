import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_app/core/router/app_router.dart';
import 'package:nexus_app/core/theme/app_theme.dart';
import 'package:nexus_app/features/support_access/data/support_access_repository.dart';
import 'package:nexus_app/features/support_access/presentation/support_access_screen.dart';

import '../support/support_app_harness.dart';

/// Etapa 4b, lado del dueño (P38, P41): ve quién de soporte entró, cuándo,
/// cuánto, por qué y qué revisó; si está dentro ahora, puede sacarlo de un
/// toque; le llega un aviso con número en el ☰ que se apaga al verlo.
void main() {
  final now = DateTime(2026, 9, 14, 10);

  SupportVisit visitNow() => SupportVisit(
        id: 'v2',
        by: 'Soporte Nexus · Eduardo',
        reason: 'Revisar por qué no le cuadra el inventario de refrescos',
        active: true,
        openedAt: now.subtract(const Duration(minutes: 6)),
        minutes: 6,
        sections: const ['Inventario'],
      );

  SupportVisit visitBefore() => SupportVisit(
        id: 'v1',
        by: 'Soporte Nexus · Alan',
        reason: 'El corte de caja no le cuadraba',
        openedAt: DateTime(2026, 9, 12, 18, 2),
        endedAt: DateTime(2026, 9, 12, 18, 20),
        minutes: 18,
        sections: const ['Caja', 'Ventas'],
        endText: 'Soporte la terminó',
      );

  testWidgets('soporte está dentro: tarjeta con quién y por qué, "Quién entró" con lo que revisó, y quitarlo lo saca',
      (tester) async {
    tester.view.physicalSize = const Size(412 * 3, 915 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    final repo = SupportAccessRepositoryMock(latency: Duration.zero, now: () => now);
    await tester.runAsync(() => repo.grant(24));
    repo.visits.addAll([visitNow(), visitBefore()]);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        supportAccessRepositoryProvider.overrideWithValue(repo),
        supportAccessClockProvider.overrideWithValue(() => now),
      ],
      child: MaterialApp(theme: AppTheme.dark, home: const SupportAccessScreen()),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('supportVisitNow_v2')), findsOneWidget);
    expect(find.text('Soporte está viendo tu tienda ahora'), findsOneWidget);
    expect(find.textContaining('Soporte Nexus · Eduardo · sólo lectura · entró a las 09:54'), findsOneWidget);
    expect(find.text('Motivo: Revisar por qué no le cuadra el inventario de refrescos'), findsWidgets);
    expect(find.text('Ha revisado: Inventario'), findsOneWidget);

    await tester.scrollUntilVisible(find.byKey(const Key('supportVisit_v1')), 200);
    expect(find.text('Quién entró'), findsOneWidget);
    expect(find.text('Revisó: Caja, Ventas'), findsOneWidget);
    expect(find.text('Soporte la terminó'), findsOneWidget);
    expect(find.textContaining('estuvo 18 min'), findsOneWidget);

    await tester.scrollUntilVisible(find.byKey(const Key('supportAccessRevoke')), -200);
    await tester.tap(find.byKey(const Key('supportAccessRevoke')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('supportVisitNow_v2')), findsNothing);
    expect(find.text('Soporte Nexus no puede ver tu tienda.'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Terminó tu permiso'), 200);
    expect(find.text('Terminó tu permiso'), findsOneWidget);
  });

  testWidgets('aviso en "Avisos" y número en el ☰ y en "Acceso de soporte"; al verlo, se apaga', (tester) async {
    final access = SupportAccessRepositoryMock(latency: Duration.zero, now: () => now);
    await tester.runAsync(() => access.grant(1));
    access.visits.add(visitNow());
    final app = await pumpSupportApp(tester, access: access, now: now, email: demoOwnerEmail);
    await tester.pumpAndSettle();

    final menu = tester.widget<Badge>(find.byKey(const Key('homeDrawerSupportBadge')));
    expect(menu.isLabelVisible, isTrue);

    await goTo(tester, app, AppRoutes.notifications);
    expect(find.text('Soporte está viendo tu tienda'), findsOneWidget);
    expect(find.textContaining('Soporte Nexus · Eduardo · sólo lectura · Motivo:'), findsOneWidget);

    await tester.tap(find.text('Ver acceso'));
    await tester.pumpAndSettle();
    expect(find.text('Acceso de soporte'), findsOneWidget);
    expect(find.byKey(const Key('supportVisitNow_v2')), findsOneWidget);

    // Visto: el número del ☰ se apaga y queda guardado para la próxima vez
    await goTo(tester, app, AppRoutes.home);
    final after = tester.widget<Badge>(find.byKey(const Key('homeDrawerSupportBadge')));
    expect(after.isLabelVisible, isFalse);
    expect(app.storage.values.keys.any((k) => k.startsWith('nexus_support_visits_seen_at')), isTrue);
  });
}
