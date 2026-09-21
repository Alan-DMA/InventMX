import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_app/core/theme/app_theme.dart';
import 'package:nexus_app/features/account/data/account_repository.dart';
import 'package:nexus_app/features/account/data/operating_warehouse_store.dart';
import 'package:nexus_app/features/account/presentation/account_provider.dart';
import 'package:nexus_app/features/account/presentation/account_screen.dart';
import 'package:nexus_app/features/account/presentation/operating_warehouse_screen.dart';
import 'package:nexus_app/features/account/presentation/password_screen.dart';
import 'package:nexus_app/features/account/presentation/personal_data_screen.dart';
import 'package:nexus_app/core/storage/secure_storage.dart';
import 'package:nexus_app/features/auth/data/auth_repository.dart';
import 'package:nexus_app/features/auth/presentation/login_provider.dart';
import 'package:nexus_app/features/inventory/presentation/inventory_provider.dart'
    show WarehouseOption, warehousesProvider;
import 'package:nexus_app/features/management/data/management_repository.dart';
import 'package:nexus_app/features/management/domain/app_permission.dart';
import 'package:nexus_app/features/management/domain/tenant_role.dart';
import 'package:nexus_app/features/management/presentation/management_provider.dart'
    hide warehousesProvider;
import 'package:nexus_app/features/saas_admin/data/saas_repository.dart';
import 'package:nexus_app/features/saas_admin/presentation/saas_provider.dart';

// ---------------------------------------------------------------------------
// Mi cuenta — página índice y sus sub-páginas (reestructura de Sep 16)
// ---------------------------------------------------------------------------

const _owner = 'eduardo.cristancho@nexus.mx';
const _manager = 'maria.hernandez@nexus.mx';
const _cashier = 'jose.ramirez@nexus.mx';

/// Espeja el mock de Gestión de siempre (wh-001/002/003) pero como lo que
/// hoy alimenta el selector real: `GET /inventory/warehouses`.
const _testWarehouses = [
  WarehouseOption(id: 'wh-001', name: 'Almacén Principal', isDefault: true),
  WarehouseOption(id: 'wh-002', name: 'Mostrador'),
  WarehouseOption(id: 'wh-003', name: 'Bodega'),
];

ProviderContainer _container({
  String email = _owner,
  AuthRepositoryMock? authRepo,
  AccountRepository? account,
}) {
  final container = ProviderContainer(
    overrides: [
      sessionProvider.overrideWith((ref) => true),
      currentUserNameProvider.overrideWith((ref) => email),
      // Personas y roles son reales desde la Fase B (Sep 21): el arnés
      // fija el mock para no pegarle a /users.
      managementRepositoryProvider.overrideWith(
          (ref) => ManagementRepositoryMock(currentEmail: email)),
      operatingWarehouseStoreProvider
          .overrideWithValue(OperatingWarehouseStoreMemory()),
      // El almacén operativo ahora persiste en el backend (/auth/me) — sin
      // esto, golpearía red real.
      authRepositoryProvider.overrideWithValue(
          authRepo ?? AuthRepositoryMock(storage: SecureStorage())),
      warehousesProvider.overrideWith((ref) async => _testWarehouses),
      if (account != null) accountRepositoryProvider.overrideWithValue(account),
      // Sin esto, el perfil SaaS intentaría salir a la red real.
      saasRepositoryProvider
          .overrideWithValue(SaasRepositoryMock(currentEmail: email)),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

Widget _app(ProviderContainer container, Widget home) =>
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: AppTheme.dark, home: home),
    );

/// Los mocks responden con retardo y varios providers cargan a la par:
/// `pumpAndSettle` solo se detiene en cuanto no queda animación, aunque sigan
/// pendientes los timers, así que el reloj se avanza a mano.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  await tester.pump(const Duration(seconds: 1));
  await tester.pumpAndSettle();
}

