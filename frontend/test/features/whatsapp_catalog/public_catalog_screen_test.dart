import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus_app/features/whatsapp_catalog/presentation/widgets/order_sheet.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_app/features/purchases/presentation/widgets/phone_launcher.dart';
import 'package:nexus_app/features/whatsapp_catalog/data/whatsapp_catalog_repository.dart';
import 'package:nexus_app/features/whatsapp_catalog/data/whatsapp_message_formatter.dart';
import 'package:nexus_app/features/whatsapp_catalog/domain/catalog_settings.dart';
import 'package:nexus_app/features/whatsapp_catalog/domain/public_catalog.dart';
import 'package:nexus_app/features/whatsapp_catalog/domain/whatsapp_order.dart';
import 'package:nexus_app/features/whatsapp_catalog/presentation/public_catalog_screen.dart';
import 'package:nexus_app/features/whatsapp_catalog/presentation/whatsapp_catalog_provider.dart';
import 'package:url_launcher/url_launcher.dart';

// ---------------------------------------------------------------------------
// Dobles
// ---------------------------------------------------------------------------

const _demoStore = PublicStoreInfo(
  name: 'Abarrotes Don Pepe',
  slug: 'abarrotes-don-pepe',
  whatsappNumber: '+52 55 1234 5678',
  businessHours: 'Lunes a Sábado 8:00 AM - 8:00 PM',
  minOrderAmountMxn: 50,
  deliveryFeeMxn: 20,
);

const _products = [
  PublicCatalogProduct(
    id: 'coca',
    name: 'Coca-Cola 600ml',
    sku: 'COCA',
    categoryId: 'bebidas',
    categoryName: 'Bebidas',
    priceMxn: 18,
  ),
  PublicCatalogProduct(
    id: 'pan',
    name: 'Pan Bimbo Grande',
    sku: 'PAN',
    categoryId: 'panaderia',
    categoryName: 'Panadería',
    priceMxn: 52,
  ),
  PublicCatalogProduct(
    id: 'sab',
    name: 'Sabritas 45g',
    sku: 'SAB',
    categoryId: 'botanas',
    categoryName: 'Botanas',
    priceMxn: 17,
    inStock: false,
  ),
];

/// Repositorio controlable: filtra en memoria y registra las llamadas.
class _FakeRepo implements WhatsappCatalogRepository {
  _FakeRepo({
    this.failWith,
    PublicStoreInfo store = _demoStore,
    this.latency = Duration.zero,
  }) : _store = store;

  final Object? failWith;
  final Duration latency;
  final PublicStoreInfo _store;
  final builtDrafts = <WhatsAppOrderDraft>[];
  bool failBuild = false;

  @override
  Future<PublicCatalog> fetchPublicCatalog(String slug,
      {String? search, String? categoryId}) async {
    await Future<void>.delayed(latency);
    if (failWith != null) throw failWith!;
    if (slug != _store.slug) throw StoreNotFound(slug);
    var items = _products;
    if (categoryId != null) {
      items = items.where((p) => p.categoryId == categoryId).toList();
    }
    final q = (search ?? '').toLowerCase();
    if (q.isNotEmpty) {
      items = items.where((p) => p.name.toLowerCase().contains(q)).toList();
    }
    return PublicCatalog(
      store: _store,
      categories: const [
        PublicCategory(id: 'bebidas', name: 'Bebidas', productCount: 1),
        PublicCategory(id: 'botanas', name: 'Botanas', productCount: 1),
        PublicCategory(id: 'panaderia', name: 'Panadería', productCount: 1),
      ],
      products: items,
      totalProducts: 3,
    );
  }

  @override
  Future<WhatsAppOrderBuild> buildWhatsAppOrder(
      String slug, WhatsAppOrderDraft draft) async {
    if (failBuild) throw StateError('servidor caído');
    builtDrafts.add(draft);
    return const WhatsAppMessageFormatter().build(store: _store, draft: draft);
  }

  final submitted = <SavedOrder>[];
  bool failSubmit = false;

