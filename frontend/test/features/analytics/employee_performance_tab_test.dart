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
  List<RankingEntry> ranking = const [],
}) {
  return EmployeePerformance(
    cashierName: 'Ana García',
    role: 'Vendedor',
    periodLabel: 'Hoy · 10/09/2026',
    totalSalesMxn: 964.0,
    accumulatedCommissionMxn: 48.20,
    commissionRatePercent: 5.0,
    dailyBreakdown: dailyBreakdown,
    ranking: ranking,
  );
}

Widget _buildTab(EmployeePerformance performance) {
  return MaterialApp(
    theme: AppTheme.dark,
    home: Scaffold(
      body: SingleChildScrollView(
        child: EmployeePerformanceTab(
          performance: performance,
          onPeriodTap: () {},
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
    expect(find.text('Tasa comisión: 5% sobre volumen'), findsOneWidget);
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

  testWidgets('resalta al usuario actual en el ranking con la etiqueta (yo)',
      (tester) async {
    await tester.pumpWidget(_buildTab(_makePerformance(ranking: const [
      RankingEntry(cashierName: 'María López', commissionMxn: 62.0),
      RankingEntry(
        cashierName: 'Ana García',
        commissionMxn: 48.20,
        isCurrentUser: true,
      ),
      RankingEntry(cashierName: 'Juan Torres', commissionMxn: 31.50),
    ])));

    expect(find.text('María López'), findsOneWidget);
    expect(find.text('Juan Torres'), findsOneWidget);
    expect(find.text('(yo)'), findsOneWidget);
    // "Ana García" aparece en el encabezado Y en la fila de ranking
    expect(find.text('Ana García'), findsNWidgets(2));
  });
}
