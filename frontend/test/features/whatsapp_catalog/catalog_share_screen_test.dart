import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nexus_app/core/theme/app_theme.dart';
import 'package:nexus_app/features/purchases/presentation/widgets/phone_launcher.dart';
import 'package:nexus_app/features/whatsapp_catalog/data/whatsapp_catalog_repository.dart';
import 'package:nexus_app/features/whatsapp_catalog/domain/catalog_settings.dart';
import 'package:nexus_app/features/whatsapp_catalog/domain/public_catalog.dart';
import 'package:nexus_app/features/whatsapp_catalog/domain/whatsapp_order.dart';
import 'package:nexus_app/features/whatsapp_catalog/presentation/catalog_share_screen.dart';
import 'package:nexus_app/features/whatsapp_catalog/presentation/whatsapp_catalog_provider.dart';
import 'package:url_launcher/url_launcher.dart';

class _FakeRepo implements WhatsappCatalogRepository {
  _FakeRepo({String? number = '+52 55 1234 5678'})
      : settings = CatalogSettings(
          slug: 'abarrotes-don-pepe',
          storeName: 'Abarrotes Don Pepe',
          whatsappNumber: number,
        );

  CatalogSettings settings;
  bool failUpdate = false;

  @override
  Future<CatalogSettings> getSettings() async => settings;

  @override
  Future<CatalogSettings> updateSettings(
      {bool? isCatalogEnabled, String? whatsappNumber}) async {
    if (failUpdate) throw StateError('sin red');
    settings = settings.copyWith(
      isCatalogEnabled: isCatalogEnabled,
      whatsappNumber: whatsappNumber == null ? null : () => whatsappNumber,
    );
    return settings;
  }

  @override
  Future<PublicCatalog> fetchPublicCatalog(String slug,
          {String? search, String? categoryId}) =>
      throw UnimplementedError();

  @override
  Future<WhatsAppOrderBuild> buildWhatsAppOrder(
          String slug, WhatsAppOrderDraft draft) =>
      throw UnimplementedError();

  @override
  Future<SavedOrder> submitOrder(String slug, WhatsAppOrderDraft draft) =>
      throw UnimplementedError();

  @override
  Future<SavedOrder> fetchOrder(String slug, String folio) =>
      throw UnimplementedError();
}

Future<(_FakeRepo, List<Uri>, List<String>)> _pump(
  WidgetTester tester, {
  _FakeRepo? repo,
}) async {
  tester.view.physicalSize = const Size(412 * 3, 915 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final fake = repo ?? _FakeRepo();
  final launched = <Uri>[];
  final visited = <String>[];
  final clipboard = <String>[];

  // Portapapeles: se registra lo copiado.
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'Clipboard.setData') {
        clipboard.add((call.arguments as Map)['text'] as String);
      }
      return null;
    },
  );
  addTearDown(() => tester.binding.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, null));

  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (_, __) => const CatalogShareScreen()),
      GoRoute(
        path: '/tienda/:slug',
        builder: (_, state) {
          visited.add(state.pathParameters['slug']!);
          return const Scaffold(body: Text('vitrina'));
        },
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        catalogStoreNameProvider
            .overrideWith((_) async => 'Abarrotes Don Pepe'),
        whatsappCatalogRepositoryProvider.overrideWithValue(fake),
        urlLauncherProvider.overrideWithValue(
          (Uri uri, {LaunchMode mode = LaunchMode.platformDefault}) async {
            launched.add(uri);
            return true;
          },
        ),
      ],
      child: MaterialApp.router(theme: AppTheme.dark, routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return (fake, launched, clipboard);
}

void main() {
  group('CatalogShareScreen — panel de difusión (13.2.3)', () {
    testWidgets('muestra estado, número, enlace y QR', (tester) async {
      await _pump(tester);

      expect(find.text('Catálogo activo'), findsOneWidget);
      expect(find.textContaining('Los pedidos llegan al +52 55 1234 5678'),
          findsOneWidget);
      expect(find.byKey(const Key('catalogLink')), findsOneWidget);
      expect(find.textContaining('/abarrotes-don-pepe'), findsWidgets);
      expect(find.byKey(const Key('catalogQr')), findsOneWidget);
    });

    testWidgets('copiar deja el enlace en el portapapeles', (tester) async {
      final (_, _, clipboard) = await _pump(tester);

      await tester.tap(find.byKey(const Key('catalogCopyLink')));
      await tester.pumpAndSettle();

      expect(clipboard.single, endsWith('/tienda/abarrotes-don-pepe'));
      expect(find.text('Enlace copiado'), findsOneWidget);
    });

    testWidgets('compartir por WhatsApp abre wa.me con el enlace',
        (tester) async {
      final (_, launched, _) = await _pump(tester);

      await tester.tap(find.byKey(const Key('catalogShareWhatsApp')));
      await tester.pumpAndSettle();

      expect(launched.single.host, 'wa.me');
      expect(launched.single.queryParameters['text'],
          contains('/tienda/abarrotes-don-pepe'));
      expect(launched.single.queryParameters['text'],
          contains('Abarrotes Don Pepe'));
    });

    testWidgets('el switch apaga el catálogo y lo dice', (tester) async {
      final (repo, _, _) = await _pump(tester);

      await tester.tap(find.byKey(const Key('catalogEnabledSwitch')));
      await tester.pumpAndSettle();

      expect(repo.settings.isCatalogEnabled, isFalse);
      expect(find.text('Catálogo apagado'), findsOneWidget);
    });

    testWidgets('si guardar falla, el switch regresa y avisa', (tester) async {
      final (repo, _, _) = await _pump(tester);
      repo.failUpdate = true;

      await tester.tap(find.byKey(const Key('catalogEnabledSwitch')));
      await tester.pumpAndSettle();

      expect(find.text('Catálogo activo'), findsOneWidget);
      expect(find.textContaining('No se pudo cambiar'), findsOneWidget);
    });

    testWidgets('sin número lo pide en ámbar y "Agregar" lo guarda',
        (tester) async {
      final (repo, _, _) = await _pump(tester, repo: _FakeRepo(number: null));

      expect(
          find.textContaining('Falta tu número de WhatsApp'), findsOneWidget);
      await tester.tap(find.byKey(const Key('catalogEditNumber')));
      await tester.pumpAndSettle();

      // Menos de 10 dígitos no pasa.
      await tester.enterText(
          find.byKey(const Key('catalogNumberField')), '55 12');
      await tester.tap(find.byKey(const Key('catalogNumberSave')));
      await tester.pumpAndSettle();
      expect(find.textContaining('10 dígitos'), findsOneWidget);

      await tester.enterText(
          find.byKey(const Key('catalogNumberField')), '+52 33 9876 5432');
      await tester.tap(find.byKey(const Key('catalogNumberSave')));
      await tester.pumpAndSettle();

      expect(repo.settings.whatsappNumber, '+52 33 9876 5432');
      expect(find.textContaining('Los pedidos llegan al +52 33 9876 5432'),
          findsOneWidget);
    });

    testWidgets('"Ver como cliente" abre la vitrina de su slug',
        (tester) async {
      await _pump(tester);

      await tester.ensureVisible(find.byKey(const Key('catalogPreview')));
      await tester.tap(find.byKey(const Key('catalogPreview')));
      await tester.pumpAndSettle();

      expect(find.text('vitrina'), findsOneWidget);
    });
  });
}
