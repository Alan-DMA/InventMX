import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_app/core/theme/app_colors.dart';
import 'package:nexus_app/core/theme/app_theme.dart';
import 'package:nexus_app/features/analytics/data/analytics_dashboard_repository.dart';
import 'package:nexus_app/features/analytics/domain/analytics_dashboard.dart';
import 'package:nexus_app/features/analytics/presentation/analytics_dashboard_screen.dart';
import 'package:nexus_app/features/analytics/presentation/widgets/daily_sales_chart.dart';
import 'package:nexus_app/features/saas_admin/presentation/saas_provider.dart';

// ---------------------------------------------------------------------------
// Fixtures — Tarea 15.2.3 (dashboard analítico)
// ---------------------------------------------------------------------------

final _today = DateTime(2026, 9, 15, 10, 30);

Widget _build({AnalyticsDashboardRepository? repo}) {
  return ProviderScope(
    overrides: [
      clockProvider.overrideWithValue(() => _today),
      analyticsDashboardRepositoryProvider.overrideWithValue(
        repo ?? AnalyticsDashboardRepositoryMock(delay: Duration.zero),
      ),
    ],
    child: MaterialApp(theme: AppTheme.dark, home: const AnalyticsDashboardScreen()),
  );
}

class _EmptyRepo implements AnalyticsDashboardRepository {
  @override
  Future<AnalyticsDashboard> getDashboard({
    required DashboardPeriod period,
    required DateTime now,
  }) async {
    return AnalyticsDashboard(
      period: period,
      periodStart: now,
      periodEnd: now,
      totalRevenueMxn: 0,
      totalOrders: 0,
      averageTicketMxn: 0,
      grossProfitMxn: 0,
      grossMarginPercent: 0,
      dailySales: const [],
      topProducts: const [],
      comparison: const PeriodComparison(
        currentLabel: 'Hoy',
        previousLabel: 'Ayer',
        currentRevenueMxn: 0,
        previousRevenueMxn: 0,
      ),
    );
  }
}

class _RefundsRepo implements AnalyticsDashboardRepository {
  @override
  Future<AnalyticsDashboard> getDashboard({
    required DashboardPeriod period,
    required DateTime now,
  }) async {
    return AnalyticsDashboard(
      period: period,
      periodStart: now,
      periodEnd: now,
      totalRevenueMxn: 1265,
      refundsMxn: 550,
      totalOrders: 8,
      averageTicketMxn: 158.12,
      grossProfitMxn: 480,
      grossMarginPercent: 37.9,
      dailySales: [DailySalesPoint(date: now, revenueMxn: 1265, ordersCount: 8)],
      topProducts: const [],
      comparison: const PeriodComparison(
        currentLabel: 'Este mes',
        previousLabel: 'Mes pasado',
        currentRevenueMxn: 1265,
        previousRevenueMxn: 0,
      ),
    );
  }
}

class _FailingRepo implements AnalyticsDashboardRepository {
  int calls = 0;
  @override
  Future<AnalyticsDashboard> getDashboard({
    required DashboardPeriod period,
    required DateTime now,
  }) async {
    calls++;
    throw const AnalyticsException('No se pudo cargar el dashboard. Revisa tu conexión e intenta de nuevo.');
  }
}

