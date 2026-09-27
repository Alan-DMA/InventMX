// QA de Eduardo (Sep 27): viendo "Todos los almacenes" en el Inicio,
//  · "Ver todas" llevaba a Inventario (sólo mi almacén) y se perdían las
//    alertas de los demás → pantalla "Alertas de stock" agrupada (D39);
//  · tocar una alerta de otro almacén abría la ficha con MI almacén → la
//    ficha muestra el almacén de la alerta, avisado, con traslado (D40).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nexus_app/core/theme/app_theme.dart';
import 'package:nexus_app/features/dashboard/domain/daily_snapshot.dart';
import 'package:nexus_app/features/dashboard/domain/stock_alert.dart';
import 'package:nexus_app/features/dashboard/presentation/dashboard_provider.dart';
import 'package:nexus_app/features/dashboard/presentation/stock_alerts_screen.dart';
import 'package:nexus_app/features/inventory/data/inventory_repository.dart';
import 'package:nexus_app/features/inventory/domain/product.dart';
import 'package:nexus_app/features/inventory/presentation/inventory_provider.dart';
import 'package:nexus_app/features/inventory/presentation/product_detail_screen.dart';
import 'package:nexus_app/features/inventory/presentation/widgets/action_grid.dart';
import 'package:nexus_app/features/management/domain/app_permission.dart';
import 'package:nexus_app/features/management/presentation/management_provider.dart'
    show canViewAllWarehousesProvider, myPermissionsProvider;

class _MockInventoryRepository extends Mock implements InventoryRepository {}

const _principal = 'wh-pri';
const _valencia = 'wh-val';

const _warehouses = [
  WarehouseOption(id: _principal, name: 'Almacén Principal', isDefault: true),
  WarehouseOption(id: _valencia, name: 'Almacén en Valencia'),
];

class _FixedSnapshot extends DailySnapshotNotifier {
  _FixedSnapshot(this.snapshot);
  final DailySnapshot snapshot;

  @override
  Future<DailySnapshot> build() async => snapshot;
}

StockAlertItem _alert(String product, String warehouseId, String warehouse, int stock) =>
    StockAlertItem(
      productId: product,
      productName: product,
      availableStock: stock,
      isOutOfStock: stock <= 0,
      minStock: 5,
      warehouseId: warehouseId,
      warehouseName: warehouse,
    );

/// Opero en Valencia (24); en Principal quedan 3.
Product _coca() => Product(
      id: 'p-1',
      sku: 'NEX-1',
      name: 'Coca-Cola 600ml',
      category: 'Bebidas',
      priceMxn: 18,
      costMxn: 12,
      stock: 24,
      reservedStock: 0,
      availableStock: 24,
      minStockAlert: 5,
      warehouseId: _valencia,
      stockByWarehouse: const {_valencia: 24, _principal: 3},
      isActive: true,
      isOnCatalog: false,
      createdAt: DateTime(2026, 9, 1),
    );

Widget _detail({String? viewWarehouseId}) {
  final product = _coca();
  final repo = _MockInventoryRepository();
  when(() => repo.getProducts(
        query: any(named: 'query'),
        category: any(named: 'category'),
        lowStock: any(named: 'lowStock'),
        page: any(named: 'page'),
        pageSize: any(named: 'pageSize'),
      )).thenAnswer((_) async => PaginatedProducts(
      items: [product], total: 1, page: 1, pageSize: 20, totalPages: 1));
  return ProviderScope(
    overrides: [
      inventoryRepositoryProvider.overrideWithValue(repo),
      productDetailProvider(product.id).overrideWith((ref) async => product),
      myPermissionsProvider.overrideWithValue(Permissions.all),
      warehousesProvider.overrideWith((ref) async => _warehouses),
    ],
    child: MaterialApp(
      theme: AppTheme.dark,
      home: ProductDetailScreen(
          productId: product.id, viewWarehouseId: viewWarehouseId),
    ),
  );
}

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(800 * 3, 2000 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets('"Alertas de stock" agrupa por almacén', (tester) async {
    final snapshot = DailySnapshot(
      salesTodayMxn: 0,
      salesTodayCount: 0,
      salesYesterdayMxn: 0,
      marginTodayMxn: 0,
      lowStockCount: 3,
      outOfStockCount: 1,
      lowStockAlerts: [
        _alert('Sabritas 45g', _principal, 'Almacén Principal', 0),
        _alert('Coca-Cola 600ml', _principal, 'Almacén Principal', 3),
        _alert('Coca-Cola 600ml', _valencia, 'Almacén en Valencia', 2),
      ],
      payablesDueMxn: 0,
      payablesOverdueCount: 0,
      isCashSessionOpen: false,
      cashExpectedMxn: 0,
    );
    await tester.pumpWidget(ProviderScope(
      overrides: [
        dailySnapshotProvider.overrideWith(() => _FixedSnapshot(snapshot)),
        canViewAllWarehousesProvider.overrideWith((ref) => true),
        warehousesProvider.overrideWith((ref) async => _warehouses),
      ],
      child: MaterialApp(theme: AppTheme.dark, home: const StockAlertsScreen()),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('stockAlertsGroup-Almacén Principal')), findsOneWidget);
    expect(find.byKey(const Key('stockAlertsGroup-Almacén en Valencia')), findsOneWidget);
    expect(find.text('ALMACÉN PRINCIPAL · 2'), findsOneWidget);
    // El mismo producto, una vez por almacén (no se suman bodegas)
    expect(find.text('Coca-Cola 600ml'), findsNWidgets(2));
  });

  testWidgets('la ficha abierta desde una alerta de otro almacén muestra ese almacén',
      (tester) async {
    _phone(tester);
    await tester.pumpWidget(_detail(viewWarehouseId: _principal));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('otherWarehouseBanner')), findsOneWidget);
    expect(find.text('Viendo Almacén Principal'), findsOneWidget);
    expect(find.text('Tú operas en Almacén en Valencia'), findsOneWidget);
    expect(find.text('DISPONIBLE · ALMACÉN PRINCIPAL'), findsOneWidget);
    expect(find.byKey(const Key('stockByWarehouse')), findsOneWidget);
    expect(find.byKey(const Key('sendFromMyWarehouse')), findsOneWidget);
    // El ajuste manual es sólo del almacén donde opero
    expect(tester.widget<ActionGrid>(find.byType(ActionGrid)).onAdjustStock, isNull);
  });

  testWidgets('desde mi almacén la ficha es la de siempre (con desglose)',
      (tester) async {
    _phone(tester);
    await tester.pumpWidget(_detail(viewWarehouseId: _valencia));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('otherWarehouseBanner')), findsNothing);
    expect(find.byKey(const Key('sendFromMyWarehouse')), findsNothing);
    expect(find.text('DISPONIBLE'), findsOneWidget);
    expect(find.byKey(const Key('stockByWarehouse')), findsOneWidget);
    expect(tester.widget<ActionGrid>(find.byType(ActionGrid)).onAdjustStock, isNotNull);
  });
}
