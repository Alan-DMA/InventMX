// Personas y roles contra el backend real (`/users`, `/roles`, `/auth/me`):
// mapeo de campos (incluida la comisión), roles por código, errores del
// servidor y delegación al mock de lo que el backend no cubre.
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nexus_app/core/network/dio_client.dart';
import 'package:nexus_app/features/management/data/management_repository.dart';
import 'package:nexus_app/features/management/data/management_repository_impl.dart';
import 'package:nexus_app/features/management/domain/app_permission.dart';
import 'package:nexus_app/features/management/domain/tenant_member.dart';
import 'package:nexus_app/features/management/domain/tenant_role.dart';

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

final _roles = [
  {'id': _cashierRole, 'name': 'CASHIER', 'description': 'Cajero', 'permissions': []},
  {'id': _ownerRole, 'name': 'OWNER', 'description': 'Dueño', 'permissions': []},
  {'id': 'r-wh', 'name': 'WAREHOUSE', 'description': 'Almacén', 'permissions': []},
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
    repo = ManagementRepositoryImpl(
      client: client,
      fallback: ManagementRepositoryMock(currentEmail: 'ana@tienda.mx'),
    );
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
    test('mapea código, etiqueta y permisos por código, en orden fijo', () async {
      stubGet('/api/v1/roles', _roles);
      final roles = await repo.listRoles();
      expect(roles.map((r) => r.code), ['OWNER', 'ADMIN', 'CASHIER', 'WAREHOUSE']);
      expect(roles.map((r) => r.label), ['Dueño', 'Encargado', 'Cajero', 'Almacenista']);
      expect(roles.first.id, _ownerRole);
      expect(roles.first.isOwner, isTrue);
      expect(roles.first.can(Permissions.usuariosGestionar), isTrue);
      final cashier = roles.firstWhere((r) => r.code == RoleCodes.cashier);
      expect(cashier.can(Permissions.ventasCobrar), isTrue);
      expect(cashier.can(Permissions.usuariosGestionar), isFalse);
    });

    test('updateRolePermissions vive en memoria (el backend no lo expone)', () async {
      stubGet('/api/v1/roles', _roles);
      final updated = await repo.updateRolePermissions(
          roleId: _cashierRole, permissions: {Permissions.inventarioVer});
      expect(updated.permissions, {Permissions.inventarioVer});
      final again = await repo.listRoles();
      expect(again.firstWhere((r) => r.id == _cashierRole).permissions,
          {Permissions.inventarioVer});
    });
  });

  test('almacenes y categorías se delegan al mock', () async {
    final warehouses = await repo.listWarehouses();
    expect(warehouses, isNotEmpty);
    final categories = await repo.listCategories();
    expect(categories, isNotEmpty);
    verifyNever(() => client.get<dynamic>(any(),
        queryParameters: any(named: 'queryParameters'),
        options: any(named: 'options')));
  });
}
