// Repositorio real de Reportes contra el backend de `analytics_reports`:
// cuatro lecturas en paralelo, montos como string, Top reordenado por ingreso
// y tolerancia a fallos en las lecturas complementarias.
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nexus_app/core/network/dio_client.dart';
import 'package:nexus_app/features/analytics/data/analytics_dashboard_repository.dart';
import 'package:nexus_app/features/analytics/domain/analytics_dashboard.dart';

class MockDioClient extends Mock implements DioClient {}

const _base = '/api/v1/analytics';

// 2026-09-15 (martes): semana natural 14–20, mes 1–30, mes anterior 1–31 ago.
final _now = DateTime(2026, 9, 15, 10, 30);

/// Respuesta de `/financial-summary` tal como la serializa Pydantic v2:
/// los `Decimal` viajan como **string**.
Map<String, dynamic> _summary({
  String net = '150.00',
  String profit = '60.00',
  int tx = 2,
  String refunds = '100.00',
}) =>
    {
      'period_start': '2026-09-15T00:00:00',
      'period_end': '2026-09-15T23:59:59.999999',
      'gross_sales_mxn': '250.00',
      'discounts_mxn': '0.00',
      'net_sales_mxn': net,
      'refunds_mxn': refunds,
      'cogs_mxn': '90.00',
      'gross_profit_mxn': profit,
      'profit_margin_pct': '40.00',
      'average_ticket_mxn': '75.00',
      'total_transactions': tx,
      'payment_methods': [
        {'payment_method': 'CARD_TPV', 'total_mxn': '50.00', 'transaction_count': 1, 'percentage': '25.00'},
        {'payment_method': 'CASH_MXN', 'total_mxn': '150.00', 'transaction_count': 2, 'percentage': '75.00'},
      ],
    };

final _capital = {
  'as_of_date': '2026-09-15T10:30:00',
  'cash_in_register_mxn': '500.00',
  'accounts_receivable_mxn': '120.50',
  'accounts_payable_mxn': '900.00',
  'net_working_capital_mxn': '-279.50',
};

final _trends = {
  'period_start': '2026-09-14T00:00:00',
  'period_end': '2026-09-20T23:59:59.999999',
  'granularity': 'daily',
  'trends': [
    {'period': '2026-09-14', 'revenue_mxn': '0', 'orders_count': 0, 'gross_profit_mxn': '0'},
    {'period': '2026-09-15', 'revenue_mxn': '150.00', 'orders_count': 2, 'gross_profit_mxn': '60.00'},
  ],
};

final _health = {
  'valuation': {
    'total_active_skus': 2,
    'total_units_in_stock': '97.00',
    'total_inventory_cost_mxn': '1000.00',
    'total_inventory_retail_mxn': '1500.00',
    'potential_gross_profit_mxn': '500.00',
  },
  // El backend ordena por unidades: B (3 pzas, $60) antes que A (1 pza, $100).
  'top_selling_products': [
    {'product_id': 'b', 'product_name': 'Producto B', 'sku': 'B', 'units_sold': '3.00', 'revenue_mxn': '60.00', 'profit_mxn': '20.00'},
    {'product_id': 'a', 'product_name': 'Producto A', 'sku': 'A', 'units_sold': '1.00', 'revenue_mxn': '100.00', 'profit_mxn': '40.00'},
  ],
  'critical_stock_products': [],
};

Response<dynamic> _ok(String path, dynamic data) => Response(
      data: data,
      statusCode: 200,
      requestOptions: RequestOptions(path: path),
    );

DioException _http(String path, int status) => DioException(
      requestOptions: RequestOptions(path: path),
      response: Response(statusCode: status, requestOptions: RequestOptions(path: path)),
      type: DioExceptionType.badResponse,
    );

