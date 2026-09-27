// Aislamiento por almacén — Fase 2 (Sep 27): ventas, Inicio y Reportes
// mandan el alcance elegido en la leyenda (`null` = todos). A quien no puede
// ver todos el servidor le fija su almacén; aquí se prueba que el cliente
// manda lo elegido y que las alertas de "todos" llegan rotuladas (D38).
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nexus_app/core/network/dio_client.dart';
import 'package:nexus_app/features/analytics/data/analytics_dashboard_repository.dart';
import 'package:nexus_app/features/analytics/domain/analytics_dashboard.dart';
import 'package:nexus_app/features/dashboard/data/dashboard_repository.dart';
import 'package:nexus_app/features/dashboard/domain/stock_alert.dart';
import 'package:nexus_app/features/sales_pos/data/sales_repository.dart';

class _MockDioClient extends Mock implements DioClient {}

Response<dynamic> _ok(dynamic data) =>
    Response(data: data, statusCode: 200, requestOptions: RequestOptions());

/// Captura `path → queryParameters` de cada GET.
Map<String, List<Map<String, dynamic>>> _stubAll(_MockDioClient client,
    dynamic Function(String path) body) {
  final calls = <String, List<Map<String, dynamic>>>{};
  when(() => client.get<dynamic>(
        any(),
        queryParameters: any(named: 'queryParameters'),
        options: any(named: 'options'),
      )).thenAnswer((inv) async {
    final path = inv.positionalArguments.first as String;
    final query = (inv.namedArguments[#queryParameters] as Map?)
            ?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    calls.putIfAbsent(path, () => []).add(query);
    return _ok(body(path));
  });
  when(() => client.get(
        any(),
        queryParameters: any(named: 'queryParameters'),
        options: any(named: 'options'),
      )).thenAnswer((inv) async {
    final path = inv.positionalArguments.first as String;
    final query = (inv.namedArguments[#queryParameters] as Map?)
            ?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    calls.putIfAbsent(path, () => []).add(query);
    return _ok(body(path));
  });
  return calls;
}

void main() {
  test('el historial de ventas manda el almacén elegido', () async {
    final client = _MockDioClient();
    final calls = _stubAll(client, (_) => const []);
    String? scope = 'wh-2';
    final repo = SalesRepositoryImpl(client: client, resolveScope: () => scope);

    await repo.getSales();
    expect(calls['/api/v1/sales']!.last['warehouse_id'], 'wh-2');

    scope = null;
    await repo.getSales();
    expect(calls['/api/v1/sales']!.last.containsKey('warehouse_id'), isFalse);
  });

  test('Reportes manda el almacén a todas sus consultas', () async {
    final client = _MockDioClient();
    final calls = _stubAll(client, (_) => const <String, dynamic>{});
    final repo = AnalyticsDashboardRepositoryImpl(
      client: client,
      resolveScope: () => 'wh-2',
    );

    try {
      await repo.getDashboard(
          period: DashboardPeriod.today, now: DateTime(2026, 9, 27, 12));
    } catch (_) {
      // Las respuestas vacías no arman un tablero válido; aquí sólo importa
      // qué se pidió.
    }

    for (final path in [
      '/api/v1/analytics/financial-summary',
      '/api/v1/analytics/sales-trends',
      '/api/v1/analytics/inventory-health',
      '/api/v1/analytics/working-capital',
    ]) {
      expect(calls[path], isNotNull, reason: path);
      for (final q in calls[path]!) {
        expect(q['warehouse_id'], 'wh-2', reason: path);
      }
    }
  });

  test('el Inicio manda el alcance al resumen y a "por pagar"', () async {
    final client = _MockDioClient();
    final calls = _stubAll(client, (path) {
      if (path.endsWith('/summary')) {
        return {'total_pending_mxn': '120.00', 'overdue_count': 0};
      }
      return {
        'sales_metrics': {'total_revenue_mxn': '36.00', 'total_orders': 1},
        'profitability': {'gross_profit_mxn': '12.00'},
        'inventory_metrics': {'low_stock_alerts': 1},
        'critical_stock_alerts': [
          {
            'product_id': 'p-1',
            'product_name': 'Coca-Cola 600ml',
            'sku': 'NEX-1',
            'warehouse_id': 'wh-1',
            'warehouse_name': 'Almacén Principal',
            'current_stock': '3.00',
            'min_stock': '5.00',
            'is_out_of_stock': false,
          },
        ],
      };
    });
    final repo = DashboardRepositoryImpl(
      client: client,
      resolveWarehouseScope: () async => 'wh-2',
    );

    final snapshot = await repo.getTodaySnapshot();

    expect(calls['/api/v1/analytics/dashboard']!.last['warehouse_id'], 'wh-2');
    expect(calls['/api/v1/accounts-payable/summary']!.last['warehouse_id'],
        'wh-2');
    final alert = snapshot.lowStockAlerts.single;
    expect(alert.warehouseName, 'Almacén Principal');
  });

  test('una alerta se identifica por producto y almacén (D38)', () {
    StockAlertItem alert(String warehouse) => StockAlertItem.fromJson({
          'product_id': 'p-1',
          'product_name': 'Coca-Cola 600ml',
          'warehouse_id': warehouse,
          'warehouse_name': warehouse,
          'current_stock': 2,
          'min_stock': 5,
        });

    expect(alert('wh-1').alertKey, isNot(alert('wh-2').alertKey));
    expect(alert('wh-1'), isNot(alert('wh-2')));
  });
}
