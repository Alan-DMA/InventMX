import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_app/core/theme/app_theme.dart';
import 'package:nexus_app/features/sales_pos/data/sales_repository.dart';
import 'package:nexus_app/features/sales_pos/domain/cart_item.dart';
import 'package:nexus_app/features/sales_pos/domain/cart_state.dart';
import 'package:nexus_app/features/sales_pos/domain/payment_entry.dart';
import 'package:nexus_app/features/sales_pos/presentation/widgets/refund_sale_modal.dart';

// ---------------------------------------------------------------------------
// Fase 2 — Acciones sobre la venta: RefundSaleModal
// ---------------------------------------------------------------------------

final _sale = CheckoutResult(
  saleId: 'sale-1',
  folio: 'NV-2026-000001',
  totalMxn: 89,
  totalPaidMxn: 100,
  changeGivenMxn: 11,
  items: const [
    CartItem(id: 'ci-1', name: 'Coca-Cola 600 ml', unitPriceMxn: 18, quantity: 3),
    CartItem(id: 'ci-2', name: 'Sabritas 45 g', unitPriceMxn: 17, quantity: 1),
  ],
  payments: const [
    PaymentEntry(id: 'p1', method: PaymentMethodMxn.cashMxn, amountMxn: 100),
  ],
  cashierName: 'Eduardo',
  completedAt: DateTime(2026, 9, 17, 12),
);

class _RecordingRepo implements SalesRepository {
  CheckoutResult? refunded;
  Object? throwOnRefund;

  @override
  Future<CheckoutResult> checkout({
    required List<CartItem> items,
    required List<PaymentEntry> payments,
    required String cashierName,
  }) =>
      throw UnimplementedError();

  @override
  Future<List<String>> getCashiers() => throw UnimplementedError();

  @override
  Future<CheckoutResult> getSaleById(String id) => throw UnimplementedError();

  @override
  Future<PaginatedSales> getSales({
    SalesQuery query = const SalesQuery(),
    int page = 1,
    int pageSize = 20,
  }) =>
      throw UnimplementedError();

  @override
  Future<CheckoutResult> refundSale({
    required String saleId,
    required String reason,
    required bool refundToStock,
    List<RefundedLine>? itemsToRefund,
  }) async {
    if (throwOnRefund != null) throw throwOnRefund!;
    final lines = itemsToRefund ??
        _sale.items
            .map((i) => RefundedLine(cartItemId: i.id, quantity: i.quantity))
            .toList();
    var amount = 0.0;
    for (final line in lines) {
      final item = _sale.items.firstWhere((i) => i.id == line.cartItemId);
      amount += item.unitPriceMxn * line.quantity;
    }
    final updated = _sale.copyWith(
      refund: SaleRefund(
        refundedAt: DateTime(2026, 9, 17, 13),
        reason: reason,
        refundAmountMxn: amount,
        refundToStock: refundToStock,
        lines: lines,
      ),
    );
    refunded = updated;
    return updated;
  }
}

Future<CheckoutResult?> _pump(
  WidgetTester tester,
  _RecordingRepo repo, {
  CheckoutResult? sale,
}) async {
  CheckoutResult? result;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [salesRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(
        theme: AppTheme.dark,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  result = await showRefundSaleModal(context, sale: sale ?? _sale);
                },
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('abrir'));
  await tester.pumpAndSettle();
  return result;
}

void main() {
  testWidgets('el botón queda deshabilitado sin selección ni motivo', (tester) async {
    await _pump(tester, _RecordingRepo());

    final button = tester.widget<ElevatedButton>(
      find.byKey(const Key('confirmRefundButton')),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('"Reembolsar todo" sube todos los contadores al máximo', (tester) async {
    await _pump(tester, _RecordingRepo());

    await tester.tap(find.byKey(const Key('refundAllButton')));
    await tester.pumpAndSettle();

    // 3 + 1 unidades = $54 + $17 = $71.
    expect(find.text('\$71.00'), findsOneWidget);
  });

  testWidgets('un contador no pasa de la cantidad original', (tester) async {
    await _pump(tester, _RecordingRepo());

    final addButtons = find.descendant(
      of: find.byType(RefundSaleModal),
      matching: find.byIcon(Icons.add_rounded),
    );
    // Segundo ítem (Sabritas) tiene cantidad original 1.
    for (var i = 0; i < 3; i++) {
      await tester.tap(addButtons.last);
      await tester.pump();
    }
    expect(find.text('\$17.00'), findsOneWidget);
  });

  testWidgets('confirmar llama al repositorio y cierra la hoja con el resultado',
      (tester) async {
    final repo = _RecordingRepo();
    final result = await _pump(tester, repo);
    expect(result, isNull); // aún no se confirma nada

    await tester.tap(find.byKey(const Key('refundAllButton')));
    await tester.enterText(
      find.byKey(const Key('refundReasonField')),
      'Cliente se arrepintió',
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('confirmRefundButton')));
    await tester.pumpAndSettle();

    expect(repo.refunded, isNotNull);
    expect(repo.refunded!.isRefunded, isTrue);
    expect(find.byType(RefundSaleModal), findsNothing);
  });

  testWidgets('reembolso ya aplicado muestra el error inline sin cerrar la hoja',
      (tester) async {
    final repo = _RecordingRepo()..throwOnRefund = const SaleAlreadyRefundedException('sale-1');
    await _pump(tester, repo);

    await tester.tap(find.byKey(const Key('refundAllButton')));
    await tester.enterText(find.byKey(const Key('refundReasonField')), 'x');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirmRefundButton')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('refundErrorBanner')), findsOneWidget);
    expect(find.text('Esta venta ya fue reembolsada.'), findsOneWidget);
    expect(find.byType(RefundSaleModal), findsOneWidget);
  });
}
