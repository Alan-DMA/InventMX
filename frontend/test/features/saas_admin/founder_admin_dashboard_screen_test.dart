import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_app/core/theme/app_theme.dart';
import 'package:nexus_app/features/auth/presentation/login_provider.dart';
import 'package:nexus_app/features/saas_admin/data/saas_repository.dart';
import 'package:nexus_app/features/saas_admin/presentation/founder_admin_dashboard_screen.dart';
import 'package:nexus_app/features/saas_admin/presentation/saas_provider.dart';

/// Tarea 14.2.2 — CA-05 (métricas calculadas), CA-06 (aprobar/rechazar),
/// CA-07 (filtros, búsqueda, reactivar/extender).
void main() {
  final now = DateTime(2026, 9, 14);

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final mock = SaasRepositoryMock(
      currentEmail: 'eduardo@nexus.mx',
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
          home: const FounderAdminDashboardScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> settleSnackbar(WidgetTester tester) =>
      tester.pump(const Duration(seconds: 5));

  testWidgets('CA-05: MRR, conteos y retención salen del mock, no de constantes', (tester) async {
    await pump(tester);
    expect(find.byKey(const Key('mrrValue')), findsOneWidget);
    expect(find.text('\$1,895.00'), findsOneWidget);
    expect(find.byKey(const Key('statActive')), findsOneWidget);
    expect(find.text('5'), findsOneWidget); // activos
    expect(find.text('63%'), findsOneWidget); // 5 / 8
    expect(find.textContaining('8 comercios'), findsOneWidget);
    expect(find.textContaining('2 pagos por validar'), findsOneWidget);
  });

  testWidgets('CA-06: aprobar pide confirmación con nombre y monto; reactiva y recalcula', (tester) async {
    await pump(tester);
    // Bandeja: primero el más antiguo (Lupita, SPEI)
    expect(find.byKey(const Key('inbox-val-1')), findsOneWidget);
    expect(find.text('Miscelánea Lupita · 318902'), findsOneWidget);

    await tester.tap(find.byKey(const Key('approve-val-1')));
    await tester.pumpAndSettle();
    expect(find.text('Aprobar pago'), findsOneWidget);
    expect(find.textContaining('Miscelánea Lupita (318902) · \$199.00 MXN'), findsOneWidget);
    await tester.tap(find.byKey(const Key('confirmApprove')));
    await tester.pumpAndSettle();

    expect(find.text('Miscelánea Lupita está al corriente.'), findsOneWidget);
    expect(find.byKey(const Key('inbox-val-1')), findsNothing);
    // MRR sube 199 y ya solo hay un moroso en solo lectura
    expect(find.text('\$2,094.00'), findsOneWidget);
    expect(find.textContaining('1 pagos por validar'), findsOneWidget);
    await settleSnackbar(tester);
  });

  testWidgets('CA-06: rechazar exige motivo; la factura sigue pendiente', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const Key('reject-val-2')));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Rechazar aviso'), findsOneWidget);

    await tester.tap(find.byKey(const Key('confirmReject')));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Escribe el motivo.'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('rejectNotesField')), 'No aparece en el banco');
    await tester.pump();
    await tester.tap(find.byKey(const Key('confirmReject')));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.textContaining('Aviso rechazado. La Esquina verá el motivo.'), findsOneWidget);
    expect(find.byKey(const Key('inbox-val-2')), findsNothing);
    // El comercio sigue bloqueado y su factura pendiente (rechazar no cobra)
    await tester.scrollUntilVisible(find.byKey(const Key('tenant-t-esquina')), 200, scrollable: find.byType(Scrollable).first);
    expect(find.byKey(const Key('tenantStatus-t-esquina')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('tenant-t-esquina')), matching: find.text('Bloqueada')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('tenant-t-esquina')), matching: find.textContaining('Vencida hace 13 días')), findsOneWidget);
    await settleSnackbar(tester);
  });

  testWidgets('CA-07: filtro por estado y búsqueda por código', (tester) async {
    await pump(tester);
    await tester.scrollUntilVisible(find.byKey(const Key('filter-hardLock')), 200, scrollable: find.byType(Scrollable).first);
    // El chip vive en un scroll horizontal: asegurar visibilidad en ambos ejes
    await tester.ensureVisible(find.byKey(const Key('filter-hardLock')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('filter-hardLock')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byKey(const Key('tenant-t-esquina')), 200, scrollable: find.byType(Scrollable).first);
    expect(find.byKey(const Key('tenant-t-esquina')), findsOneWidget);
    expect(find.byKey(const Key('tenant-t-sol')), findsNothing);

    await tester.tap(find.text('Todos'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('tenantSearch')), '6110');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byKey(const Key('tenant-t-mary')), 200, scrollable: find.byType(Scrollable).first);
    expect(find.byKey(const Key('tenant-t-mary')), findsOneWidget);
    expect(find.byKey(const Key('tenant-t-esquina')), findsNothing);
  });

  testWidgets('CA-07: reactivar desde el menú del comercio confirma y cambia el estado', (tester) async {
    await pump(tester);
    await tester.scrollUntilVisible(find.byKey(const Key('filter-hardLock')), 200, scrollable: find.byType(Scrollable).first);
    // El chip vive en un scroll horizontal: asegurar visibilidad en ambos ejes
    await tester.ensureVisible(find.byKey(const Key('filter-hardLock')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('filter-hardLock')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byKey(const Key('tenant-t-esquina')), 200, scrollable: find.byType(Scrollable).first);

    await tester.tap(find.byKey(const Key('tenantMenu-t-esquina')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reactivar'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Vuelve a ACTIVE y su vencimiento se corre 7 días.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('confirmStatus-active')));
    await tester.pumpAndSettle();

    expect(find.text('La Esquina: Activa.'), findsOneWidget);
    // Con el filtro "Bloqueados" activo, ya no aparece
    expect(find.byKey(const Key('tenant-t-esquina')), findsNothing);
    expect(find.byKey(const Key('tenantsEmpty')), findsOneWidget);
    await settleSnackbar(tester);
  });

  testWidgets('Sin permiso: el repositorio rebota y la pantalla lo dice', (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionProvider.overrideWith((ref) => true),
          saasRepositoryProvider.overrideWithValue(
            SaasRepositoryMock(currentEmail: 'sol@tiendita.mx', latency: Duration.zero, now: () => now),
          ),
        ],
        child: MaterialApp(theme: AppTheme.dark, home: const FounderAdminDashboardScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Este panel es exclusivo de los fundadores de Nexus.'), findsOneWidget);
  });
}
