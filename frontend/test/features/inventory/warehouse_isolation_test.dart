// Aislamiento por almacén — Fase 1 (Sep 2026): el producto trae las
// existencias del almacén donde opero (D23), avisa cuando aquí hay cero y otra
// bodega sí tiene (D24), el repositorio manda el alcance al servidor y la
// leyenda del encabezado muestra el almacén (D22).
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nexus_app/core/network/dio_client.dart';
import 'package:nexus_app/core/storage/secure_storage.dart';
import 'package:nexus_app/core/theme/app_theme.dart';
import 'package:nexus_app/features/account/presentation/account_provider.dart';
import 'package:nexus_app/features/account/presentation/widgets/warehouse_scope_badge.dart';
import 'package:nexus_app/features/auth/data/auth_repository.dart';
import 'package:nexus_app/features/inventory/data/inventory_repository.dart';
import 'package:nexus_app/features/inventory/domain/product.dart';
import 'package:nexus_app/features/inventory/presentation/inventory_provider.dart';
import 'package:nexus_app/features/inventory/presentation/widgets/product_list_tile.dart';
import 'package:nexus_app/features/inventory/presentation/widgets/stock_card.dart';
import 'package:nexus_app/features/inventory/presentation/widgets/warehouse_stock_hint.dart';
import 'package:nexus_app/features/management/domain/warehouse.dart';

class MockDioClient extends Mock implements DioClient {}

const _principal = '11111111-1111-1111-1111-111111111111';
const _bodega = '22222222-2222-2222-2222-222222222222';
const _names = {_principal: 'Almacén Principal', _bodega: 'Bodega'};

/// `ProductResponse` del backend con alcance de almacén.
Map<String, dynamic> _json({
  String? scope = _principal,
  num here = 4,
  num there = 26,
  num reservedHere = 0,
  num reservedThere = 0,
}) =>
    {
      'id': 'p-1',
      'sku': 'NEX-00001',
      'name': 'Coca-Cola 600ml',
      'price_mxn': '18.00',
      'cost_mxn': '12.00',
      'min_stock_alert': '5.00',
      'is_active': true,
      'created_at': '2026-09-01T10:00:00',
      'total_stock': '${here + there}',
      'warehouse_id': scope,
      'warehouse_stock': scope == _bodega ? '$there' : (scope == null ? '${here + there}' : '$here'),
      'is_low_stock': true,
      'stocks': [
        {'warehouse_id': _principal, 'current_stock': '$here', 'reserved_stock': '$reservedHere'},
        {'warehouse_id': _bodega, 'current_stock': '$there', 'reserved_stock': '$reservedThere'},
      ],
    };

