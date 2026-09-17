import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nexus_app/core/theme/app_theme.dart';
import 'package:nexus_app/features/inventory/data/inventory_repository.dart';
import 'package:nexus_app/features/inventory/domain/product.dart';
import 'package:nexus_app/features/inventory/presentation/inventory_provider.dart';
import 'package:nexus_app/features/inventory/presentation/widgets/adjust_stock_modal.dart';
import 'package:nexus_app/features/inventory/presentation/widgets/kardex_bottom_sheet.dart';

class MockInventoryRepository extends Mock implements InventoryRepository {}

void main() {
  testWidgets('pressing back button dismisses KardexBottomSheet without popping underlying screen', (tester) async {
    final mockRepo = MockInventoryRepository();
    when(() => mockRepo.getProducts(
      query: any(named: 'query'),
      category: any(named: 'category'),
      lowStock: any(named: 'lowStock'),
      page: any(named: 'page'),
      pageSize: any(named: 'pageSize'),
    )).thenAnswer((_) async => const PaginatedProducts(
      items: [], total: 0, page: 1, pageSize: 20, totalPages: 1,
    ));

    when(() => mockRepo.getMovements(
      productId: any(named: 'productId'),
      movementType: any(named: 'movementType'),
      dateFrom: any(named: 'dateFrom'),
      dateTo: any(named: 'dateTo'),
      page: any(named: 'page'),
      pageSize: any(named: 'pageSize'),
    )).thenAnswer((_) async => const PaginatedMovements(
      items: [], total: 0, page: 1, pageSize: 20, totalPages: 1,
    ));

    final router = GoRouter(
      initialLocation: '/inventory',
      routes: [
        StatefulShellRoute.indexedStack(
          builder: (context, state, navigationShell) => Scaffold(
            body: navigationShell,
            bottomNavigationBar: const Text('NavBar'),
          ),
          branches: [
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/inventory',
                  builder: (context, state) => Scaffold(
                    body: ElevatedButton(
                      onPressed: () => context.push('/inventory/detail'),
                      child: const Text('Go to Detail'),
                    ),
                  ),
                  routes: [
                    GoRoute(
                      path: 'detail',
                      builder: (context, state) => Scaffold(
                        appBar: AppBar(title: const Text('Detail Screen')),
                        body: ElevatedButton(
                          onPressed: () => showKardexBottomSheet(
                            context,
                            productId: 'p1',
                            productName: 'Producto Test',
                          ),
                          child: const Text('Abrir Kardex'),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          inventoryRepositoryProvider.overrideWithValue(mockRepo),
        ],
        child: MaterialApp.router(
          theme: AppTheme.dark,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 1. Initial screen: Inventory
    expect(find.text('Go to Detail'), findsOneWidget);

    // 2. Navigate to Detail
    await tester.tap(find.text('Go to Detail'));
    await tester.pumpAndSettle();
    expect(find.text('Detail Screen'), findsOneWidget);
    expect(find.text('Abrir Kardex'), findsOneWidget);

    // 3. Open Kardex BottomSheet
    await tester.tap(find.text('Abrir Kardex'));
    await tester.pumpAndSettle();
    expect(find.text('Movimientos'), findsOneWidget);

    // 4. Trigger system back button
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    final detailCount = find.text('Detail Screen').evaluate().length;
    final inventoryCount = find.text('Go to Detail').evaluate().length;
    final kardexCount = find.text('Movimientos').evaluate().length;
    print('DEBUG: detailCount=$detailCount, inventoryCount=$inventoryCount, kardexCount=$kardexCount');

    // 5. Verification after 1st back press:
    // Kardex should be closed, Detail Screen should still be open!
    expect(find.text('Movimientos'), findsNothing, reason: 'Kardex modal should be closed');
    expect(find.text('Detail Screen'), findsOneWidget, reason: 'Detail screen should NOT have been popped');

    // 6. Trigger system back button a 2nd time
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    // Verification after 2nd back press:
    // Detail screen should now pop back to Inventory screen!
    expect(find.text('Detail Screen'), findsNothing, reason: 'Detail screen should now be closed');
    expect(find.text('Go to Detail'), findsOneWidget, reason: 'Should be back at Inventory screen');
  });

  testWidgets('back button closes filter panel first when open, then dismisses modal', (tester) async {
    final mockRepo = MockInventoryRepository();
    when(() => mockRepo.getProducts(
      query: any(named: 'query'),
      category: any(named: 'category'),
      lowStock: any(named: 'lowStock'),
      page: any(named: 'page'),
      pageSize: any(named: 'pageSize'),
    )).thenAnswer((_) async => const PaginatedProducts(
      items: [], total: 0, page: 1, pageSize: 20, totalPages: 1,
    ));

    when(() => mockRepo.getMovements(
      productId: any(named: 'productId'),
      movementType: any(named: 'movementType'),
      dateFrom: any(named: 'dateFrom'),
      dateTo: any(named: 'dateTo'),
      page: any(named: 'page'),
      pageSize: any(named: 'pageSize'),
    )).thenAnswer((_) async => const PaginatedMovements(
      items: [], total: 0, page: 1, pageSize: 20, totalPages: 1,
    ));

    final router = GoRouter(
      initialLocation: '/inventory/detail',
      routes: [
        StatefulShellRoute.indexedStack(
          builder: (context, state, navigationShell) => Scaffold(
            body: navigationShell,
          ),
          branches: [
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/inventory/detail',
                  builder: (context, state) => Scaffold(
                    appBar: AppBar(title: const Text('Detail Screen')),
                    body: ElevatedButton(
                      onPressed: () => showKardexBottomSheet(
                        context,
                        productId: 'p1',
                        productName: 'Producto Test',
                      ),
                      child: const Text('Abrir Kardex'),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          inventoryRepositoryProvider.overrideWithValue(mockRepo),
        ],
        child: MaterialApp.router(
          theme: AppTheme.dark,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Open Kardex
    await tester.tap(find.text('Abrir Kardex'));
    await tester.pumpAndSettle();
    expect(find.text('Movimientos'), findsOneWidget);

    // Open filter panel
    await tester.tap(find.byIcon(Icons.filter_list_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Todos los tipos'), findsOneWidget);

    // 1st back press: should close filter panel only
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Todos los tipos'), findsNothing);
    expect(find.text('Movimientos'), findsOneWidget);

    // 2nd back press: should dismiss Kardex bottom sheet
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Movimientos'), findsNothing);
    expect(find.text('Detail Screen'), findsOneWidget);
  });

  testWidgets('close button in header dismisses KardexBottomSheet', (tester) async {
    final mockRepo = MockInventoryRepository();
    when(() => mockRepo.getProducts(
      query: any(named: 'query'),
      category: any(named: 'category'),
      lowStock: any(named: 'lowStock'),
      page: any(named: 'page'),
      pageSize: any(named: 'pageSize'),
    )).thenAnswer((_) async => const PaginatedProducts(
      items: [], total: 0, page: 1, pageSize: 20, totalPages: 1,
    ));

    when(() => mockRepo.getMovements(
      productId: any(named: 'productId'),
      movementType: any(named: 'movementType'),
      dateFrom: any(named: 'dateFrom'),
      dateTo: any(named: 'dateTo'),
      page: any(named: 'page'),
      pageSize: any(named: 'pageSize'),
    )).thenAnswer((_) async => const PaginatedMovements(
      items: [], total: 0, page: 1, pageSize: 20, totalPages: 1,
    ));

    final router = GoRouter(
      initialLocation: '/inventory/detail',
      routes: [
        StatefulShellRoute.indexedStack(
          builder: (context, state, navigationShell) => Scaffold(
            body: navigationShell,
          ),
          branches: [
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/inventory/detail',
                  builder: (context, state) => Scaffold(
                    appBar: AppBar(title: const Text('Detail Screen')),
                    body: ElevatedButton(
                      onPressed: () => showKardexBottomSheet(
                        context,
                        productId: 'p1',
                        productName: 'Producto Test',
                      ),
                      child: const Text('Abrir Kardex'),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          inventoryRepositoryProvider.overrideWithValue(mockRepo),
        ],
        child: MaterialApp.router(
          theme: AppTheme.dark,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Open Kardex
    await tester.tap(find.text('Abrir Kardex'));
    await tester.pumpAndSettle();
    expect(find.text('Movimientos'), findsOneWidget);

    // Tap Close 'X' button
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();

    expect(find.text('Movimientos'), findsNothing);
    expect(find.text('Detail Screen'), findsOneWidget);
  });

  testWidgets('back button dismisses AdjustStockModal without popping Detail Screen', (tester) async {
    final product = Product(
      id: 'p1',
      sku: 'SKU-001',
      name: 'Coca Cola',
      category: 'Bebidas',
      stock: 10,
      reservedStock: 0,
      availableStock: 10,
      costMxn: 15.0,
      priceMxn: 20.0,
      isOnCatalog: true,
      isActive: true,
      createdAt: DateTime.now(),
    );

    final router = GoRouter(
      initialLocation: '/inventory/detail',
      routes: [
        StatefulShellRoute.indexedStack(
          builder: (context, state, navigationShell) => Scaffold(
            body: navigationShell,
          ),
          branches: [
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/inventory/detail',
                  builder: (context, state) => Scaffold(
                    appBar: AppBar(title: const Text('Detail Screen')),
                    body: ElevatedButton(
                      onPressed: () => showAdjustStockModal(context, product),
                      child: const Text('Abrir Ajuste'),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp.router(
          theme: AppTheme.dark,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Abrir Ajuste'));
    await tester.pumpAndSettle();
    expect(find.text('Ajustar stock'), findsOneWidget);

    // 1st back: dismisses AdjustStockModal
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Ajustar stock'), findsNothing);
    expect(find.text('Detail Screen'), findsOneWidget);
  });
}
