// Gestión contra el backend real (`/users`, `/roles`, `/auth/me`, almacenes y
// categorías): mapeo de campos (incluida la comisión), roles por código y
// errores del servidor mostrados tal cual.
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nexus_app/core/network/dio_client.dart';
import 'package:nexus_app/features/management/domain/category.dart';
import 'package:nexus_app/features/management/data/management_repository_impl.dart';
import 'package:nexus_app/features/management/domain/app_permission.dart';
import 'package:nexus_app/features/management/domain/tenant_member.dart';
import 'package:nexus_app/features/management/domain/tenant_role.dart';
import 'package:nexus_app/features/management/domain/warehouse.dart';

class MockDioClient extends Mock implements DioClient {}

const _ownerRole = 'a0000000-0000-0000-0000-000000000001';
const _cashierRole = 'a0000000-0000-0000-0000-000000000003';

Map<String, dynamic> _user({
  String id = 'u-1',
  String name = 'Ana Torres',
  String email = 'ana@tienda.mx',
  String roleId = _cashierRole,
  bool active = true,
  String type = 'PERCENTAGE_SALE',
  dynamic rate = '0.00',
}) =>
    {
      'id': id,
      'full_name': name,
      'email': email,
      'role_id': roleId,
      'is_active': active,
      'created_at': '2026-09-01T10:00:00',
      'commission_type': type,
      'commission_rate': rate, // Decimal → string con response_model
    };

/// `permissions[]` tal como los manda `GET /roles` (seed `0002`): OWNER sin
/// filas, CASHIER con sus 7, WAREHOUSE con sus 5.
List<Map<String, String>> _perms(List<String> codes) =>
    [for (final c in codes) {'id': 'p-$c', 'code': c, 'description': c}];

const _cashierCodes = [
  'inventory.view',
  'sales.view',
  'sales.checkout',
  'cash.view',
  'cash.open_session',
  'cash.close_session',
  'cash.manual_movement',
];

final _roles = [
  {'id': _cashierRole, 'name': 'CASHIER', 'description': 'Cajero', 'permissions': _perms(_cashierCodes)},
  {'id': _ownerRole, 'name': 'OWNER', 'description': 'Dueño', 'permissions': []},
  {'id': 'r-wh', 'name': 'WAREHOUSE', 'description': 'Almacén',
    'permissions': _perms(['inventory.view', 'inventory.create', 'inventory.adjust_stock', 'purchases.view', 'purchases.create'])},
  {'id': 'r-adm', 'name': 'ADMIN', 'description': 'Admin', 'permissions': []},
];

Response<dynamic> _ok(String path, dynamic data) => Response(
      data: data,
      statusCode: 200,
      requestOptions: RequestOptions(path: path),
    );

DioException _http(String path, int status, {String? detail}) => DioException(
      requestOptions: RequestOptions(path: path),
      response: Response(
        statusCode: status,
        data: detail == null ? null : {'detail': detail},
        requestOptions: RequestOptions(path: path),
      ),
      type: DioExceptionType.badResponse,
    );