void main() {
  late MockDioClient client;
  late AnalyticsDashboardRepositoryImpl repo;
  late List<(String, Map<String, dynamic>?)> calls;

  /// Registra cada GET y responde según el path y el preset pedido.
  void stub({
    Map<String, dynamic>? Function(Map<String, dynamic>? q)? summary,
    bool trendsFail = false,
    bool healthFail = false,
    bool capitalFail = false,
  }) {
    when(() => client.get<dynamic>(
          any(),
          queryParameters: any(named: 'queryParameters'),
          options: any(named: 'options'),
        )).thenAnswer((inv) async {
      final path = inv.positionalArguments.first as String;
      final q = inv.namedArguments[#queryParameters] as Map<String, dynamic>?;
      calls.add((path, q));
      if (path == '$_base/financial-summary') {
        final data = summary?.call(q) ?? _summary();
        return _ok(path, data);
      }
      if (path == '$_base/sales-trends') {
        if (trendsFail) throw _http(path, 500);
        return _ok(path, _trends);
      }
      if (path == '$_base/inventory-health') {
        if (healthFail) throw _http(path, 500);
        return _ok(path, _health);
      }
      if (path == '$_base/working-capital') {
        if (capitalFail) throw _http(path, 500);
        return _ok(path, _capital);
      }
      throw _http(path, 404);
    });
  }

  setUp(() {
    client = MockDioClient();
    repo = AnalyticsDashboardRepositoryImpl(client: client);
    calls = [];
  });

  test('compone el dashboard con las cuatro lecturas y parsea montos string', () async {
    stub(summary: (q) => q?['preset'] == 'CUSTOM' ? _summary(net: '100.00', profit: '30.00', tx: 1) : null);

    final d = await repo.getDashboard(period: DashboardPeriod.week, now: _now);

    // Presets del período actual y CUSTOM (semana pasada) para la comparativa
    final byPath = {for (final c in calls) '${c.$1}|${c.$2?['preset']}': c.$2};
    expect(byPath['$_base/financial-summary|THIS_WEEK'], isNotNull);
    expect(byPath['$_base/sales-trends|THIS_WEEK'], isNotNull);
    expect(byPath['$_base/inventory-health|THIS_WEEK'], isNotNull);
    final prev = byPath['$_base/financial-summary|CUSTOM']!;
    expect(prev['start_date'], startsWith('2026-09-07T00:00:00'));
    expect(prev['end_date'], startsWith('2026-09-13T23:59:59'));
    expect(prev['end_date'], isNot(endsWith('Z'))); // ISO local, como el historial

    expect(d.totalRevenueMxn, 150.0); // "150.00" → 150
    expect(d.refundsMxn, 100.0);
    expect(d.grossRevenueMxn, 250.0);
    expect(d.totalOrders, 2);
    expect(d.averageTicketMxn, 75.0);
    expect(d.grossProfitMxn, 60.0);
    expect(d.grossMarginPercent, 40.0);
    expect(d.periodStart, DateTime(2026, 9, 14));
    expect(d.periodEnd, DateTime(2026, 9, 20));

    expect(d.dailySales.length, 2);
    expect(d.dailySales.first.revenueMxn, 0);
    expect(d.dailySales.last.date, DateTime(2026, 9, 15));
    expect(d.dailySales.last.revenueMxn, 150.0);
    expect(d.dailySales.last.ordersCount, 2);

    // Top reordenado por ingreso: A ($100) antes que B ($60)
    expect(d.topProducts.map((t) => t.name), ['Producto A', 'Producto B']);
    expect(d.topProducts.first.unitsSold, 1);
    expect(d.topProducts.first.profitMxn, 40.0);

    expect(d.comparison.currentLabel, 'Esta semana');
    expect(d.comparison.previousLabel, 'Semana pasada');
    expect(d.comparison.currentRevenueMxn, 150.0);
    expect(d.comparison.previousRevenueMxn, 100.0);
    expect(d.comparison.changePercent, closeTo(50.0, 0.01));
    expect(d.isEmpty, isFalse);

    // Fase B: métodos ordenados por monto (efectivo primero) y liquidez de hoy
    expect(byPath['$_base/working-capital|null'], isNotNull);
    expect(d.paymentMethods.map((m) => m.label), ['Efectivo', 'Tarjeta']);
    expect(d.paymentMethods.first.percentage, 75.0);
    expect(d.paymentMethods.first.isCash, isTrue);
    expect(d.workingCapital?.cashInRegisterMxn, 500.0);
    expect(d.workingCapital?.receivableMxn, 120.5);
    expect(d.workingCapital?.payableMxn, 900.0);
    expect(d.workingCapital?.netMxn, -279.5);
  });

  test('sin ventas en ninguno de los dos períodos: vacío y sin base de comparación', () async {
    stub(summary: (_) => _summary(net: '0.00', profit: '0.00', tx: 0));
    when(() => client.get<dynamic>(
          '$_base/sales-trends',
          queryParameters: any(named: 'queryParameters'),
          options: any(named: 'options'),
        )).thenAnswer((_) async => _ok('$_base/sales-trends', {'trends': []}));

    final d = await repo.getDashboard(period: DashboardPeriod.today, now: _now);
    expect(d.isEmpty, isTrue);
    expect(d.comparison.changePercent, isNull);
  });

  test('si fallan la serie, el top o la liquidez, el dashboard sigue sirviendo', () async {
    stub(trendsFail: true, healthFail: true, capitalFail: true);

    final d = await repo.getDashboard(period: DashboardPeriod.month, now: _now);
    expect(d.totalRevenueMxn, 150.0);
    expect(d.dailySales, isEmpty);
    expect(d.topProducts, isEmpty);
    expect(d.workingCapital, isNull);
    expect(d.paymentMethods, isNotEmpty); // viene con el resumen obligatorio
  });

  test('si falla el resumen actual, lanza AnalyticsException con mensaje de red', () async {
    when(() => client.get<dynamic>(
          any(),
          queryParameters: any(named: 'queryParameters'),
          options: any(named: 'options'),
        )).thenThrow(_http('$_base/financial-summary', 500));

    expect(
      () => repo.getDashboard(period: DashboardPeriod.month, now: _now),
      throwsA(isA<AnalyticsException>()
          .having((e) => e.message, 'message', contains('No se pudo cargar el dashboard'))),
    );
  });

  test('403 se explica como falta de permiso, no como falla de red', () async {
    when(() => client.get<dynamic>(
          any(),
          queryParameters: any(named: 'queryParameters'),
          options: any(named: 'options'),
        )).thenThrow(_http('$_base/financial-summary', 403));

    expect(
      () => repo.getDashboard(period: DashboardPeriod.month, now: _now),
      throwsA(isA<AnalyticsException>()
          .having((e) => e.message, 'message', contains('permiso'))),
    );
  });
}
