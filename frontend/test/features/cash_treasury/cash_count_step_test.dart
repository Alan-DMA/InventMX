import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_app/core/theme/app_theme.dart';
import 'package:nexus_app/features/cash_treasury/domain/banxico_denomination.dart';
import 'package:nexus_app/features/cash_treasury/domain/cash_denomination_entry.dart';
import 'package:nexus_app/features/cash_treasury/presentation/widgets/cash_count_step.dart';

// ---------------------------------------------------------------------------
// Helper de montaje — mantiene el estado de `entries` en el test para
// simular exactamente lo que hace `CloseSessionWizard` (dueño del estado).
// ---------------------------------------------------------------------------

class _Harness extends StatefulWidget {
  const _Harness({this.initialEntries = const []});

  final List<CashDenominationEntry> initialEntries;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  late List<CashDenominationEntry> entries = List.of(widget.initialEntries);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(
        // Altura acotada — igual que en producción (`CloseSessionWizard` le
        // da altura vía `Expanded`): el widget reparte fijo/scroll interno.
        body: SizedBox(
          height: 700,
          child: CashCountStep(
            entries: entries,
            onAdd: (denomination, quantity) {
              setState(() {
                final i = entries.indexWhere(
                    (e) => e.denomination.apiKey == denomination.apiKey);
                if (i >= 0) {
                  entries[i] = entries[i].copyWith(
                      quantity: entries[i].quantity + quantity);
                } else {
                  entries = [
                    ...entries,
                    CashDenominationEntry(denomination: denomination, quantity: quantity),
                  ];
                }
              });
            },
            onRemove: (apiKey) {
              setState(() {
                entries = entries.where((e) => e.denomination.apiKey != apiKey).toList();
              });
            },
            onClearAll: () => setState(() => entries = []),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  testWidgets('estado inicial muestra el tipo Billete y denominación \$1000',
      (tester) async {
    await tester.pumpWidget(const _Harness());

    expect(find.text('Billete'), findsOneWidget);
    expect(find.text('\$1000'), findsOneWidget);
    expect(find.text('Aún no agregas ninguna denominación'), findsOneWidget);
  });

  testWidgets('agregar una denominación la suma al desglose', (tester) async {
    await tester.pumpWidget(const _Harness());

    await tester.enterText(find.byType(TextField), '3');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Agregar'));
    await tester.pump();

    expect(find.text('Cantidad: 3 uds'), findsOneWidget);
    expect(find.text('\$3000.00'), findsOneWidget); // 1000 * 3
    expect(find.text('Aún no agregas ninguna denominación'), findsNothing);
  });

  testWidgets('agregar la misma denominación dos veces acumula la cantidad',
      (tester) async {
    await tester.pumpWidget(const _Harness());

    await tester.enterText(find.byType(TextField), '2');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Agregar'));
    await tester.pump();

    await tester.enterText(find.byType(TextField), '1');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Agregar'));
    await tester.pump();

    // Una sola fila con cantidad acumulada (2 + 1 = 3), no dos filas separadas.
    expect(find.text('Cantidad: 3 uds'), findsOneWidget);
    expect(find.text('Cantidad: 1 ud'), findsNothing);
  });

  testWidgets('eliminar una fila la quita del desglose', (tester) async {
    await tester.pumpWidget(const _Harness(initialEntries: [
      CashDenominationEntry(
        denomination: BanxicoDenomination(
            value: 500, kind: DenominationKind.bill, apiKey: 'bills_500'),
        quantity: 2,
      ),
    ]));

    expect(find.text('Cantidad: 2 uds'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.delete_outline_rounded));
    await tester.pump();

    expect(find.text('Cantidad: 2 uds'), findsNothing);
    expect(find.text('Aún no agregas ninguna denominación'), findsOneWidget);
  });

  testWidgets('cambiar el tipo a Moneda actualiza las opciones de valor',
      (tester) async {
    await tester.pumpWidget(const _Harness());

    await tester.tap(find.text('Billete'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Moneda').last);
    await tester.pumpAndSettle();

    // El valor por defecto de Moneda es $20 (primero del catálogo de monedas)
    expect(find.text('\$20'), findsWidgets);
  });

  testWidgets('vaciar todo limpia el desglose tras confirmar', (tester) async {
    await tester.pumpWidget(const _Harness(initialEntries: [
      CashDenominationEntry(
        denomination: BanxicoDenomination(
            value: 100, kind: DenominationKind.bill, apiKey: 'bills_100'),
        quantity: 1,
      ),
    ]));

    await tester.tap(find.text('Vaciar todo'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Vaciar'));
    await tester.pumpAndSettle();

    expect(find.text('Aún no agregas ninguna denominación'), findsOneWidget);
  });
}
