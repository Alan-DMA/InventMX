import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_app/core/theme/app_theme.dart';
import 'package:nexus_app/features/cash_treasury/domain/cash_movement.dart';
import 'package:nexus_app/features/cash_treasury/presentation/widgets/cash_movements_list_box.dart';

List<CashMovement> _makeMovements(int count) {
  return List.generate(
    count,
    (i) => CashMovement(
      id: 'mov-$i',
      cashSessionId: 'cash-1',
      type: i.isEven ? CashMovementType.withdrawal : CashMovementType.deposit,
      amountMxn: 10.0 * (i + 1),
      description: 'Movimiento $i',
      createdAt: DateTime(2026, 9, 15, 12, i),
    ),
  );
}

Widget _buildBox(List<CashMovement> movements) {
  return MaterialApp(
    theme: AppTheme.dark,
    home: Scaffold(body: CashMovementsListBox(movements: movements)),
  );
}

void main() {
  testWidgets('con 4 movimientos o menos se muestran todos sin scroll interno', (tester) async {
    final movements = _makeMovements(4);
    await tester.pumpWidget(_buildBox(movements));
    await tester.pump();

    // Lista simple (Column) — sin ListView ni límite de alto.
    expect(find.byType(ListView), findsNothing);
    for (final m in movements) {
      expect(find.text(m.description), findsOneWidget);
    }
  });

  testWidgets('con más de 4 movimientos activa scroll interno con altura acotada',
      (tester) async {
    final movements = _makeMovements(8);
    await tester.pumpWidget(_buildBox(movements));
    await tester.pump();

    expect(find.byType(ListView), findsOneWidget);

    final constrainedBox = tester.widget<ConstrainedBox>(
      find.ancestor(of: find.byType(ListView), matching: find.byType(ConstrainedBox)).first,
    );
    // La altura queda acotada (no crece indefinidamente con el número de
    // movimientos) — nunca "sin límite" (double.infinity).
    expect(constrainedBox.constraints.maxHeight.isFinite, isTrue);
    expect(constrainedBox.constraints.maxHeight, lessThan(8 * 53.0));

    // Al menos las primeras filas (visibles en el alto acotado) siguen
    // siendo legibles sin necesidad de scrollear la pantalla contenedora.
    expect(find.text('Movimiento 0'), findsOneWidget);
  });
}