void main() {
  group('Dominio', () {
    // 2026-09-15 es martes: la semana natural va del lunes 14 al domingo 20.
    test('los períodos son de calendario (D2): semana lunes→domingo, mes natural', () {
      final week = DashboardPeriod.week.range(_today);
      expect(week.start, DateTime(2026, 9, 14));
      expect(week.end, DateTime(2026, 9, 20));
      final prevWeek = DashboardPeriod.week.previousRange(_today);
      expect(prevWeek.start, DateTime(2026, 9, 7));
      expect(prevWeek.end, DateTime(2026, 9, 13));

      final month = DashboardPeriod.month.range(_today);
      expect(month.start, DateTime(2026, 9, 1));
      expect(month.end, DateTime(2026, 9, 30));
      final prevMonth = DashboardPeriod.month.previousRange(_today);
      expect(prevMonth.start, DateTime(2026, 8, 1));
      expect(prevMonth.end, DateTime(2026, 8, 31));

      final today = DashboardPeriod.today.range(_today);
      expect(today.start, DateTime(2026, 9, 15));
      expect(DashboardPeriod.today.previousRange(_today).end, DateTime(2026, 9, 14));
    });

    test('enero compara contra diciembre del año anterior', () {
      final prev = DashboardPeriod.month.previousRange(DateTime(2027, 1, 10));
      expect(prev.start, DateTime(2026, 12, 1));
      expect(prev.end, DateTime(2026, 12, 31));
    });

    test('los presets coinciden con el backend', () {
      expect(DashboardPeriod.values.map((p) => p.preset),
          ['TODAY', 'THIS_WEEK', 'THIS_MONTH']);
    });

    test('sin base de comparación el cambio es null (no se inventa un +100%)', () {
      const c = PeriodComparison(
        currentLabel: 'Hoy',
        previousLabel: 'Ayer',
        currentRevenueMxn: 500,
        previousRevenueMxn: 0,
      );
      expect(c.changePercent, isNull);
    });
  });

  group('Mock', () {
    test('es determinista: mismo día, mismas cifras', () async {
      final repo = AnalyticsDashboardRepositoryMock(delay: Duration.zero);
      final a = await repo.getDashboard(period: DashboardPeriod.week, now: _today);
      final b = await repo.getDashboard(period: DashboardPeriod.week, now: _today);
      expect(a, b);
      // Semana natural: del lunes 14 hasta hoy (martes 15); el resto no se pinta.
      expect(a.dailySales.length, 2);
      expect(a.dailySales.first.date, DateTime(2026, 9, 14));
      expect(a.dailySales.last.date, DateTime(2026, 9, 15));
      expect(a.periodEnd, DateTime(2026, 9, 20));
      expect(a.topProducts.length, 5);
      expect(a.totalRevenueMxn, greaterThan(0));
    });

    test('el margen bruto cuadra con precio − costo del inventario mock', () async {
      final repo = AnalyticsDashboardRepositoryMock(delay: Duration.zero);
      final d = await repo.getDashboard(period: DashboardPeriod.month, now: _today);
      // Los productos mock tienen márgenes entre ~26% y ~40%.
      expect(d.grossMarginPercent, inInclusiveRange(20, 50));
      expect(d.grossProfitMxn, lessThan(d.totalRevenueMxn));
    });
  });

  // ── CA-04: las cuatro vistas de RF-20/21 con datos del mock ─────────────
  testWidgets('muestra ventas, ganancia, comparativa y lo más vendido', (tester) async {
    await tester.pumpWidget(_build());
    await tester.pumpAndSettle();

    expect(find.text('Reportes'), findsOneWidget);
    expect(find.byKey(const Key('totalRevenue')), findsOneWidget);
    expect(find.byType(DailySalesChart), findsOneWidget);
    expect(find.byKey(const Key('grossProfit')), findsOneWidget);
    expect(find.textContaining('% de margen sobre ventas'), findsOneWidget);
    // La lista creció (Fase B): se hace scroll hasta la sección, no a ciegas.
    await tester.scrollUntilVisible(find.text('Comparado con mes pasado'), 200,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('Comparado con mes pasado'), findsOneWidget);
    expect(find.byKey(const Key('comparisonChange')), findsOneWidget);
    expect(find.text('Lo más vendido'), findsOneWidget);

    // Fase B: "Tu dinero hoy" (tres renglones con signo) y "Cómo te pagan".
    await tester.scrollUntilVisible(find.text('Tu dinero hoy'), 200,
        scrollable: find.byType(Scrollable).first);
    expect(find.byKey(const Key('workingCapitalNet')), findsOneWidget);
    expect(find.text('Fondo de caja'), findsOneWidget);
    // La app no vende fiado: sin saldo por cobrar el renglón no existe.
    expect(find.textContaining('Te deben'), findsNothing);
    expect(find.text('Lo que tienes menos lo que debes.'), findsOneWidget);
    expect(find.text('Debes a proveedores'), findsOneWidget);
    // El mock debe más de lo que tiene: el neto se pinta en rojo, como dato.
    final net = tester.widget<Text>(find.byKey(const Key('workingCapitalNet')));
    expect(net.style?.color, AppColors.error);

    await tester.scrollUntilVisible(find.text('Cómo te pagan'), 200,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('Efectivo · 72%'), findsOneWidget);
    expect(find.text('Tarjeta · 19%'), findsOneWidget);
    expect(find.text('Transferencia · 9%'), findsOneWidget);
  });

  testWidgets('sin lectura de liquidez ni cobros, las secciones nuevas no aparecen',
      (tester) async {
    await tester.pumpWidget(_build(repo: _RefundsRepo()));
    await tester.pumpAndSettle();
    expect(find.text('Tu dinero hoy'), findsNothing);
    expect(find.text('Cómo te pagan'), findsNothing);
  });

  testWidgets('cambiar el período recarga la serie', (tester) async {
    await tester.pumpWidget(_build());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('period-week')));
    await tester.pumpAndSettle();

    final chart = tester.widget<DailySalesChart>(find.byType(DailySalesChart));
    expect(chart.points.length, 2); // lunes 14 y martes 15
    // La lista creció (Fase B): se hace scroll hasta la sección, no a ciegas.
    await tester.scrollUntilVisible(find.text('Comparado con semana pasada'), 200,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('Comparado con semana pasada'), findsOneWidget);

    await tester.tap(find.byKey(const Key('period-today')));
    await tester.pumpAndSettle();
    // La lista creció (Fase B): se hace scroll hasta la sección, no a ciegas.
    await tester.scrollUntilVisible(find.text('Comparado con ayer'), 200,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('Comparado con ayer'), findsOneWidget);
  });

  testWidgets('con devoluciones, Ventas dice cuánto se vendió y cuánto volvió', (tester) async {
    await tester.pumpWidget(_build(repo: _RefundsRepo()));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('totalRevenue')), findsOneWidget);
    expect(find.text('\$1,815.00 vendidos · \$550.00 devueltos'), findsOneWidget);
  });

  testWidgets('sin devoluciones no aparece la nota', (tester) async {
    await tester.pumpWidget(_build());
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('salesRefundsNote')), findsNothing);
  });

  testWidgets('sin ventas muestra el vacío con el período nombrado', (tester) async {
    await tester.pumpWidget(_build(repo: _EmptyRepo()));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('dashboardEmpty')), findsOneWidget);
    expect(find.text('Sin ventas este mes'), findsOneWidget);
  });

  testWidgets('error de carga: mensaje y reintentar vuelve a pedir', (tester) async {
    final failing = _FailingRepo();
    await tester.pumpWidget(_build(repo: failing));
    await tester.pumpAndSettle();

    expect(find.textContaining('No se pudo cargar el dashboard'), findsOneWidget);
    await tester.tap(find.byKey(const Key('dashboardRetry')));
    await tester.pumpAndSettle();
    expect(failing.calls, 2);
  });

  testWidgets('el botón de comisiones abre "Mis Comisiones"', (tester) async {
    await tester.pumpWidget(_build());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('commissionsButton')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Mis Comisiones'), findsOneWidget);
    // Vacía el Future.delayed del mock de comisiones (reloj falso).
    await tester.pump(const Duration(seconds: 1));
  });
}