  @override
  Future<SavedOrder> submitOrder(String slug, WhatsAppOrderDraft draft) async {
    if (failSubmit) throw StateError('servidor caído');
    final totals =
        const WhatsAppMessageFormatter().build(store: _store, draft: draft);
    final order = SavedOrder(
      folio: 'P-260914-TEST',
      slug: slug,
      issuedAt: DateTime(2026, 9, 14, 12, 0),
      draft: draft,
      totals: totals,
    );
    submitted.add(order);
    return order;
  }

  @override
  Future<SavedOrder> fetchOrder(String slug, String folio, {String? accessKey}) async =>
      submitted.firstWhere((o) => o.folio == folio,
          orElse: () => throw OrderNotFound(folio));

  @override
  Future<CatalogSettings> getSettings() => throw UnimplementedError();

  @override
  Future<CatalogSettings> updateSettings({
    bool? isCatalogEnabled,
    String? whatsappNumber,
    String? welcomeMessage,
    double? minOrderAmountMxn,
    double? deliveryFeeMxn,
    bool? deliveryEnabled,
    bool? pickupEnabled,
    String? businessHours,
  }) =>
      throw UnimplementedError();
}

class _Launcher {
  final launched = <Uri>[];
  bool succeed = true;

  Future<bool> call(Uri uri,
      {LaunchMode mode = LaunchMode.platformDefault}) async {
    launched.add(uri);
    return succeed;
  }
}

Future<(_FakeRepo, _Launcher)> _pump(
  WidgetTester tester, {
  _FakeRepo? repo,
  String slug = 'abarrotes-don-pepe',
}) async {
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final fake = repo ?? _FakeRepo();
  final launcher = _Launcher();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        catalogStoreNameProvider
            .overrideWith((_) async => 'Abarrotes Don Pepe'),
        whatsappCatalogRepositoryProvider.overrideWithValue(fake),
        urlLauncherProvider.overrideWithValue(launcher.call),
      ],
      child: MaterialApp(home: PublicCatalogScreen(slug: slug)),
    ),
  );
  await tester.pump();
  return (fake, launcher);
}

Future<void> _settle(WidgetTester tester) async {
  // Debounce del buscador (250 ms) + animaciones de la barra.
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pumpAndSettle();
}

Future<void> _tapAdd(WidgetTester tester, String productId) async {
  final card = find.byKey(ValueKey('product-$productId'));
  await tester.tap(find.descendant(
    of: card,
    matching: find.byIcon(Icons.add_rounded),
  ));
  await tester.pump();
}