void main() {
  late MockDioClient client;
  late ManagementRepositoryImpl repo;

  setUp(() {
    client = MockDioClient();
    repo = ManagementRepositoryImpl(client: client);
  });

  void stubGet(String path, dynamic data) {
    when(() => client.get<dynamic>(
          path,
          queryParameters: any(named: 'queryParameters'),
          options: any(named: 'options'),
        )).thenAnswer((_) async => _ok(path, data));
  }

  group('personas', () {
    test('listMembers mapea comisión (string) y ordena por alta', () async {
      stubGet('/api/v1/users', [
        _user(id: 'u-2', name: 'Beto', rate: '5.00', type: 'PERCENTAGE_PROFIT'),
        _user(id: 'u-1'),
      ]);
      final members = await repo.listMembers();
      expect(members.map((m) => m.id), ['u-2', 'u-1']); // misma fecha: estable
      final beto = members.first;
      expect(beto.commissionType, CommissionType.percentageProfit);
      expect(beto.commissionRate, 5.0);
      expect(beto.commissionLabel, '5 % de la ganancia');
      expect(members.last.hasCommission, isFalse);
      expect(members.last.commissionLabel, isNull);
    });

    test('createMember manda contraseña y fija la comisión en un segundo PUT', () async {
      Map<String, dynamic>? posted;
      Map<String, dynamic>? put;
      when(() => client.post<dynamic>(
            '/api/v1/users',
            data: any(named: 'data'),
            options: any(named: 'options'),
          )).thenAnswer((inv) async {
        posted = inv.namedArguments[#data] as Map<String, dynamic>;
        return _ok('/api/v1/users', _user(id: 'u-9', name: 'Lucía'));
      });
      when(() => client.put<dynamic>(
            '/api/v1/users/u-9',
            data: any(named: 'data'),
            options: any(named: 'options'),
          )).thenAnswer((inv) async {
        put = inv.namedArguments[#data] as Map<String, dynamic>;
        return _ok('/api/v1/users/u-9',
            _user(id: 'u-9', name: 'Lucía', type: 'FIXED_PER_SALE', rate: '15.00'));
      });

      final m = await repo.createMember(
        name: ' Lucía ',
        email: 'Lucia@Tienda.mx',
        roleId: _cashierRole,
        password: 'lucia123',
        commissionType: CommissionType.fixedPerSale,
        commissionRate: 15,
      );

      expect(posted, {
        'full_name': 'Lucía',
        'email': 'lucia@tienda.mx',
        'password': 'lucia123',
        'role_id': _cashierRole,
      });
      expect(put, {'commission_type': 'FIXED_PER_SALE', 'commission_rate': 15});
      expect(m.commissionLabel, r'$15.00 fijos por venta');
    });

    test('sin comisión no hay segundo PUT', () async {
      when(() => client.post<dynamic>(
            '/api/v1/users',
            data: any(named: 'data'),
            options: any(named: 'options'),
          )).thenAnswer((_) async => _ok('/api/v1/users', _user(id: 'u-9')));

      await repo.createMember(
          name: 'X Y', email: 'x@y.mx', roleId: _cashierRole, password: 'abcdef');
      verifyNever(() => client.put<dynamic>(any(),
          data: any(named: 'data'),
          options: any(named: 'options')));
    });

    test('updateMember sólo manda lo que cambia (nunca el correo)', () async {
      Map<String, dynamic>? put;
      when(() => client.put<dynamic>(
            '/api/v1/users/u-1',
            data: any(named: 'data'),
            options: any(named: 'options'),
          )).thenAnswer((inv) async {
        put = inv.namedArguments[#data] as Map<String, dynamic>;
        return _ok('/api/v1/users/u-1', _user(rate: '5'));
      });
      await repo.updateMember(
        id: 'u-1',
        email: 'otro@tienda.mx',
        commissionType: CommissionType.percentageSale,
        commissionRate: 5,
      );
      expect(put, {'commission_type': 'PERCENTAGE_SALE', 'commission_rate': 5});
    });

    test('409 → correo duplicado; "degradar" → último dueño; detail → tal cual', () async {
      when(() => client.post<dynamic>(
            '/api/v1/users',
            data: any(named: 'data'),
            options: any(named: 'options'),
          )).thenThrow(_http('/api/v1/users', 409, detail: 'El correo ya existe'));
      expect(
        () => repo.createMember(
            name: 'A B', email: 'a@b.mx', roleId: _cashierRole, password: 'abcdef'),
        throwsA(isA<DuplicateMemberEmailException>()),
      );

      when(() => client.put<dynamic>(
            '/api/v1/users/u-1',
            data: any(named: 'data'),
            options: any(named: 'options'),
          )).thenThrow(_http('/api/v1/users/u-1', 400,
              detail: 'No es posible cambiar o degradar el rol del dueño principal (OWNER).'));
      expect(() => repo.updateMember(id: 'u-1', roleId: _cashierRole),
          throwsA(isA<LastOwnerException>()));

      when(() => client.put<dynamic>(
            '/api/v1/users/u-2',
            data: any(named: 'data'),
            options: any(named: 'options'),
          )).thenThrow(_http('/api/v1/users/u-2', 400,
              detail: 'El porcentaje de comisión no puede ser mayor a 100 %.'));
      expect(
        () => repo.updateMember(id: 'u-2', commissionRate: 150),
        throwsA(predicate((e) => e.toString().contains('mayor a 100'))),
      );
    });

    test('deactivateMember alterna el estado con PATCH', () async {
      when(() => client.patch<dynamic>(
            '/api/v1/users/u-1/status',
            data: any(named: 'data'),
            options: any(named: 'options'),
          )).thenAnswer((_) async => _ok('/api/v1/users/u-1/status', _user(active: false)));
      await repo.deactivateMember('u-1');
      verify(() => client.patch<dynamic>('/api/v1/users/u-1/status',
          data: any(named: 'data'),
          options: any(named: 'options'))).called(1);
    });

    test('getCurrentMember lee /auth/me', () async {
      stubGet('/api/v1/auth/me', _user(id: 'me', roleId: _ownerRole, rate: 5));
      final me = await repo.getCurrentMember();
      expect(me.id, 'me');
      expect(me.roleId, _ownerRole);
      expect(me.commissionRate, 5);
    });
  });

  group('roles', () {
    test('mapea código, etiqueta y los permisos del servidor, en orden fijo', () async {
      stubGet('/api/v1/roles', _roles);
      final roles = await repo.listRoles();
      expect(roles.map((r) => r.code), ['OWNER', 'ADMIN', 'CASHIER', 'WAREHOUSE']);
      expect(roles.map((r) => r.label), ['Dueño', 'Encargado', 'Cajero', 'Almacenista']);
      expect(roles.first.id, _ownerRole);
      expect(roles.first.isOwner, isTrue);
      // OWNER no trae filas: el catálogo completo, como `require_permission`.
      expect(roles.first.permissions, Permissions.all);
      final cashier = roles.firstWhere((r) => r.code == RoleCodes.cashier);
      expect(cashier.permissions, _cashierCodes.toSet());
      expect(cashier.can(Permissions.salesCheckout), isTrue);
      expect(cashier.can(Permissions.settingsManageUsers), isFalse);
      // ADMIN con lista vacía en el servidor queda sin nada: fail-closed.
      final admin = roles.firstWhere((r) => r.code == RoleCodes.admin);
      expect(admin.permissions, isEmpty);
    });

    test('getCurrentMember trae los permisos de `role.permissions` (CA-01)', () async {
      stubGet('/api/v1/auth/me', {
        ..._user(id: 'me'),
        'role': _roles.first,
        'default_warehouse_id': 'wh-9',
      });
      final me = await repo.getCurrentMember();
      expect(me.permissions, _cashierCodes.toSet());
      expect(me.can(Permissions.salesCheckout), isTrue);
      expect(me.can(Permissions.purchasesView), isFalse);
      expect(me.defaultWarehouseId, 'wh-9');

      stubGet('/api/v1/auth/me', {
        ..._user(id: 'me', roleId: _ownerRole),
        'role': _roles[1],
      });
      final owner = await repo.getCurrentMember();
      expect(owner.permissions, Permissions.all);
      expect(owner.permissions.length, 21);
    });
  });

  group('almacenes contra el servidor (Ajustes operativos, D7)', () {
    final principal = {
      'id': 'wh-1',
      'tenant_id': 't-1',
      'name': 'Almacén Principal',
      'is_default': true,
      'is_active': true,
      'created_at': '2026-09-01T10:00:00',
    };

    test('listWarehouses mapea principal e inactivos', () async {
      stubGet('/api/v1/inventory/warehouses', [
        principal,
        {...principal, 'id': 'wh-2', 'name': 'Bodega', 'is_default': false, 'is_active': false},
      ]);
      final warehouses = await repo.listWarehouses();
      expect(warehouses.map((w) => w.id), ['wh-1', 'wh-2']);
      expect(warehouses.first.isDefault, isTrue);
      expect(warehouses.first.isActive, isTrue);
      expect(warehouses.last.isDefault, isFalse);
      expect(warehouses.last.isActive, isFalse);
    });

    test('createWarehouse hace POST sin volverlo principal', () async {
      when(() => client.post<dynamic>(
            '/api/v1/inventory/warehouses',
            data: any(named: 'data'),
            options: any(named: 'options'),
          )).thenAnswer((_) async => _ok('/api/v1/inventory/warehouses', {
            ...principal,
            'id': 'wh-2',
            'name': 'Bodega',
            'is_default': false,
          }));

      final created = await repo.createWarehouse('  Bodega ');
      expect(created.id, 'wh-2');
      final sent = verify(() => client.post<dynamic>(
            '/api/v1/inventory/warehouses',
            data: captureAny(named: 'data'),
            options: any(named: 'options'),
          )).captured.single as Map;
      expect(sent, {'name': 'Bodega', 'is_default': false});
    });

    test('409 al crear o renombrar → nombre repetido', () async {
      when(() => client.post<dynamic>(
            '/api/v1/inventory/warehouses',
            data: any(named: 'data'),
            options: any(named: 'options'),
          )).thenThrow(_http('/api/v1/inventory/warehouses', 409));
      when(() => client.put<dynamic>(
            '/api/v1/inventory/warehouses/wh-2',
            data: any(named: 'data'),
            options: any(named: 'options'),
          )).thenThrow(_http('/api/v1/inventory/warehouses/wh-2', 409));

      await expectLater(
        repo.createWarehouse('almacén principal'),
        throwsA(isA<DuplicateWarehouseNameException>()),
      );
      await expectLater(
        repo.updateWarehouse(id: 'wh-2', name: 'Almacén Principal'),
        throwsA(isA<DuplicateWarehouseNameException>()),
      );
    });

    test('updateWarehouse hace PUT con el nombre limpio', () async {
      when(() => client.put<dynamic>(
            '/api/v1/inventory/warehouses/wh-1',
            data: any(named: 'data'),
            options: any(named: 'options'),
          )).thenAnswer((_) async => _ok('/api/v1/inventory/warehouses/wh-1',
              {...principal, 'name': 'Matriz'}));

      final renamed = await repo.updateWarehouse(id: 'wh-1', name: ' Matriz ');
      expect(renamed.name, 'Matriz');
      final sent = verify(() => client.put<dynamic>(
            '/api/v1/inventory/warehouses/wh-1',
            data: captureAny(named: 'data'),
            options: any(named: 'options'),
          )).captured.single as Map;
      expect(sent, {'name': 'Matriz'});
    });

    test('la baja rechazada muestra el motivo del servidor tal cual (CA-A3)', () async {
      const motivo = 'Aquí opera: Pepe Cajero. Asígnales otro almacén antes de darlo de baja.';
      when(() => client.delete<dynamic>(
            '/api/v1/inventory/warehouses/wh-2',
            options: any(named: 'options'),
          )).thenThrow(_http('/api/v1/inventory/warehouses/wh-2', 422, detail: motivo));

      await expectLater(
        repo.deactivateWarehouse('wh-2'),
        throwsA(predicate((e) => e.toString() == 'Exception: $motivo')),
      );
    });

    test('reactivar y hacer principal llaman a su endpoint (CA-A4)', () async {
      for (final path in [
        '/api/v1/inventory/warehouses/wh-2/activate',
        '/api/v1/inventory/warehouses/wh-2/make-default',
      ]) {
        when(() => client.post<dynamic>(
              path,
              data: any(named: 'data'),
              options: any(named: 'options'),
            )).thenAnswer((_) async => _ok(path, principal));
      }

      await repo.activateWarehouse('wh-2');
      await repo.makeDefaultWarehouse('wh-2');
      verify(() => client.post<dynamic>('/api/v1/inventory/warehouses/wh-2/activate',
          data: any(named: 'data'), options: any(named: 'options'))).called(1);
      verify(() => client.post<dynamic>('/api/v1/inventory/warehouses/wh-2/make-default',
          data: any(named: 'data'), options: any(named: 'options'))).called(1);
    });
  });

  group('categorías contra el servidor (Ajustes operativos, D8)', () {
    Map<String, dynamic> category(String id, String name, int count) => {
          'id': id,
          'tenant_id': 't-1',
          'name': name,
          'description': null,
          'created_at': '2026-09-01T10:00:00',
          'product_count': count,
        };

    test('listCategories lee las reales con su conteo (CA-A6)', () async {
      stubGet('/api/v1/inventory/categories', [
        category('c-1', 'Bebidas', 5),
        category('c-2', 'Otros', 0),
      ]);
      final categories = await repo.listCategories();
      expect(categories.map((c) => c.name), ['Bebidas', 'Otros']);
      expect(categories.first.productCount, 5);
      expect(categories.last.productCount, 0);
    });

    test('renombrar hace PUT; 409 → nombre repetido (envolvente error.message)', () async {
      when(() => client.put<dynamic>(
            '/api/v1/inventory/categories/c-1',
            data: any(named: 'data'),
            options: any(named: 'options'),
          )).thenAnswer((_) async =>
              _ok('/api/v1/inventory/categories/c-1', category('c-1', 'Refrescos', 5)));
      final renamed = await repo.renameCategory(id: 'c-1', name: ' Refrescos ');
      expect(renamed.name, 'Refrescos');
      expect(renamed.productCount, 5);

      when(() => client.put<dynamic>(
            '/api/v1/inventory/categories/c-2',
            data: any(named: 'data'),
            options: any(named: 'options'),
          )).thenThrow(DioException(
        requestOptions: RequestOptions(path: '/api/v1/inventory/categories/c-2'),
        response: Response(
          statusCode: 409,
          data: {
            'success': false,
            'error': {'code': 'RESOURCE_CONFLICT', 'message': "Ya existe una categoría con el nombre 'refrescos'."},
          },
          requestOptions: RequestOptions(path: '/api/v1/inventory/categories/c-2'),
        ),
        type: DioExceptionType.badResponse,
      ));
      await expectLater(
        repo.renameCategory(id: 'c-2', name: 'refrescos'),
        throwsA(isA<DuplicateCategoryNameException>()),
      );
    });

    test('borrar con productos muestra el 422 del servidor (CA-A5)', () async {
      const motivo = 'Esta categoría tiene 5 productos. Muévelos a otra categoría antes de eliminarla.';
      when(() => client.delete<dynamic>(
            '/api/v1/inventory/categories/c-1',
            options: any(named: 'options'),
          )).thenThrow(_http('/api/v1/inventory/categories/c-1', 422, detail: motivo));
      when(() => client.delete<dynamic>(
            '/api/v1/inventory/categories/c-2',
            options: any(named: 'options'),
          )).thenAnswer((_) async => _ok('/api/v1/inventory/categories/c-2', null));

      await expectLater(
        repo.deleteCategory('c-1'),
        throwsA(predicate((e) => e.toString() == 'Exception: $motivo')),
      );
      await repo.deleteCategory('c-2');
    });
  });
}
