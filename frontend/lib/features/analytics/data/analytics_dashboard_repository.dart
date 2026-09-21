import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/dio_client.dart';
import '../../auth/data/auth_repository.dart';
import '../../inventory/data/inventory_mock_data.dart';
import '../../sales_pos/data/sales_repository.dart';
import '../../sales_pos/domain/cart_state.dart' show RefundedLine;
import '../domain/analytics_dashboard.dart';
import 'models/financial_analytics_dto.dart';
import 'models/inventory_analytics_dto.dart';
import 'models/liquidity_analytics_dto.dart';

// ---------------------------------------------------------------------------
// Contrato
// ---------------------------------------------------------------------------

abstract class AnalyticsDashboardRepository {
  /// Dashboard del período que contiene a [now]: ventas netas, utilidad,
  /// comparativa contra el período anterior, serie diaria y lo más vendido.
  Future<AnalyticsDashboard> getDashboard({
    required DashboardPeriod period,
    required DateTime now,
  });
}

// ---------------------------------------------------------------------------
// Mock — sólo para tests y `--dart-define=ANALYTICS_MOCK=true`
// ---------------------------------------------------------------------------

/// Serie sintética **determinista** (semilla fija) construida sobre los 15
/// productos del inventario mock: mismos precios y costos que ve el tendero
/// en Inventario, así el margen del dashboard cuadra con lo que él conoce.
/// Las ventas reales hechas hoy en el POS mock se suman al día de hoy.
/// Períodos de calendario, igual que el backend (D2).
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
    final current = period.range(now);
    final previous = period.previousRange(now);

    // Ventas por producto: acumulado por período para el Top y el margen.
    final unitsByProduct = <String, int>{};
    final revenueByProduct = <String, double>{};
    final profitByProduct = <String, double>{};
    final daily = <DailySalesPoint>[];

    // La serie sólo llega hasta hoy: los días que aún no ocurren no se pintan.
    for (var day = current.start;
        !day.isAfter(today) && !day.isAfter(current.end);
        day = day.add(const Duration(days: 1))) {
      final sim = _simulateDay(day);
      daily.add(DailySalesPoint(
          date: day, revenueMxn: sim.revenue, ordersCount: sim.orders));
      sim.units.forEach((name, qty) {
        unitsByProduct[name] = (unitsByProduct[name] ?? 0) + qty;
        revenueByProduct[name] =
            (revenueByProduct[name] ?? 0) + sim.revenueOf[name]!;
        profitByProduct[name] =
            (profitByProduct[name] ?? 0) + sim.profitOf[name]!;
      });
    }
    var previousRevenue = 0.0;
    for (var day = previous.start;
        !day.isAfter(previous.end);
        day = day.add(const Duration(days: 1))) {
      previousRevenue += _simulateDay(day).revenue;
    }

    // Ventas reales del POS mock hechas hoy en esta sesión.
    var refunds = 0.0;
    final todaysSales = SalesRepositoryMock.todaysSales
        .where((s) => !s.completedAt.isBefore(today))
        .toList();
    if (todaysSales.isNotEmpty && daily.isNotEmpty) {
      final last = daily.last;
      // Neto (decisión de Eduardo, Fase 2 · reembolsos): una venta
      // reembolsada — total o parcial — no infla "vendido hoy".
      final extraRevenue =
          todaysSales.fold<double>(0, (a, s) => a + s.netTotalMxn);
      refunds = todaysSales.fold<double>(
          0, (a, s) => a + (s.refund?.refundAmountMxn ?? 0));
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
      periodStart: current.start,
      periodEnd: current.end,
      totalRevenueMxn: totalRevenue,
      refundsMxn: refunds,
      totalOrders: totalOrders,
      averageTicketMxn: totalOrders == 0 ? 0 : totalRevenue / totalOrders,
      grossProfitMxn: grossProfit,
      grossMarginPercent:
          totalRevenue == 0 ? 0 : grossProfit / totalRevenue * 100,
      dailySales: daily,
      topProducts: top.take(5).toList(),
      comparison: PeriodComparison(
        currentLabel: period.currentLabel,
        previousLabel: period.previousLabel,
        currentRevenueMxn: totalRevenue,
        previousRevenueMxn: previousRevenue,
      ),
      // Reparto típico de una tiendita: casi todo en efectivo.
      paymentMethods: totalRevenue == 0
          ? const []
          : [
              PaymentMethodShare(
                  method: 'CASH_MXN',
                  totalMxn: totalRevenue * 0.72,
                  transactionCount: (totalOrders * 0.72).round(),
                  percentage: 72),
              PaymentMethodShare(
                  method: 'CARD_TPV',
                  totalMxn: totalRevenue * 0.19,
                  transactionCount: (totalOrders * 0.19).round(),
                  percentage: 19),
              PaymentMethodShare(
                  method: 'SPEI',
                  totalMxn: totalRevenue * 0.09,
                  transactionCount: (totalOrders * 0.09).round(),
                  percentage: 9),
            ],
      // Sin fiado: la app no vende a crédito, el mock tampoco lo inventa.
      workingCapital: WorkingCapital(
        asOf: now,
        cashInRegisterMxn: 1500,
        receivableMxn: 0,
        payableMxn: 4120,
        netMxn: 1500 - 4120,
      ),
    );
  }

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
// Implementación real — backend/app/modules/analytics_reports
// ---------------------------------------------------------------------------