void main() {
  group('PublicCatalogScreen — vitrina (13.2.1)', () {
    testWidgets('muestra skeleton y luego la tienda con sus productos',
        (tester) async {
      await _pump(tester,
          repo: _FakeRepo(latency: const Duration(milliseconds: 500)));
      expect(find.byKey(const Key('catalogSkeleton')), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 600));
      await _settle(tester);
      expect(find.byKey(const Key('storeName')), findsOneWidget);
      expect(find.text('Abarrotes Don Pepe'), findsOneWidget);
      expect(find.text('Lunes a Sábado 8:00 AM - 8:00 PM'), findsOneWidget);
      expect(find.text('Coca-Cola 600ml'), findsOneWidget);
      expect(find.text('\$18.00'), findsOneWidget);
      expect(find.text('\$52.00'), findsOneWidget);
      // Las reglas de la tienda se dicen arriba, no en el checkout.
      expect(find.text('Mínimo \$50.00'), findsOneWidget);
      expect(find.text('Envío \$20.00'), findsOneWidget);
    });

    testWidgets('el agotado se escribe y no tiene "+"', (tester) async {
      await _pump(tester);
      await _settle(tester);

      final card = find.byKey(const ValueKey('product-sab'));
      expect(find.descendant(of: card, matching: find.text('Agotado')),
          findsOneWidget);
      expect(
        find.descendant(of: card, matching: find.byIcon(Icons.add_rounded)),
        findsNothing,
      );
    });

    testWidgets('"+" convierte el botón en stepper y muestra la barra',
        (tester) async {
      await _pump(tester);
      await _settle(tester);
      expect(find.text('Ver mi pedido'), findsOneWidget);
      // Escondida: no responde.
      final barMaterial = tester.widget<AnimatedOpacity>(find.ancestor(
        of: find.byKey(const Key('orderBar')),
        matching: find.byType(AnimatedOpacity),
      ));
      expect(barMaterial.opacity, 0);

      await _tapAdd(tester, 'coca');
      await _tapAdd(tester, 'coca');
      await _settle(tester);

      final card = find.byKey(const ValueKey('product-coca'));
      expect(
          find.descendant(of: card, matching: find.text('2')), findsOneWidget);
      expect(find.byKey(const Key('orderBarTotal')), findsOneWidget);
      expect(find.text('\$36.00'), findsOneWidget);
    });

    testWidgets('el buscador filtra (con debounce) y se puede limpiar',
        (tester) async {
      await _pump(tester);
      await _settle(tester);

      await tester.enterText(find.byKey(const Key('catalogSearch')), 'pan');
      await _settle(tester);
      expect(find.text('Pan Bimbo Grande'), findsOneWidget);
      expect(find.text('Coca-Cola 600ml'), findsNothing);

      await tester.tap(find.byKey(const Key('catalogSearchClear')));
      await _settle(tester);
      expect(find.text('Coca-Cola 600ml'), findsOneWidget);
    });

    testWidgets('sin resultados ofrece "Ver todo"', (tester) async {
      await _pump(tester);
      await _settle(tester);

      await tester.enterText(find.byKey(const Key('catalogSearch')), 'zzz');
      await _settle(tester);
      expect(find.byKey(const Key('catalogEmpty')), findsOneWidget);

      await tester.tap(find.byKey(const Key('catalogClearFilters')));
      await _settle(tester);
      expect(find.text('Coca-Cola 600ml'), findsOneWidget);
    });

    testWidgets('los chips de categoría filtran y se destildan',
        (tester) async {
      await _pump(tester);
      await _settle(tester);

      await tester.tap(find.byKey(const Key('category-bebidas')));
      await _settle(tester);
      expect(find.text('Coca-Cola 600ml'), findsOneWidget);
      expect(find.text('Pan Bimbo Grande'), findsNothing);

      await tester.tap(find.byKey(const Key('category-bebidas')));
      await _settle(tester);
      expect(find.text('Pan Bimbo Grande'), findsOneWidget);
    });
  });

  group('PublicCatalogScreen — estados honestos', () {
    testWidgets('tienda inexistente', (tester) async {
      await _pump(tester, slug: 'no-existe');
      await _settle(tester);

      expect(find.byKey(const Key('catalogFailure')), findsOneWidget);
      expect(find.text('No encontramos esta tienda'), findsOneWidget);
      expect(find.byKey(const Key('catalogRetry')), findsNothing);
    });

    testWidgets('catálogo apagado nombra a la tienda', (tester) async {
      await _pump(tester,
          repo:
              _FakeRepo(failWith: const CatalogDisabled('Abarrotes Don Pepe')));
      await _settle(tester);

      expect(
        find.text('Abarrotes Don Pepe tiene su catálogo apagado por ahora'),
        findsOneWidget,
      );
    });

    testWidgets('sin conexión permite reintentar', (tester) async {
      await _pump(tester,
          repo: _FakeRepo(failWith: const CatalogUnavailable()));
      await _settle(tester);

      expect(find.text('No pudimos cargar el catálogo'), findsOneWidget);
      expect(find.byKey(const Key('catalogRetry')), findsOneWidget);
    });
  });

  group('OrderSheet — pedido y envío (13.2.2)', () {
    Future<void> openSheet(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('orderBar')));
      await tester.pumpAndSettle();
    }

    testWidgets('error de validación: el foco sube al primer campo inválido (nombre)',
        (tester) async {
      await _pump(tester);
      await _settle(tester);
      await _tapAdd(tester, 'coca');
      await _tapAdd(tester, 'coca');
      await _tapAdd(tester, 'coca'); // $54 ≥ mínimo $50: el envío queda habilitado
      await _settle(tester);
      await openSheet(tester);

      // A domicilio sin nombre ni dirección: dos errores, el nombre va primero
      await tester.tap(find.byKey(const Key('delivery-delivery')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('orderSend')));
      await tester.tap(find.byKey(const Key('orderSend')));
      await tester.pumpAndSettle();

      expect(find.text('Escribe tu nombre para que la tienda sepa de quién es.'),
          findsOneWidget);
      final nameField = tester.widget<EditableText>(find.descendant(
        of: find.byKey(const Key('orderName')),
        matching: find.byType(EditableText),
      ));
      expect(nameField.focusNode.hasFocus, isTrue);
      final addressField = tester.widget<EditableText>(find.descendant(
        of: find.byKey(const Key('orderAddress')),
        matching: find.byType(EditableText),
      ));
      expect(addressField.focusNode.hasFocus, isFalse);
    });

    testWidgets('nota por renglón (U-09): se agrega, se ve en la línea y se quita',
        (tester) async {
      await _pump(tester);
      await _settle(tester);
      await _tapAdd(tester, 'coca');
      await _settle(tester);
      await openSheet(tester);

      expect(find.text('Agregar nota'), findsOneWidget);
      await tester.tap(find.text('Agregar nota'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('orderNoteField')), 'bien fría');
      await tester.tap(find.byKey(const Key('orderNoteSave')));
      await tester.pumpAndSettle();

      expect(find.text('bien fría'), findsOneWidget);
      expect(find.text('Agregar nota'), findsNothing);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(OrderSheet)),
      );
      expect(container.read(orderCartProvider).lines.values.single.notes, 'bien fría');

      await tester.tap(find.text('bien fría'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('orderNoteClear')));
      await tester.pumpAndSettle();
      expect(find.text('Agregar nota'), findsOneWidget);
      expect(container.read(orderCartProvider).lines.values.single.notes, isNull);
    });

    testWidgets('exige nombre y avisa el pedido mínimo', (tester) async {
      await _pump(tester);
      await _settle(tester);
      await _tapAdd(tester, 'coca'); // $18 < mínimo $50
      await _settle(tester);
      await openSheet(tester);

      expect(find.text('Tu pedido'), findsOneWidget);
      expect(find.byKey(const Key('orderMinNotice')), findsOneWidget);
      expect(find.textContaining('Te faltan \$32.00'), findsOneWidget);
      final send =
          tester.widget<FilledButton>(find.byKey(const Key('orderSend')));
      expect(send.onPressed, isNull);
    });

    testWidgets(
        'a domicilio pide dirección y suma el envío; efectivo calcula '
        'cambio', (tester) async {
      await _pump(tester);
      await _settle(tester);
      await _tapAdd(tester, 'pan'); // $52 ≥ mínimo
      await _settle(tester);
      await openSheet(tester);

      await tester.tap(find.byKey(const Key('delivery-delivery')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('orderAddress')), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('orderTotals')));
      expect(find.text('Envío a domicilio'), findsWidgets); // totales + ticket
      expect(find.text('\$72.00'), findsWidgets); // total = 52 + 20

      await tester.enterText(find.byKey(const Key('orderCash')), '100');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('orderChange')), findsOneWidget);
      expect(find.text('Cambio: \$28.00'), findsOneWidget);

      // Sin nombre ni dirección no se envía.
      await tester.ensureVisible(find.byKey(const Key('orderSend')));
      await tester.tap(find.byKey(const Key('orderSend')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Escribe tu nombre'), findsOneWidget);
      expect(find.textContaining('Escribe la dirección'), findsOneWidget);
    });

    Future<void> readyToSend(WidgetTester tester) async {
      await _settle(tester);
      await _tapAdd(tester, 'pan');
      await _settle(tester);
      await openSheet(tester);
      await tester.enterText(find.byKey(const Key('orderName')), 'Ana');
      await tester.pumpAndSettle();
    }

    testWidgets('la vista previa es el ticket: folio, cliente y total',
        (tester) async {
      await _pump(tester);
      await readyToSend(tester);
      await tester.ensureVisible(find.byKey(const Key('orderPreview')));

      expect(find.byKey(const Key('orderPreview')), findsOneWidget);
      expect(find.textContaining('Folio P-'), findsOneWidget);
      expect(find.text('ABARROTES DON PEPE'), findsOneWidget);
      // El nombre aparece en el campo y en el ticket.
      expect(find.text('Ana'), findsNWidgets(2));
      expect(find.text('\$52.00 MXN'), findsOneWidget);
      expect(find.text('Recoger en tienda'), findsWidgets);
    });

    testWidgets('sin renglones válidos la vista previa explica por qué',
        (tester) async {
      await _pump(tester);
      await _settle(tester);
      await _tapAdd(tester, 'coca'); // por debajo del mínimo
      await _settle(tester);
      await openSheet(tester);

      expect(find.byKey(const Key('orderPreviewReason')), findsOneWidget);
      expect(find.byKey(const Key('orderPreview')), findsNothing);
    });

    testWidgets(
        'enviar registra el pedido y abre el chat de la tienda con '
        'folio y enlace', (tester) async {
      final (repo, launcher) = await _pump(tester);
      await readyToSend(tester);

      await tester.ensureVisible(find.byKey(const Key('orderSend')));
      await tester.tap(find.byKey(const Key('orderSend')));
      await tester.pumpAndSettle();

      expect(repo.submitted.single.draft.customerName, 'Ana');
      final link = launcher.launched.single;
      expect(link.host, 'wa.me');
      expect(link.path, '/525512345678'); // directo al número: sin contactos
      final text = link.queryParameters['text']!;
      expect(text, contains('Pedido P-260914-TEST'));
      expect(text, contains('Ana · 1 artículo · recoger en tienda'));
      expect(text, contains('Total: \$52.00 MXN'));
      expect(text, contains('/tienda/abarrotes-don-pepe/pedido/P-260914-TEST'));
      // El detalle NO viaja en el texto: vive en el ticket.
      expect(text, isNot(contains('Pan Bimbo Grande')));
      expect(find.text('Tu pedido'), findsNothing);
      expect(find.textContaining('Pedido P-260914-TEST listo'), findsOneWidget);
    });

    testWidgets('si WhatsApp no abre, ofrece copiar el aviso', (tester) async {
      final (_, launcher) = await _pump(tester);
      launcher.succeed = false;
      await readyToSend(tester);

      await tester.ensureVisible(find.byKey(const Key('orderSend')));
      await tester.tap(find.byKey(const Key('orderSend')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('orderCopyFallback')), findsOneWidget);
      expect(find.text('Tu pedido'), findsOneWidget);
    });

    testWidgets('sin servidor no hay folio: va el detalle completo en el texto',
        (tester) async {
      final (repo, launcher) = await _pump(tester);
      repo.failSubmit = true;
      await readyToSend(tester);

      await tester.ensureVisible(find.byKey(const Key('orderSend')));
      await tester.tap(find.byKey(const Key('orderSend')));
      await tester.pumpAndSettle();

      final link = launcher.launched.single;
      expect(link.path, '/525512345678');
      expect(link.queryParameters['text'], contains('*Pan Bimbo Grande* x1'));
      expect(find.text('Tu pedido'), findsNothing);
    });

    testWidgets('sin número de WhatsApp en la tienda no se puede enviar',
        (tester) async {
      await _pump(
        tester,
        repo: _FakeRepo(
          store: const PublicStoreInfo(
            name: 'Abarrotes Don Pepe',
            slug: 'abarrotes-don-pepe',
          ),
        ),
      );
      await _settle(tester);
      await _tapAdd(tester, 'pan');
      await _settle(tester);
      await openSheet(tester);

      expect(find.byKey(const Key('orderNoWhatsapp')), findsOneWidget);
      final send =
          tester.widget<FilledButton>(find.byKey(const Key('orderSend')));
      expect(send.onPressed, isNull);
    });

    testWidgets('"Vaciar" limpia el pedido y esconde la barra', (tester) async {
      await _pump(tester);
      await _settle(tester);
      await _tapAdd(tester, 'pan');
      await _settle(tester);
      await openSheet(tester);

      await tester.tap(find.byKey(const Key('orderClear')));
      await _settle(tester);

      expect(find.text('Tu pedido'), findsNothing);
      final card = find.byKey(const ValueKey('product-pan'));
      expect(
        find.descendant(of: card, matching: find.byIcon(Icons.add_rounded)),
        findsOneWidget,
      );
    });
  });
}
