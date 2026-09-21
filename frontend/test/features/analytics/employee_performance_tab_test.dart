import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_app/core/theme/app_theme.dart';
import 'package:nexus_app/features/analytics/domain/employee_performance.dart';
import 'package:nexus_app/features/analytics/presentation/widgets/employee_performance_tab.dart';

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

EmployeePerformance _makePerformance({
  List<DailyCommissionEntry> dailyBreakdown = const [],
  List<MonthlyCommissionEntry> history = const [],
  double commissionRatePercent = 5.0,
  CommissionType commissionType = CommissionType.percentageSale,
}) {
  return EmployeePerformance(
    cashierName: 'Ana García',
    role: 'Vendedor',
    periodLabel: 'Hoy · 10/09/2026',
    totalSalesMxn: 964.0,
    accumulatedCommissionMxn: 48.20,
    commissionRatePercent: commissionRatePercent,
    commissionType: commissionType,
    dailyBreakdown: dailyBreakdown,
    history: history,
  );
}

Widget _buildTab(
  EmployeePerformance performance, {
  DateTime? selectedMonth,
  ValueChanged<DateTime>? onMonthTap,
}) {
  return MaterialApp(
    theme: AppTheme.dark,
    home: Scaffold(
      body: SingleChildScrollView(
        child: EmployeePerformanceTab(
          performance: performance,
          onPeriodTap: () {},
          selectedMonth: selectedMonth,
          onMonthTap: onMonthTap,
        ),
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  testWidgets('muestra nombre, rol y período del vendedor', (tester) async {
    await tester.pumpWidget(_buildTab(_makePerformance()));

    expect(find.text('Ana García'), findsOneWidget);
    expect(find.text('Vendedor'), findsOneWidget);
    expect(find.text('Hoy · 10/09/2026'), findsOneWidget);
    // Iniciales del avatar
    expect(find.text('AG'), findsOneWidget);
  });

  testWidgets('muestra la comisión acumulada y las ventas del período',
      (tester) async {
    await tester.pumpWidget(_buildTab(_makePerformance()));

    expect(find.text('\$48.20'), findsOneWidget);
    expect(find.text('\$964.00'), findsOneWidget);
    expect(find.text('Tasa comisión: 5% sobre ventas'), findsOneWidget);
  });

  testWidgets('lista el desglose diario con ventas y comisión',
      (tester) async {
    await tester.pumpWidget(_buildTab(_makePerformance(dailyBreakdown: [
      DailyCommissionEntry(
        date: DateTime(2026, 7, 2),
        salesCount: 14,
        commissionMxn: 12.40,
      ),
    ])));

    expect(find.text('02/07'), findsOneWidget);
    expect(find.text('14 ventas'), findsOneWidget);
    expect(find.text('+\$12.40'), findsOneWidget);
  });

  testWidgets('muestra estado vacío cuando no hay ventas hoy', (tester) async {
    await tester.pumpWidget(_buildTab(_makePerformance()));

    expect(find.text('Aún no hay ventas registradas hoy.'), findsOneWidget);
  });

  testWidgets('"Tu histórico" lista los meses del propio vendedor y resalta el seleccionado',
      (tester) async {
    DateTime? tapped;
    await tester.pumpWidget(_buildTab(
      _makePerformance(history: [
        MonthlyCommissionEntry(month: DateTime(2026, 9), salesCount: 14, commissionMxn: 48.20),
        MonthlyCommissionEntry(month: DateTime(2026, 8), salesCount: 3, commissionMxn: 12.5),
        MonthlyCommissionEntry(month: DateTime(2026, 7), salesCount: 0, commissionMxn: 0),
      ]),
      selectedMonth: DateTime(2026, 9),
      onMonthTap: (m) => tapped = m,
    ));

    expect(find.text('Tu histórico'), findsOneWidget);
    expect(find.text('Ranking del Período'), findsNothing);
    expect(find.text('sep 2026'), findsOneWidget);
    expect(find.text('ago 2026'), findsOneWidget);
    expect(find.text('jul 2026'), findsOneWidget);
    expect(find.text('14 ventas'), findsOneWidget);
    expect(find.text('0 ventas'), findsOneWidget);
    expect(find.text(r'$12.50'), findsOneWidget);
    // Sin nombres de otros vendedores: sólo el del encabezado.
    expect(find.text('Ana García'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('history-2026-8')));
    await tester.tap(find.byKey(const Key('history-2026-8')));
    expect(tapped, DateTime(2026, 8));
  });

  testWidgets('la tarjeta de tasa describe el esquema; sin tasa lo dice', (tester) async {
    await tester.pumpWidget(_buildTab(_makePerformance(
      commissionRatePercent: 15,
      commissionType: CommissionType.fixedPerSale,
    )));
    expect(find.text(r'Tasa comisión: $15.00 por ticket'), findsOneWidget);

    await tester.pumpWidget(_buildTab(_makePerformance(commissionRatePercent: 0)));
    expect(find.text('Sin esquema de comisión configurado para tu usuario.'), findsOneWidget);
    expect(find.textContaining('Tasa comisión'), findsNothing);
  });
}