void main() {
  group('Página índice', () {
    testWidgets('el Dueño ve su identidad y los dos grupos', (tester) async {
      final container = _container();
      await tester.pumpWidget(_app(container, const AccountScreen()));
      await _settle(tester);

      expect(find.text('Eduardo Cristancho'), findsOneWidget);
      expect(find.byKey(const Key('accountRoleChip')), findsOneWidget);

      expect(find.text('Mi información'.toUpperCase()), findsOneWidget);
      expect(find.byKey(const Key('accountRowData')), findsOneWidget);
      expect(find.byKey(const Key('accountRowPassword')), findsOneWidget);
      expect(find.byKey(const Key('accountRowWarehouse')), findsOneWidget);

      expect(find.text('Mi negocio'.toUpperCase()), findsOneWidget);
      expect(find.byKey(const Key('accountRowUsers')), findsOneWidget);
      expect(find.byKey(const Key('accountRowPreferences')), findsOneWidget);

      // Cerrar sesión cierra la página: hay que bajar hasta construirlo.
      await tester.scrollUntilVisible(
        find.byKey(const Key('accountLogout')),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.byKey(const Key('accountLogout')), findsOneWidget);
    });

    testWidgets('un Cajero solo ve lo suyo: no hay grupo de negocio',
        (tester) async {
      final container = _container(email: _cashier);
      await tester.pumpWidget(_app(container, const AccountScreen()));
      await _settle(tester);

      expect(find.byKey(const Key('accountRowData')), findsOneWidget);
      expect(find.text('Mi negocio'.toUpperCase()), findsNothing);
      expect(find.byKey(const Key('accountRowUsers')), findsNothing);
      expect(find.byKey(const Key('accountRowPreferences')), findsNothing);
    });

    testWidgets('solo el Dueño ve cuánto paga el negocio', (tester) async {
      final owner = _container();
      await tester.pumpWidget(_app(owner, const AccountScreen()));
      await _settle(tester);
      expect(owner.read(canSeeSubscriptionProvider), isTrue);
      expect(find.byKey(const Key('accountRowSubscription')), findsOneWidget);

      final manager = _container(email: _manager);
      await tester.pumpWidget(_app(manager, const AccountScreen()));
      await _settle(tester);
      expect(manager.read(canSeeSubscriptionProvider), isFalse);
      expect(find.byKey(const Key('accountRowSubscription')), findsNothing);
      // El Encargado sí administra gente, pero no toca los almacenes.
      expect(find.byKey(const Key('accountRowUsers')), findsOneWidget);
      expect(find.byKey(const Key('accountRowPreferences')), findsNothing);
    });

    testWidgets('la administración del sistema no existe para un comerciante',
        (tester) async {
      final container = _container();
      await tester.pumpWidget(_app(container, const AccountScreen()));
      await _settle(tester);

      expect(
          find.text('Administración del sistema'.toUpperCase()), findsNothing);
      expect(find.byKey(const Key('accountRowSystem')), findsNothing);
    });
  });

  group('Mis datos', () {
    testWidgets('el correo y el rol se muestran pero no se editan',
        (tester) async {
      final container = _container();
      await tester.pumpWidget(_app(container, const PersonalDataScreen()));
      await _settle(tester);

      expect(find.text(_owner), findsOneWidget);
      expect(find.text('Dueño'), findsOneWidget);
      expect(find.text('Es con el que entras a la app'), findsOneWidget);
      // Un solo campo editable: el nombre.
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('guardar el nombre lo cambia en el negocio', (tester) async {
      final container = _container();
      await tester.pumpWidget(_app(container, const PersonalDataScreen()));
      await _settle(tester);

      await tester.enterText(
          find.byKey(const Key('personalNameField')), 'Eduardo C.');
      await tester.pump();
      await tester.tap(find.byKey(const Key('personalSaveButton')));
      await _settle(tester);

      expect(container.read(currentMemberProvider).valueOrNull?.name,
          'Eduardo C.');
    });
  });

  group('Contraseña', () {
    testWidgets('avisa en el momento si es corta o si no coinciden',
        (tester) async {
      final container = _container(account: AccountRepositoryMock());
      await tester.pumpWidget(_app(container, const PasswordScreen()));
      await _settle(tester);

      await tester.enterText(
          find.byKey(const Key('passwordNewField')), 'corta');
      await tester.pump();
      expect(find.text('Debe tener al menos 8 caracteres.'), findsOneWidget);

      await tester.enterText(
          find.byKey(const Key('passwordNewField')), 'unaLarga123');
      await tester.enterText(
          find.byKey(const Key('passwordConfirmField')), 'otraDistinta1');
      await tester.pump();
      expect(find.text('Las dos contraseñas nuevas no coinciden.'),
          findsOneWidget);
    });

    testWidgets('rechaza cuando la contraseña actual no es la correcta',
        (tester) async {
      final container =
          _container(account: AccountRepositoryMock(knownPassword: 'Real123!'));
      await tester.pumpWidget(_app(container, const PasswordScreen()));
      await _settle(tester);

      await tester.enterText(
          find.byKey(const Key('passwordCurrentField')), 'equivocada');
      await tester.enterText(
          find.byKey(const Key('passwordNewField')), 'nuevaBuena1');
      await tester.enterText(
          find.byKey(const Key('passwordConfirmField')), 'nuevaBuena1');
      await tester.pump();
      await tester.tap(find.byKey(const Key('passwordSaveButton')));
      await _settle(tester);

      expect(find.byKey(const Key('passwordError')), findsOneWidget);
      expect(find.text('La contraseña actual no es correcta.'), findsOneWidget);
    });

    testWidgets('con la actual correcta, la cambia', (tester) async {
      final repo = AccountRepositoryMock(knownPassword: 'Real123!');
      final container = _container(account: repo);
      await tester.pumpWidget(_app(container, const PasswordScreen()));
      await _settle(tester);

      await tester.enterText(
          find.byKey(const Key('passwordCurrentField')), 'Real123!');
      await tester.enterText(
          find.byKey(const Key('passwordNewField')), 'nuevaBuena1');
      await tester.enterText(
          find.byKey(const Key('passwordConfirmField')), 'nuevaBuena1');
      await tester.pump();
      await tester.tap(find.byKey(const Key('passwordSaveButton')));
      await _settle(tester);

      expect(repo.knownPassword, 'nuevaBuena1');
    });
  });

  group('Dónde opero', () {
    testWidgets('elegir un almacén lo recuerda', (tester) async {
      final authRepo = AuthRepositoryMock(storage: SecureStorage());
      final container = _container(authRepo: authRepo);
      await tester
          .pumpWidget(_app(container, const OperatingWarehouseScreen()));
      await _settle(tester);

      expect(find.text('Almacén Principal'), findsOneWidget);
      await tester.tap(find.byKey(const Key('warehouseOption-wh-003')));
      await _settle(tester);

      expect(await authRepo.fetchDefaultWarehouseId(), 'wh-003');
      expect(container.read(operatingWarehouseProvider).valueOrNull?.name,
          'Bodega');
    });

    testWidgets('sin permiso no se puede cambiar, y se explica por qué',
        (tester) async {
      final container = _container(email: _cashier);
      await tester
          .pumpWidget(_app(container, const OperatingWarehouseScreen()));
      await _settle(tester);

      expect(container.read(canManageWarehousesProvider), isFalse);
      expect(find.byKey(const Key('warehouseLockedHint')), findsOneWidget);
      expect(find.byKey(const Key('warehouseManageLink')), findsNothing);

      // El renglón existe pero no responde al toque.
      final tile = tester.widget<ListTile>(
        find.byKey(const Key('warehouseOption-wh-003')),
      );
      expect(tile.onTap, isNull);
    });

    testWidgets('con permiso ofrece el atajo a administrar almacenes',
        (tester) async {
      final container = _container();
      await tester
          .pumpWidget(_app(container, const OperatingWarehouseScreen()));
      await _settle(tester);

      expect(find.byKey(const Key('warehouseManageLink')), findsOneWidget);
      expect(
        container.read(myPermissionsProvider),
        contains(Permissions.inventarioGestionarAlmacenes),
      );
      expect(container.read(myRoleProvider)?.id, TenantRoles.owner);
    });
  });
}
