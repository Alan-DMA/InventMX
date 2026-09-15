import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nexus_app/core/router/app_router.dart';
import 'package:nexus_app/features/whatsapp_catalog/data/whatsapp_catalog_repository.dart';
import 'package:nexus_app/features/whatsapp_catalog/domain/whatsapp_order.dart';
import 'package:nexus_app/features/whatsapp_catalog/presentation/order_ticket_screen.dart';
import 'package:nexus_app/features/whatsapp_catalog/presentation/whatsapp_catalog_provider.dart';

/// La pantalla que abre la tienda desde el enlace del chat (13.2.2, iter. 3).
void main() {
  late WhatsappCatalogRepositoryMock repo;

  setUp(() {
    repo = WhatsappCatalogRepositoryMock(
      storeName: 'Abarrotes Don Pepe',
      latency: Duration.zero,
      now: () => DateTime(2026, 9, 14, 12, 39),
    );
  });

  Future<SavedOrder> registerOrder() async {
    final catalog = await repo.fetchPublicCatalog('abarrotes-don-pepe');
    return repo.submitOrder(
      'abarrotes-don-pepe',
      WhatsAppOrderDraft(
        customerName: 'María González',
        deliveryMethod: DeliveryMethod.delivery,
        deliveryAddress: 'Av. Insurgentes 123',
        cashTenderedMxn: 200,
        lines: [
          CartLine(product: catalog.products[0], quantity: 2),
          CartLine(product: catalog.products[1], quantity: 1),
        ],
      ),
    );
  }

  Future<void> pump(WidgetTester tester, String folio) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final router = GoRouter(
      initialLocation: AppRoutes.publicOrderPath('abarrotes-don-pepe', folio),
      routes: [
        GoRoute(
          path: '/tienda/:slug',
          builder: (_, __) => const Scaffold(body: Text('vitrina')),
          routes: [
            GoRoute(
              path: 'pedido/:folio',
              builder: (_, state) => OrderTicketScreen(
                slug: state.pathParameters['slug']!,
                folio: state.pathParameters['folio']!,
              ),
            ),
          ],
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          catalogStoreNameProvider
              .overrideWith((_) async => 'Abarrotes Don Pepe'),
          whatsappCatalogRepositoryProvider.overrideWithValue(repo),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();
  }

  testWidgets('muestra el ticket del pedido registrado', (tester) async {
    // El mock usa Future.delayed: fuera del tiempo simulado del tester.
    final order = (await tester.runAsync(registerOrder))!;
    await pump(tester, order.folio);

    expect(find.byKey(const Key('savedOrderTicket')), findsOneWidget);
    expect(find.text('Pedido ${order.folio}'), findsOneWidget);
    expect(find.text('Folio ${order.folio}'), findsOneWidget);
    expect(find.text('ABARROTES DON PEPE'), findsOneWidget);
    expect(find.text('María González'), findsOneWidget);
    expect(find.text('Av. Insurgentes 123'), findsOneWidget);
    expect(find.text('14/09/2026 12:39'), findsOneWidget);
    // 2 × 18 + 32 + envío 20 = 88; paga con 200 → cambio 112.
    expect(find.text('\$88.00 MXN'), findsOneWidget);
    expect(find.text('\$112.00'), findsOneWidget);
  });

  testWidgets('un folio desconocido lo dice y ofrece el catálogo',
      (tester) async {
    await pump(tester, 'P-000000-0000');

    expect(find.byKey(const Key('orderFailure')), findsOneWidget);
    expect(find.textContaining('No encontramos el pedido P-000000-0000'),
        findsOneWidget);

    await tester.tap(find.text('Ver el catálogo'));
    await tester.pumpAndSettle();
    expect(find.text('vitrina'), findsOneWidget);
  });

  test('publicOrderPath arma el enlace del chat', () {
    expect(AppRoutes.publicOrderPath('abarrotes-don-pepe', 'P-260914-AB6F'),
        '/tienda/abarrotes-don-pepe/pedido/P-260914-AB6F');
  });
}