/// Compone el dashboard con cuatro lecturas en paralelo:
///
/// | Llamada                                               | Alimenta                    |
/// |-------------------------------------------------------|-----------------------------|
/// | `GET /analytics/financial-summary?preset=<período>`   | Ventas, Ganancia            |
/// | `GET /analytics/financial-summary?preset=CUSTOM&…`    | Comparativa (período previo)|
/// | `GET /analytics/sales-trends?preset=<período>`        | Serie diaria                |
/// | `GET /analytics/inventory-health?preset=<período>`    | Lo más vendido              |
/// | `GET /analytics/working-capital`                      | Tu dinero hoy (Fase B)      |
///
/// El resumen actual es obligatorio (también trae "Cómo te pagan"); las otras
/// cuatro son complementarias: si fallan, la sección correspondiente queda
/// vacía y el dashboard sigue sirviendo (nunca se tumba la pantalla por la
/// gráfica).
class AnalyticsDashboardRepositoryImpl implements AnalyticsDashboardRepository {
  AnalyticsDashboardRepositoryImpl({required this.client});

  final DioClient client;

  static const _base = '/api/v1/analytics';

  static dynamic _unwrap(dynamic body) =>
      body is Map && body.containsKey('data') ? body['data'] : body;

  /// Fechas en ISO local **sin** `Z`, como el historial de ventas: el backend
  /// compara contra `datetime.now()` naive del servidor (probado en QA).
  static Map<String, String> _customRange(DateRange r) => {
        'preset': 'CUSTOM',
        'start_date': DateTime(r.start.year, r.start.month, r.start.day)
            .toIso8601String(),
        'end_date': DateTime(r.end.year, r.end.month, r.end.day, 23, 59, 59, 999)
            .toIso8601String(),
      };

  Future<Map<dynamic, dynamic>> _getMap(
      String path, Map<String, dynamic> query) async {
    final res = await client.get(path, queryParameters: query);
    final data = _unwrap(res.data);
    if (data is! Map) {
      throw const AnalyticsException('Respuesta inesperada del servidor.');
    }
    return data;
  }

  /// Lectura complementaria: cualquier fallo devuelve `null` en vez de
  /// propagarse.
  Future<Map<dynamic, dynamic>?> _tryGetMap(
      String path, Map<String, dynamic> query) async {
    try {
      return await _getMap(path, query);
    } on DioException {
      return null;
    } on AnalyticsException {
      return null;
    }
  }

  @override
  Future<AnalyticsDashboard> getDashboard({
    required DashboardPeriod period,
    required DateTime now,
  }) async {
    final presetQuery = {'preset': period.preset};
    final previous = _customRange(period.previousRange(now));
    try {
      final results = await Future.wait<Map<dynamic, dynamic>?>([
        _getMap('$_base/financial-summary', presetQuery),
        _tryGetMap('$_base/financial-summary', previous),
        _tryGetMap('$_base/sales-trends', presetQuery),
        _tryGetMap('$_base/inventory-health', presetQuery),
        _tryGetMap('$_base/working-capital', const {}),
      ]);

      final summary = ExecutiveFinancialSummaryDto.fromJson(results[0]!);
      final previousSummary = results[1] == null
          ? null
          : ExecutiveFinancialSummaryDto.fromJson(results[1]!);
      final trends =
          results[2] == null ? null : SalesTrendsDto.fromJson(results[2]!);
      final health =
          results[3] == null ? null : InventoryHealthDto.fromJson(results[3]!);
      final capital =
          results[4] == null ? null : WorkingCapitalDto.fromJson(results[4]!);

      return _compose(
        period: period,
        now: now,
        summary: summary,
        previousSummary: previousSummary,
        trends: trends,
        health: health,
        capital: capital,
      );
    } on DioException catch (e) {
      throw AnalyticsException(
        e.response?.statusCode == 403
            ? 'Tu usuario no tiene permiso para ver los reportes del negocio.'
            : 'No se pudo cargar el dashboard. Revisa tu conexión e intenta de nuevo.',
      );
    }
  }

