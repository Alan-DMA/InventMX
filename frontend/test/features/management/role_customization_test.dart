import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_app/core/storage/secure_storage.dart';
import 'package:nexus_app/core/theme/app_theme.dart';
import 'package:nexus_app/features/auth/data/auth_repository.dart';
import 'package:nexus_app/features/auth/presentation/login_provider.dart';
import 'package:nexus_app/features/management/data/management_repository.dart';
import 'package:nexus_app/features/management/domain/app_permission.dart';
import 'package:nexus_app/features/management/domain/tenant_role.dart';
import 'package:nexus_app/features/management/presentation/management_provider.dart';
import 'package:nexus_app/features/management/presentation/members_screen.dart';
import 'package:nexus_app/features/management/presentation/permissions_screen.dart';

// ---------------------------------------------------------------------------
// Roles por comercio — Fase B (Sep 2026)
// ---------------------------------------------------------------------------
//
// El dueño ajusta qué puede cada rol **en su tienda**: la primera edición de un
// rol de fábrica crea su propia versión, avisando a cuántas personas afecta.
// El Encargado entra a la pantalla pero sólo lee; el rol Dueño no se toca y
// ningún rol pierde "ver inventario".

const _owner = 'eduardo.cristancho@nexus.mx';
const _manager = 'maria.hernandez@nexus.mx';