void main() {
  group('Product.fromJson con alcance de almacén', () {
    test('stock es el de mi almacén; totalStock y desglose conservan el resto', () {
      final product = Product.fromJson(_json());
      expect(product.stock, 4);
      expect(product.availableStock, 4);
      expect(product.totalStock, 30);
      expect(product.warehouseId, _principal);
      expect(product.stockByWarehouse, {_principal: 4, _bodega: 26});
      expect(product.stockElsewhere, {_bodega: 26});
      expect(product.stockStatus, StockStatus.lowStock);
    });

    test('lo apartado en otra bodega no resta a lo vendible aquí', () {
      final product = Product.fromJson(_json(reservedHere: 1, reservedThere: 10));
      expect(product.reservedStock, 1);
      expect(product.availableStock, 3);
    });

    test('sin alcance (todos) se comporta como antes', () {
      final product = Product.fromJson(_json(scope: null));
      expect(product.stock, 30);
      expect(product.totalStock, 30);
    });

    test('toJson/fromJson conserva existencias y desglose', () {
      final product = Product.fromJson(_json());
      final again = Product.fromJson(product.toJson());
      expect(again.stock, 4);
      expect(again.totalStock, 30);
      expect(again.stockByWarehouse, product.stockByWarehouse);
    });
  });

  group('aviso "hay N en Bodega" (D24)', () {
    test('aparece cuando aquí hay cero y otra bodega tiene', () {
      final product = Product.fromJson(_json(here: 0));
      expect(otherWarehousesHint(product, _names), 'Hay 26 en Bodega');
    });

    test('no aparece si aquí hay existencias', () {
      expect(otherWarehousesHint(Product.fromJson(_json()), _names), isNull);
    });

    test('no aparece si tampoco hay en otro lado', () {
      final product = Product.fromJson(_json(here: 0, there: 0));
      expect(otherWarehousesHint(product, _names), isNull);
    });

    test('varias bodegas se enumeran de mayor a menor', () {
      final product = Product.fromJson(_json(here: 0)).copyWith(
        stockByWarehouse: {_principal: 0, _bodega: 3, 'wh-3': 9},
      );
      expect(
        otherWarehousesHint(product, {..._names, 'wh-3': 'Centro'}),
        'Hay 9 en Centro y 3 en Bodega',
      );
    });

    testWidgets('el renglón del listado y la ficha lo muestran', (tester) async {
      final product = Product.fromJson(_json(here: 0));
      final hint = otherWarehousesHint(product, _names);
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: Column(children: [
            ProductListTile(product: product, onTap: () {}, otherWarehousesHint: hint),
            StockCard(product: product, otherWarehousesHint: hint),
          ]),
        ),
      ));
      expect(find.byKey(const Key('otherWarehousesHint')), findsOneWidget);
      expect(find.text('Hay 26 en Bodega'), findsOneWidget);
      expect(find.text('Sin stock'), findsOneWidget);
      expect(find.text('Sin stock aquí · Hay 26 en Bodega'), findsOneWidget);
    });
  });

  group('InventoryRepositoryImpl manda el almacén donde opero', () {
    late MockDioClient client;

    setUp(() {
      client = MockDioClient();
      when(() => client.get<dynamic>(
            any(),
            queryParameters: any(named: 'queryParameters'),
            options: any(named: 'options'),
          )).thenAnswer((inv) async => Response(
            data: (inv.positionalArguments.first as String).endsWith('products')
                ? [_json()]
                : _json(),
            statusCode: 200,
            requestOptions: RequestOptions(),
          ));
    });

    Map<String, dynamic>? sentQuery() => verify(() => client.get<dynamic>(
          any(),
          queryParameters: captureAny(named: 'queryParameters'),
          options: any(named: 'options'),
        )).captured.last as Map<String, dynamic>?;

    test('listado y detalle con warehouse_id', () async {
      final repo = InventoryRepositoryImpl(
        client: client,
        resolveWarehouseScope: () async => _principal,
      );
      final page = await repo.getProducts(lowStock: true);
      expect(page.items.single.stock, 4);
      expect(sentQuery(), containsPair('warehouse_id', _principal));

      await repo.getProductById('p-1');
      expect(sentQuery(), {'warehouse_id': _principal});
    });

    test('sin almacén real (respaldo "default") no manda alcance', () async {
      final repo = InventoryRepositoryImpl(
        client: client,
        resolveWarehouseScope: () async => 'default',
      );
      await repo.getProducts();
      expect(sentQuery(), isNot(contains('warehouse_id')));
    });
  });

  testWidgets('la leyenda del encabezado muestra el almacén donde opero (D22)',
      (tester) async {
    final auth = AuthRepositoryMock(storage: SecureStorage());
    await auth.setDefaultWarehouseId(_bodega);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(auth),
        warehousesProvider.overrideWith((ref) async => const [
              WarehouseOption(id: _principal, name: 'Almacén Principal', isDefault: true),
              WarehouseOption(id: _bodega, name: 'Bodega'),
            ]),
      ],
      child: MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          appBar: AppBar(title: const ScopedAppBarTitle(title: Text('Inventario'))),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Inventario'), findsOneWidget);
    expect(find.byKey(const Key('warehouseScopeBadge')), findsOneWidget);
    expect(find.text('Bodega'), findsOneWidget);
  });

  test('cambiar "Dónde opero" recarga el inventario con el almacén nuevo '
      '(QA de Eduardo, Sep 26)', () async {
    final client = MockDioClient();
    final scopes = <String?>[];
    when(() => client.get<dynamic>(
          any(),
          queryParameters: any(named: 'queryParameters'),
          options: any(named: 'options'),
        )).thenAnswer((inv) async {
      final query = inv.namedArguments[#queryParameters] as Map?;
      scopes.add(query?['warehouse_id'] as String?);
      return Response(data: const [], statusCode: 200, requestOptions: RequestOptions());
    });

    final container = ProviderContainer(overrides: [
      authRepositoryProvider.overrideWithValue(AuthRepositoryMock(storage: SecureStorage())),
      warehousesProvider.overrideWith((ref) async => const [
            WarehouseOption(id: _principal, name: 'Almacén Principal', isDefault: true),
            WarehouseOption(id: _bodega, name: 'Bodega'),
          ]),
      inventoryRepositoryProvider.overrideWith((ref) => InventoryRepositoryImpl(
            client: client,
            resolveWarehouseScope: () => readOperatingWarehouseId(ref),
          )),
    ]);
    addTearDown(container.dispose);
    container.listen(inventoryProvider, (_, __) {});
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(scopes.last, _principal);

    await container.read(operatingWarehouseProvider.notifier).select(
        Warehouse(id: _bodega, name: 'Bodega', isActive: true, createdAt: DateTime(2026)));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(scopes.last, _bodega);
  });
}
