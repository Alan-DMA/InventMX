import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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
    test('fromJson mapea sales_metrics, profitability, top_products y la serie', () {
      final d = AnalyticsDashboard.fromJson(const {
        'period_info': {'period': 'MONTH', 'start_date': '2026-09-01', 'end_date': '2026-09-15'},
        'sales_metrics': {
          'total_revenue_mxn': 12000.0,
          'total_orders': 300,
          'average_ticket_mxn': 40.0,
          'revenue_change_percent': 20.0,
        },
        'profitability': {'gross_profit_mxn': 3600.0, 'gross_margin_percent': 30.0},
        'top_products': [
          {'product_name': 'Coca-Cola 600ml', 'units_sold': 120, 'revenue_mxn': 2160.0, 'profit_mxn': 780.0},
        ],
      }, period: DashboardPeriod.month, trends: const [
        {'period': '2026-09-14', 'revenue_mxn': 800.0, 'orders_count': 20},
        {'period': '2026-09-15', 'revenue_mxn': 950.5, 'orders_count': 24},
      ]);

      expect(d.totalRevenueMxn, 12000.0);
      expect(d.totalOrders, 300);
      expect(d.grossMarginPercent, 30.0);
      expect(d.topProducts.single.name, 'Coca-Cola 600ml');
      expect(d.dailySales.length, 2);
      expect(d.dailySales.last.revenueMxn, 950.5);
      // +20% ⇒ el anterior fue 10,000
      expect(d.comparison.previousRevenueMxn, closeTo(10000.0, 0.01));
      expect(d.comparison.changePercent, closeTo(20.0, 0.01));
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
      expect(a.dailySales.length, 7);
      expect(a.dailySales.last.date, DateTime(2026, 9, 15));
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
    await tester.drag(find.byType(ListView), const Offset(0, -700));
    await tester.pumpAndSettle();
    expect(find.text('Comparado con mes pasado'), findsOneWidget);
    expect(find.byKey(const Key('comparisonChange')), findsOneWidget);
    expect(find.text('Lo más vendido'), findsOneWidget);
  });

  testWidgets('cambiar el período recarga la serie', (tester) async {
    await tester.pumpWidget(_build());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('period-week')));
    await tester.pumpAndSettle();

    final chart = tester.widget<DailySalesChart>(find.byType(DailySalesChart));
    expect(chart.points.length, 7);
    await tester.drag(find.byType(ListView), const Offset(0, -700));
    await tester.pumpAndSettle();
    expect(find.text('Comparado con semana pasada'), findsOneWidget);

    await tester.tap(find.byKey(const Key('period-today')));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -700));
    await tester.pumpAndSettle();
    expect(find.text('Comparado con ayer'), findsOneWidget);
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
