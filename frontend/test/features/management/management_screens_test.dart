import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_app/core/storage/secure_storage.dart';
import 'package:nexus_app/core/theme/app_theme.dart';
import 'package:nexus_app/features/auth/data/auth_repository.dart';
import 'package:nexus_app/features/auth/presentation/login_provider.dart';
import 'package:nexus_app/features/management/data/management_repository.dart';
import 'package:nexus_app/features/management/domain/app_permission.dart';
import 'package:nexus_app/features/management/domain/tenant_member.dart';
import 'package:nexus_app/features/management/domain/category.dart';
import 'package:nexus_app/features/management/domain/tenant_role.dart';
import 'package:nexus_app/features/management/presentation/categories_screen.dart';
import 'package:nexus_app/features/management/presentation/preferences_screen.dart';
import 'package:nexus_app/features/management/presentation/management_provider.dart';
import 'package:nexus_app/features/management/presentation/members_screen.dart';
import 'package:nexus_app/features/management/presentation/permissions_screen.dart';
import 'package:nexus_app/features/management/presentation/warehouses_screen.dart';

// ---------------------------------------------------------------------------
// Gestión del negocio — almacenes, usuarios y permisos (todo mock)
// ---------------------------------------------------------------------------

const _email = 'eduardo.cristancho@nexus.mx';

