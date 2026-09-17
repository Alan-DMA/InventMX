import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/dio_client.dart';
import '../../auth/data/auth_repository.dart';
import '../../inventory/data/inventory_mock_data.dart';
import '../../sales_pos/data/sales_repository.dart';
import '../../sales_pos/domain/cart_state.dart' show RefundedLine;
import '../domain/analytics_dashboard.dart';

// ---------------------------------------------------------------------------
// Contrato
// ---------------------------------------------------------------------------

abstract class AnalyticsDashboardRepository {
  /// `GET /analytics/dashboard?period=` + `GET /analytics/sales-trends`
  /// (granularidad diaria) combinados en un solo modelo para la pantalla.
  Future<AnalyticsDashboard> getDashboard({
    required DashboardPeriod period,
    required DateTime now,
  });
}

// ---------------------------------------------------------------------------
// Mock — activo hasta que Alan entregue Tarea 15.1.3 (analítica avanzada)
// ---------------------------------------------------------------------------

/// Serie sintética **determinista** (semilla fija) construida sobre los 15
/// productos del inventario mock: mismos precios y costos que ve el tendero
/// en Inventario, así el margen del dashboard cuadra con lo que él conoce.
/// Las ventas reales hechas hoy en el POS mock se suman al día de hoy.
class AnalyticsDashboardRepositoryMock implements AnalyticsDashboardRepository {
  AnalyticsDashboardRepositoryMock(
      {this.delay = const Duration(milliseconds: 500)});

  final Duration delay;

  /// Productos vendibles del inventario mock: (nombre, precio, costo).
  static final List<(String, double, double)> _catalog = kMockProductsJson
      .where((p) => (p['price_mxn'] as num) > 0)
      .map((p) => (
            p['name'] as String,
            (p['price_mxn'] as num).toDouble(),
            (p['cost_mxn'] as num).toDouble(),
          ))
      .toList();

  @override
  Future<AnalyticsDashboard> getDashboard({
    required DashboardPeriod period,
    required DateTime now,
  }) async {
    await Future.delayed(delay);

    final today = DateTime(now.year, now.month, now.day);
    final days = switch (period) {
      DashboardPeriod.today => 1,
      DashboardPeriod.week => 7,
      DashboardPeriod.month => 30,
    };
    final start = today.subtract(Duration(days: days - 1));
    final prevStart = start.subtract(Duration(days: days));

    // Ventas por producto: acumulado por período para el Top y el margen.
    final unitsByProduct = <String, int>{};
    final revenueByProduct = <String, double>{};
    final profitByProduct = <String, double>{};
    final daily = <DailySalesPoint>[];
    var previousRevenue = 0.0;

    for (var i = 0; i < days * 2; i++) {
      final day = prevStart.add(Duration(days: i));
      final inCurrent = !day.isBefore(start);
      final sim = _simulateDay(day);
      if (inCurrent) {
        daily.add(DailySalesPoint(
            date: day, revenueMxn: sim.revenue, ordersCount: sim.orders));
        sim.units.forEach((name, qty) {
          unitsByProduct[name] = (unitsByProduct[name] ?? 0) + qty;
          revenueByProduct[name] =
              (revenueByProduct[name] ?? 0) + sim.revenueOf[name]!;
          profitByProduct[name] =
              (profitByProduct[name] ?? 0) + sim.profitOf[name]!;
        });
      } else {
        previousRevenue += sim.revenue;
      }
    }

    // Ventas reales del POS mock hechas hoy en esta sesión.
    final todaysSales = SalesRepositoryMock.todaysSales
        .where((s) => !s.completedAt.isBefore(today))
        .toList();
    if (todaysSales.isNotEmpty && daily.isNotEmpty) {
      final last = daily.last;
      // Neto (decisión de Eduardo, Fase 2 · reembolsos): una venta
      // reembolsada — total o parcial — no infla "vendido hoy".
      final extraRevenue =
          todaysSales.fold<double>(0, (a, s) => a + s.netTotalMxn);
      daily[daily.length - 1] = DailySalesPoint(
        date: last.date,
        revenueMxn: last.revenueMxn + extraRevenue,
        ordersCount: last.ordersCount + todaysSales.length,
      );
      for (final sale in todaysSales) {
        // Cuánto de cada ítem ya se devolvió, para que "Lo más vendido" y
        // el margen tampoco cuenten lo reembolsado.
        final refundedQty = <String, int>{
          for (final line in sale.refund?.lines ?? const <RefundedLine>[])
            line.cartItemId: line.quantity,
        };
        for (final item in sale.items) {
          final netQty = item.quantity - (refundedQty[item.id] ?? 0);
          if (netQty <= 0) continue;
          final cost = _catalog
                  .where((c) => c.$1 == item.name)
                  .map((c) => c.$3)
                  .firstOrNull ??
              item.unitPriceMxn * 0.7;
          final revenue = item.unitPriceMxn * netQty;
          unitsByProduct[item.name] = (unitsByProduct[item.name] ?? 0) + netQty;
          revenueByProduct[item.name] =
              (revenueByProduct[item.name] ?? 0) + revenue;
          profitByProduct[item.name] = (profitByProduct[item.name] ?? 0) +
              (item.unitPriceMxn - cost) * netQty;
        }
      }
    }

    final totalRevenue = daily.fold<double>(0, (a, d) => a + d.revenueMxn);
    final totalOrders = daily.fold<int>(0, (a, d) => a + d.ordersCount);
    final grossProfit = profitByProduct.values.fold<double>(0, (a, v) => a + v);

    final top = unitsByProduct.keys
        .map((name) => TopProduct(
              name: name,
              unitsSold: unitsByProduct[name]!,
              revenueMxn: revenueByProduct[name]!,
              profitMxn: profitByProduct[name]!,
            ))
        .toList()
      ..sort((a, b) => b.revenueMxn.compareTo(a.revenueMxn));

    return AnalyticsDashboard(
      period: period,
      periodStart: start,
      periodEnd: today,
      totalRevenueMxn: totalRevenue,
      totalOrders: totalOrders,
      averageTicketMxn: totalOrders == 0 ? 0 : totalRevenue / totalOrders,
      grossProfitMxn: grossProfit,
      grossMarginPercent:
          totalRevenue == 0 ? 0 : grossProfit / totalRevenue * 100,
      dailySales: daily,
      topProducts: top.take(5).toList(),
      comparison: PeriodComparison(
        currentLabel: _periodLabel(period, current: true),
        previousLabel: _periodLabel(period, current: false),
        currentRevenueMxn: totalRevenue,
        previousRevenueMxn: previousRevenue,
      ),
    );
  }