ProviderContainer _container({String email = _owner}) {
  final container = ProviderContainer(
    overrides: [
      sessionProvider.overrideWith((ref) => true),
      currentUserNameProvider.overrideWith((ref) => email),
      managementRepositoryProvider.overrideWith(
          (ref) => ManagementRepositoryMock(currentEmail: email)),
      authRepositoryProvider
          .overrideWithValue(AuthRepositoryMock(storage: SecureStorage())),
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

/// Los mocks responden con retardo y varios providers cargan a la par.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  await tester.pump(const Duration(seconds: 1));
  await tester.pumpAndSettle();
}

/// Abre la pantalla ya con el rol Cajero seleccionado.
Future<void> _openOnCashier(
    WidgetTester tester, ProviderContainer container) async {
  await tester.pumpWidget(_app(container, const PermissionsScreen()));
  await _settle(tester);
  await tester.tap(find.byKey(const Key('roleChip-${RoleCodes.cashier}')));
  await _settle(tester);
}

void main() {
  group('el dueño ajusta un rol a su tienda', () {
    testWidgets('la primera edición avisa a cuántos afecta y marca el rol',
        (tester) async {
      final container = _container();
      await _openOnCashier(tester, container);

      expect(find.byKey(const Key('roleCustomChip')), findsNothing);
      expect(find.text('Ajusta lo que puede hacer este rol en tu tienda'),
          findsOneWidget);

      // Le quita "cobrar" al cajero
      const key = Key('perm-${RoleCodes.cashier}-${Permissions.salesCheckout}');
      expect(tester.widget<SwitchListTile>(find.byKey(key)).value, isTrue);
      await tester.tap(find.byKey(key));
      await _settle(tester);

      // Aviso con el número de personas afectadas (la semilla tiene 2 cajeros)
      expect(find.byKey(const Key('roleCustomizeAffected')), findsOneWidget);
      expect(find.textContaining('2 personas'), findsOneWidget);

      await tester.tap(find.byKey(const Key('roleCustomizeConfirm')));
      await _settle(tester);

      final cajero = container.read(rolesByIdProvider)[RoleCodes.cashier]!;
      expect(cajero.can(Permissions.salesCheckout), isFalse);
      expect(cajero.isCustom, isTrue);
      expect(find.byKey(const Key('roleCustomChip')), findsOneWidget);
      // "Restablecer" aparece al pie de la lista de permisos
      await tester.scrollUntilVisible(
        find.byKey(const Key('roleResetButton')),
        300,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.byKey(const Key('roleResetButton')), findsOneWidget);
    });

    testWidgets('cancelar el aviso deja el rol como estaba', (tester) async {
      final container = _container();
      await _openOnCashier(tester, container);

      await tester.tap(find.byKey(
          const Key('perm-${RoleCodes.cashier}-${Permissions.salesCheckout}')));
      await _settle(tester);
      await tester.tap(find.text('Cancelar'));
      await _settle(tester);

      final cajero = container.read(rolesByIdProvider)[RoleCodes.cashier]!;
      expect(cajero.can(Permissions.salesCheckout), isTrue);
      expect(cajero.isCustom, isFalse);
    });

    testWidgets('la segunda edición del mismo rol ya no pregunta',
        (tester) async {
      final container = _container();
      await _openOnCashier(tester, container);

      await tester.tap(find.byKey(
          const Key('perm-${RoleCodes.cashier}-${Permissions.salesCheckout}')));
      await _settle(tester);
      await tester.tap(find.byKey(const Key('roleCustomizeConfirm')));
      await _settle(tester);

      // Segundo cambio: sin diálogo
      await tester.tap(find.byKey(
          const Key('perm-${RoleCodes.cashier}-${Permissions.salesView}')));
      await _settle(tester);
      expect(find.byKey(const Key('roleCustomizeAffected')), findsNothing);

      final cajero = container.read(rolesByIdProvider)[RoleCodes.cashier]!;
      expect(cajero.can(Permissions.salesView), isFalse);
    });

    testWidgets('restablecer devuelve el rol al estándar', (tester) async {
      final container = _container();
      await _openOnCashier(tester, container);

      await tester.tap(find.byKey(
          const Key('perm-${RoleCodes.cashier}-${Permissions.salesCheckout}')));
      await _settle(tester);
      await tester.tap(find.byKey(const Key('roleCustomizeConfirm')));
      await _settle(tester);

      await tester.scrollUntilVisible(
        find.byKey(const Key('roleResetButton')),
        300,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.byKey(const Key('roleResetButton')));
      await _settle(tester);
      await tester.tap(find.byKey(const Key('roleResetConfirm')));
      await _settle(tester);

      final cajero = container.read(rolesByIdProvider)[RoleCodes.cashier]!;
      expect(cajero.can(Permissions.salesCheckout), isTrue);
      expect(cajero.isCustom, isFalse);
      expect(find.byKey(const Key('roleCustomChip')), findsNothing);
    });
  });

  group('cómo se llega a Permisos', () {
    testWidgets('Usuarios ofrece la entrada, también al Encargado (QA Sep 23)',
        (tester) async {
      for (final email in [_owner, _manager]) {
        final container = _container(email: email);
        await tester.pumpWidget(_app(container, const MembersScreen()));
        await _settle(tester);
        expect(find.byKey(const Key('membersPermissionsButton')), findsOneWidget,
            reason: email);
      }
    });
  });

  group('lo que no se puede tocar', () {
    testWidgets('"ver inventario" queda bloqueado en todo rol', (tester) async {
      final container = _container();
      await _openOnCashier(tester, container);

      final tile = tester.widget<SwitchListTile>(find.byKey(
          const Key('perm-${RoleCodes.cashier}-${Permissions.inventoryView}')));
      expect(tile.value, isTrue);
      expect(tile.onChanged, isNull);
      expect(find.text('Sin esto la app se ve vacía'), findsOneWidget);
    });

    testWidgets('el rol Dueño no se ajusta y se dice por qué', (tester) async {
      final container = _container();
      await tester.pumpWidget(_app(container, const PermissionsScreen()));
      await _settle(tester);

      // El Dueño es el primer rol y ya viene seleccionado
      expect(
        find.text(
            'El dueño tiene acceso a todo por definición: este rol no se ajusta'),
        findsOneWidget,
      );
      expect(find.byType(SwitchListTile), findsNothing);
      expect(find.byKey(const Key('roleResetButton')), findsNothing);
    });

    testWidgets('el Encargado ve la pantalla pero no la edita', (tester) async {
      final container = _container(email: _manager);
      await _openOnCashier(tester, container);

      expect(container.read(canEditPermissionsProvider), isFalse);
      expect(find.byType(SwitchListTile), findsNothing);
      expect(find.text('Sólo el dueño puede cambiar los permisos de un rol'),
          findsOneWidget);
      // Ve qué puede el cajero, que es lo que necesita al asignar roles
      expect(
          find.byKey(
              const Key('perm-${RoleCodes.cashier}-${Permissions.salesCheckout}')),
          findsOneWidget);
    });
  });

  group('reglas del repositorio', () {
    test('el mock aplica las mismas reglas que el servidor', () async {
      final repo = ManagementRepositoryMock(currentEmail: _owner);

      await expectLater(
        repo.updateRolePermissions(
          roleId: RoleCodes.owner,
          permissions: {Permissions.inventoryView},
        ),
        throwsA(isA<ProtectedRoleException>()),
      );

      await expectLater(
        repo.updateRolePermissions(
          roleId: RoleCodes.cashier,
          permissions: {Permissions.salesCheckout},
        ),
        throwsA(isA<MinimumPermissionException>()),
      );

      final ajustado = await repo.updateRolePermissions(
        roleId: RoleCodes.cashier,
        permissions: {Permissions.inventoryView, Permissions.salesView},
      );
      expect(ajustado.isCustom, isTrue);
      expect(ajustado.permissions,
          {Permissions.inventoryView, Permissions.salesView});

      final estandar = await repo.resetRole(RoleCodes.cashier);
      expect(estandar.isCustom, isFalse);
      expect(estandar.can(Permissions.salesCheckout), isTrue);
    });
  });
}