ProviderContainer _container({String email = _email}) {
  final container = ProviderContainer(
    overrides: [
      sessionProvider.overrideWith((ref) => true),
      currentUserNameProvider.overrideWith((ref) => email),
      // Personas y roles son reales desde la Fase B (Sep 21): el arnés
      // fija el mock para no pegarle a /users.
      managementRepositoryProvider.overrideWith(
          (ref) => ManagementRepositoryMock(currentEmail: email)),
      // "Precios" (real, Sep 2026) llama a authRepositoryProvider — sin este
      // override haría una petición HTTP real en cada test de esta pantalla.
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

/// El mock responde con retardo: se avanza el reloj a mano antes de asentar
/// (`pumpAndSettle` se detiene en cuanto no queda animación pendiente).
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  await tester.pump(const Duration(seconds: 1));
  await tester.pumpAndSettle();
}

void main() {
  group('Preferencias operativas', () {
    testWidgets('lleva a almacenes y categorías, con su conteo',
        (tester) async {
      final container = _container();
      await tester.pumpWidget(_app(container, const PreferencesScreen()));
      await _settle(tester);

      expect(find.byKey(const Key('preferencesWarehouses')), findsOneWidget);
      expect(find.text('3 almacenes activos'), findsOneWidget);
      expect(find.byKey(const Key('preferencesCategories')), findsOneWidget);
      expect(find.text('5 categorías'), findsOneWidget);
    });

    testWidgets(
        'margen máximo sugerido muestra el valor por defecto y se puede editar',
        (tester) async {
      final container = _container();
      await tester.pumpWidget(_app(container, const PreferencesScreen()));
      await _settle(tester);

      expect(find.byKey(const Key('preferencesMaxMargin')), findsOneWidget);
      expect(find.textContaining('40%'), findsOneWidget);

      await tester.tap(find.byKey(const Key('preferencesMaxMargin')));
      await _settle(tester);

      expect(find.byKey(const Key('maxMarginField')), findsOneWidget);
      await tester.enterText(find.byKey(const Key('maxMarginField')), '25');
      await tester.tap(find.byKey(const Key('saveMaxMarginButton')));
      await _settle(tester);

      expect(find.textContaining('25%'), findsOneWidget);
    });
  });

  group('Categorías', () {
    testWidgets('crear una categoría la agrega a la lista', (tester) async {
      final container = _container();
      await tester.pumpWidget(_app(container, const CategoriesScreen()));
      await _settle(tester);

      await tester.tap(find.byKey(const Key('categoryAddFab')));
      await _settle(tester);
      await tester.enterText(
          find.byKey(const Key('categoryNameField')), 'Lácteos');
      await tester.pump();
      await tester.tap(find.byKey(const Key('categorySaveButton')));
      await _settle(tester);

      expect(find.text('Lácteos'), findsOneWidget);
      expect(find.text('Sin productos todavía'), findsWidgets);
    });

    // Reloj real a propósito: bajo `testWidgets` un `Future.delayed` del mock
    // no avanza si se espera directo, y el test se cuelga.
    test('no deja eliminar una categoría con productos', () async {
      final repo = ManagementRepositoryMock();
      expect(
        () => repo.deleteCategory('cat-001'),
        throwsA(isA<CategoryInUseException>()),
      );
      expect(const CategoryInUseException(5).message, contains('5 productos'));
    });

    testWidgets('la categoría vacía sí se elimina', (tester) async {
      final container = _container();
      await tester.pumpWidget(_app(container, const CategoriesScreen()));
      await _settle(tester);

      unawaited(container.read(categoriesProvider.notifier).remove('cat-005'));
      await _settle(tester);

      expect(find.text('Otros'), findsNothing);
    });

    testWidgets('un nombre repetido se explica dentro de la hoja',
        (tester) async {
      final container = _container();
      await tester.pumpWidget(_app(container, const CategoriesScreen()));
      await _settle(tester);

      await tester.tap(find.byKey(const Key('categoryAddFab')));
      await _settle(tester);
      await tester.enterText(
          find.byKey(const Key('categoryNameField')), 'bebidas');
      await tester.pump();
      await tester.tap(find.byKey(const Key('categorySaveButton')));
      await _settle(tester);

      expect(find.byKey(const Key('categoryFormError')), findsOneWidget);
    });
  });

  group('Almacenes', () {
    testWidgets('crear un almacén lo agrega a la lista', (tester) async {
      final container = _container();
      await tester.pumpWidget(_app(container, const WarehousesScreen()));
      await _settle(tester);

      await tester.tap(find.byKey(const Key('warehouseAddFab')));
      await _settle(tester);
      await tester.enterText(
          find.byKey(const Key('warehouseNameField')), 'Bodega Norte');
      await tester.pump();
      await tester.tap(find.byKey(const Key('warehouseSaveButton')));
      await _settle(tester);

      expect(find.text('Bodega Norte'), findsOneWidget);
      final names =
          container.read(warehousesProvider).valueOrNull!.map((w) => w.name);
      expect(names, contains('Bodega Norte'));
    });

    testWidgets('un nombre repetido se explica dentro del modal',
        (tester) async {
      final container = _container();
      await tester.pumpWidget(_app(container, const WarehousesScreen()));
      await _settle(tester);

      await tester.tap(find.byKey(const Key('warehouseAddFab')));
      await _settle(tester);
      await tester.enterText(
          find.byKey(const Key('warehouseNameField')), 'Mostrador');
      await tester.pump();
      await tester.tap(find.byKey(const Key('warehouseSaveButton')));
      await _settle(tester);

      expect(find.byKey(const Key('warehouseFormError')), findsOneWidget);
      expect(find.textContaining('Ya tienes un almacén'), findsOneWidget);
    });

    testWidgets('dar de baja marca el almacén como inactivo', (tester) async {
      final container = _container();
      await tester.pumpWidget(_app(container, const WarehousesScreen()));
      await _settle(tester);

      unawaited(
          container.read(warehousesProvider.notifier).deactivate('wh-003'));
      await _settle(tester);

      expect(find.text('Inactivo'), findsOneWidget);
      final bodega = container
          .read(warehousesProvider)
          .valueOrNull!
          .firstWhere((w) => w.id == 'wh-003');
      expect(bodega.isActive, isFalse);
      // Y desaparece de lo que el selector de Perfil ofrece.
      expect(
        container.read(activeWarehousesProvider).map((w) => w.id),
        isNot(contains('wh-003')),
      );
    });
  });

  group('Usuarios', () {
    testWidgets('lista a la gente del comercio con su rol', (tester) async {
      final container = _container();
      await tester.pumpWidget(_app(container, const MembersScreen()));
      await _settle(tester);

      expect(find.text('María Hernández'), findsOneWidget);
      expect(find.textContaining('Encargado'), findsWidgets);
      // El usuario en sesión se distingue.
      expect(find.text('Tú'), findsOneWidget);
      // Carlos viene dado de baja en la semilla.
      expect(find.text('Inactivo'), findsOneWidget);
    });

    testWidgets('crear un usuario lo agrega con el rol elegido',
        (tester) async {
      final container = _container();
      await tester.pumpWidget(_app(container, const MembersScreen()));
      await _settle(tester);

      await tester.tap(find.byKey(const Key('memberAddFab')));
      await _settle(tester);
      await tester.enterText(
          find.byKey(const Key('memberNameField')), 'Lucía Fernández');
      await tester.enterText(
          find.byKey(const Key('memberEmailField')), 'lucia@minegocio.mx');
      await tester.enterText(
          find.byKey(const Key('memberPasswordField')), 'lucia123');
      await tester.pump();
      await tester.ensureVisible(find.byKey(const Key('memberRole-WAREHOUSE')));
      await tester.tap(find.byKey(const Key('memberRole-WAREHOUSE')));
      await tester.pump();
      await tester.ensureVisible(find.byKey(const Key('memberSaveButton')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('memberSaveButton')));
      await _settle(tester);

      final nueva = container
          .read(membersProvider)
          .valueOrNull!
          .firstWhere((m) => m.email == 'lucia@minegocio.mx');
      expect(nueva.name, 'Lucía Fernández');
      expect(nueva.roleId, RoleCodes.warehouse);
    });

    testWidgets('un correo repetido se explica dentro del modal',
        (tester) async {
      final container = _container();
      await tester.pumpWidget(_app(container, const MembersScreen()));
      await _settle(tester);

      await tester.tap(find.byKey(const Key('memberAddFab')));
      await _settle(tester);
      await tester.enterText(
          find.byKey(const Key('memberNameField')), 'Otra Persona');
      await tester.enterText(find.byKey(const Key('memberEmailField')),
          'maria.hernandez@nexus.mx');
      await tester.enterText(
          find.byKey(const Key('memberPasswordField')), 'clave123');
      await tester.pump();
      await tester.ensureVisible(find.byKey(const Key('memberSaveButton')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('memberSaveButton')));
      await _settle(tester);

      expect(find.byKey(const Key('memberFormError')), findsOneWidget);
    });

    testWidgets('la lista dice la comisión de quien la tiene y calla la de quien no',
        (tester) async {
      final container = _container();
      await tester.pumpWidget(_app(container, const MembersScreen()));
      await _settle(tester);

      // José Luis (semilla) comisiona 5 % sobre ventas; Ana no.
      expect(find.textContaining('Comisión: 5 % de lo que vende'), findsOneWidget);
      expect(find.textContaining('Comisión: 0'), findsNothing);
    });

    testWidgets('el dueño fija "% de lo que vende" al editar y se refleja en la lista',
        (tester) async {
      final container = _container();
      await tester.pumpWidget(_app(container, const MembersScreen()));
      await _settle(tester);

      // Ana Torres (usr-004) no comisiona todavía.
      await tester.tap(find.descendant(
          of: find.byKey(const Key('member-usr-004')),
          matching: find.byType(PopupMenuButton<String>)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Editar'));
      await _settle(tester);

      // Sin esquema pre-marcado: "No comisiona" es el estado inicial y el
      // campo de tasa no existe hasta elegir uno.
      expect(find.byKey(const Key('memberCommissionRateField')), findsNothing);
      await tester.ensureVisible(find.byKey(const Key('memberCommission-PERCENTAGE_SALE')));
      await tester.tap(find.byKey(const Key('memberCommission-PERCENTAGE_SALE')));
      await tester.pump();
      expect(find.byKey(const Key('memberCommissionRateField')), findsOneWidget);

      // Tasa vacía → no se puede guardar; 150 % → tampoco; 5 → ejemplo en pesos.
      final save = find.byKey(const Key('memberSaveButton'));
      expect(tester.widget<ElevatedButton>(save).onPressed, isNull);
      await tester.enterText(find.byKey(const Key('memberCommissionRateField')), '150');
      await tester.pump();
      expect(tester.widget<ElevatedButton>(save).onPressed, isNull);
      await tester.enterText(find.byKey(const Key('memberCommissionRateField')), '5');
      await tester.pump();
      expect(find.text(r'Con 5 %, una venta de $200 le deja $10.'), findsOneWidget);
      expect(tester.widget<ElevatedButton>(save).onPressed, isNotNull);

      await tester.ensureVisible(save);
      await tester.tap(save);
      await _settle(tester);

      final ana = container
          .read(membersProvider)
          .valueOrNull!
          .firstWhere((m) => m.id == 'usr-004');
      expect(ana.commissionType, CommissionType.percentageSale);
      expect(ana.commissionRate, 5);
      expect(find.textContaining('Comisión: 5 % de lo que vende'), findsNWidgets(2));
    });

    testWidgets('al editar, el correo queda bloqueado y no se pide contraseña',
        (tester) async {
      final container = _container();
      await tester.pumpWidget(_app(container, const MembersScreen()));
      await _settle(tester);
      await tester.tap(find.descendant(
          of: find.byKey(const Key('member-usr-004')),
          matching: find.byType(PopupMenuButton<String>)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Editar'));
      await _settle(tester);

      expect(find.byKey(const Key('memberPasswordField')), findsNothing);
      expect(find.text('El correo no se puede cambiar.'), findsOneWidget);
      final email = tester.widget<TextFormField>(find.byKey(const Key('memberEmailField')));
      expect(email.enabled, isFalse);
    });
  });

  group('Permisos (Fase B: el dueño ajusta los roles a su tienda)', () {
    testWidgets('el dueño ve los permisos reales de cada rol y puede ajustarlos',
        (tester) async {
      final container = _container();
      await tester.pumpWidget(_app(container, const PermissionsScreen()));
      await _settle(tester);

      // El Dueño (primer rol) tiene todo y no se ajusta: sin switches.
      expect(container.read(rolesByIdProvider)[RoleCodes.owner]!.permissions,
          Permissions.all);
      expect(find.byType(SwitchListTile), findsNothing);

      await tester.tap(find.byKey(const Key('roleChip-CASHIER')));
      await _settle(tester);
      final cashier = container.read(rolesByIdProvider)[RoleCodes.cashier]!;
      expect(cashier.can(Permissions.salesCheckout), isTrue);
      expect(cashier.can(Permissions.inventoryCreate), isFalse);
      expect(find.byKey(const Key('perm-CASHIER-sales.checkout')), findsOneWidget);
      // Sobre un rol distinto al suyo, el dueño sí edita.
      expect(find.byType(SwitchListTile), findsWidgets);
      expect(container.read(canEditPermissionsProvider), isTrue);
    });
  });
}