  static String _periodLabel(DashboardPeriod p, {required bool current}) =>
      switch (p) {
        DashboardPeriod.today => current ? 'Hoy' : 'Ayer',
        DashboardPeriod.week => current ? 'Esta semana' : 'Semana pasada',
        DashboardPeriod.month => current ? 'Este mes' : 'Mes pasado',
      };

  /// Un día simulado: semilla = fecha, para que el mismo día dé siempre lo
  /// mismo entre pantallas y reinicios (nada "cambia solo" en QA).
  static _DaySim _simulateDay(DateTime day) {
    final rng = Random(day.year * 10000 + day.month * 100 + day.day);
    // Fines de semana venden más en la tiendita; martes flojo.
    final weekdayFactor = switch (day.weekday) {
      DateTime.saturday => 1.35,
      DateTime.sunday => 1.2,
      DateTime.tuesday => 0.8,
      _ => 1.0,
    };
    final orders = (18 + rng.nextInt(14)) * weekdayFactor ~/ 1;
    final units = <String, int>{};
    final revenueOf = <String, double>{};
    final profitOf = <String, double>{};
    var revenue = 0.0;
    for (var i = 0; i < orders; i++) {
      final lines = 1 + rng.nextInt(3);
      for (var l = 0; l < lines; l++) {
        final (name, price, cost) = _catalog[rng.nextInt(_catalog.length)];
        final qty = 1 + rng.nextInt(2);
        units[name] = (units[name] ?? 0) + qty;
        revenueOf[name] = (revenueOf[name] ?? 0) + price * qty;
        profitOf[name] = (profitOf[name] ?? 0) + (price - cost) * qty;
        revenue += price * qty;
      }
    }
    return _DaySim(
        orders: orders,
        revenue: revenue,
        units: units,
        revenueOf: revenueOf,
        profitOf: profitOf);
  }
}

class _DaySim {
  const _DaySim({
    required this.orders,
    required this.revenue,
    required this.units,
    required this.revenueOf,
    required this.profitOf,
  });
  final int orders;
  final double revenue;
  final Map<String, int> units;
  final Map<String, double> revenueOf;
  final Map<String, double> profitOf;
}

// ---------------------------------------------------------------------------
// Implementación real — docs/api/analytics.yaml
// ---------------------------------------------------------------------------

class AnalyticsDashboardRepositoryImpl implements AnalyticsDashboardRepository {
  AnalyticsDashboardRepositoryImpl({required this.client});

  final DioClient client;

  static dynamic _unwrap(dynamic body) =>
      body is Map && body.containsKey('data') ? body['data'] : body;

  @override
  Future<AnalyticsDashboard> getDashboard({
    required DashboardPeriod period,
    required DateTime now,
  }) async {
    try {
      final dashboard = await client.get(
        '/api/v1/analytics/dashboard',
        queryParameters: {'period': period.apiValue, 'compare_previous': true},
      );
      final data = _unwrap(dashboard.data);
      if (data is! Map) {
        throw const AnalyticsException('Respuesta inesperada del servidor.');
      }

      final info = (data['period_info'] as Map?) ?? const {};
      List<dynamic> trends = const [];
      try {
        final res = await client.get(
          '/api/v1/analytics/sales-trends',
          queryParameters: {
            'granularity': 'daily',
            if (info['start_date'] != null) 'date_from': info['start_date'],
            if (info['end_date'] != null) 'date_to': info['end_date'],
          },
        );
        final t = _unwrap(res.data);
        if (t is Map && t['trends'] is List) trends = t['trends'] as List;
      } on DioException {
        // La serie es complementaria: sin ella el dashboard sigue sirviendo.
      }
      return AnalyticsDashboard.fromJson(data, period: period, trends: trends);
    } on DioException catch (e) {
      throw AnalyticsException(
        e.response?.statusCode == 403
            ? 'La analítica avanzada está disponible en el plan Corporativo.'
            : 'No se pudo cargar el dashboard. Revisa tu conexión e intenta de nuevo.',
      );
    }
  }
}

class AnalyticsException implements Exception {
  const AnalyticsException(this.message);
  final String message;
  @override
  String toString() => message;
}

// ---------------------------------------------------------------------------
// Provider — mock por defecto (D15). `--dart-define=ANALYTICS_MOCK=false`.
// ---------------------------------------------------------------------------

const bool kAnalyticsUseMock =
    bool.fromEnvironment('ANALYTICS_MOCK', defaultValue: true);

final analyticsDashboardRepositoryProvider =
    Provider<AnalyticsDashboardRepository>((ref) {
  if (kAnalyticsUseMock) return AnalyticsDashboardRepositoryMock();
  return AnalyticsDashboardRepositoryImpl(client: ref.watch(dioClientProvider));
});