  /// Traduce los DTOs del backend al modelo de pantalla.
  static AnalyticsDashboard _compose({
    required DashboardPeriod period,
    required DateTime now,
    required ExecutiveFinancialSummaryDto summary,
    ExecutiveFinancialSummaryDto? previousSummary,
    SalesTrendsDto? trends,
    InventoryHealthDto? health,
    WorkingCapitalDto? capital,
  }) {
    final range = period.range(now);

    // El backend ordena el Top por unidades y manda 10; la pantalla lee
    // "lo que más dinero dejó": se reordena por ingreso y se corta a 5.
    final top = (health?.topSellingProducts ?? const <TopSellingProductDto>[])
        .map((t) => TopProduct(
              name: t.productName,
              unitsSold: t.unitsSold.round(),
              revenueMxn: t.revenueMxn,
              profitMxn: t.profitMxn,
            ))
        .toList()
      ..sort((a, b) => b.revenueMxn.compareTo(a.revenueMxn));

    return AnalyticsDashboard(
      period: period,
      periodStart: range.start,
      periodEnd: range.end,
      totalRevenueMxn: summary.netSalesMxn,
      refundsMxn: summary.refundsMxn,
      totalOrders: summary.totalTransactions,
      averageTicketMxn: summary.averageTicketMxn,
      grossProfitMxn: summary.grossProfitMxn,
      grossMarginPercent: summary.profitMarginPct,
      dailySales: (trends?.trends ?? const <DailySalesPointDto>[])
          .map((p) => DailySalesPoint(
                date: DateTime(p.period.year, p.period.month, p.period.day),
                revenueMxn: p.revenueMxn,
                ordersCount: p.ordersCount,
              ))
          .toList(),
      topProducts: top.take(5).toList(),
      comparison: PeriodComparison(
        currentLabel: period.currentLabel,
        previousLabel: period.previousLabel,
        currentRevenueMxn: summary.netSalesMxn,
        // Sin lectura del período anterior no hay base: la pantalla dice
        // "Sin base de comparación" en vez de inventar un +100 %.
        previousRevenueMxn: previousSummary?.netSalesMxn ?? 0,
      ),
      paymentMethods: summary.paymentMethods
          .map((m) => PaymentMethodShare(
                method: m.paymentMethod,
                totalMxn: m.totalMxn,
                transactionCount: m.transactionCount,
                percentage: m.percentage,
              ))
          .toList()
        ..sort((a, b) => b.totalMxn.compareTo(a.totalMxn)),
      workingCapital: capital == null
          ? null
          : WorkingCapital(
              asOf: capital.asOfDate,
              cashInRegisterMxn: capital.cashInRegisterMxn,
              receivableMxn: capital.accountsReceivableMxn,
              payableMxn: capital.accountsPayableMxn,
              netMxn: capital.netWorkingCapitalMxn,
            ),
    );
  }
}

class AnalyticsException implements Exception {
  const AnalyticsException(this.message);
  final String message;
  @override
  String toString() => message;
}

// ---------------------------------------------------------------------------
// Provider — real por defecto (D3, Sep 2026): el backend de analítica existe.
// `--dart-define=ANALYTICS_MOCK=true` vuelve al mock determinista.
// ---------------------------------------------------------------------------

const bool kAnalyticsUseMock =
    bool.fromEnvironment('ANALYTICS_MOCK', defaultValue: false);

final analyticsDashboardRepositoryProvider =
    Provider<AnalyticsDashboardRepository>((ref) {
  if (kAnalyticsUseMock) return AnalyticsDashboardRepositoryMock();
  return AnalyticsDashboardRepositoryImpl(client: ref.watch(dioClientProvider));
});
