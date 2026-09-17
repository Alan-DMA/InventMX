import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nexus_app/core/theme/app_theme.dart';
import 'package:nexus_app/features/inventory/data/import_repository.dart';
import 'package:nexus_app/features/inventory/data/two_tier_lookup.dart';
import 'package:nexus_app/features/inventory/presentation/widgets/scan_result_card.dart';
import 'package:nexus_app/features/sales_pos/data/community_catalog_repository.dart';
import 'package:nexus_app/features/sales_pos/domain/ean_lookup_result.dart' as tier2;

// ---------------------------------------------------------------------------
// Motor de dos niveles en Modo Góndola — semilla primero, comunidad después
// ---------------------------------------------------------------------------

class MockImportRepository extends Mock implements ImportRepository {}

class MockCommunityRepository extends Mock implements CommunityCatalogRepository {}

const _seedHit = EanLookupResult(
  barcode: '7501055300075',
  name: 'Coca-Cola Original 600ml NR',
  category: 'Bebidas',
  source: 'SEED_CATALOG',
  suggestedPriceMxn: 18.5,
);

const _communityHit = tier2.EanLookupResult(
  barcode: '7501017001118',
  source: tier2.EanSource.communityVerified,
  name: 'Frijoles Negros Refritos La Costeña 430g',
  category: 'Abarrotes',
  confidenceScore: 5,
);

void main() {
  late MockImportRepository seed;
  late MockCommunityRepository community;

  setUp(() {
    seed = MockImportRepository();
    community = MockCommunityRepository();
  });

  test('si la semilla responde, no se consulta la comunidad', () async {
    when(() => seed.lookupEan(any())).thenAnswer((_) async => _seedHit);

    final r = await lookupEanTwoTier(seed: seed, community: community, barcode: '7501055300075');

    expect(r, same(_seedHit));
    verifyNever(() => community.lookupEan(any()));
  });

  test('sin coincidencia en semilla cae a la comunidad y conserva el origen', () async {
    when(() => seed.lookupEan(any())).thenAnswer((_) async => null);
    when(() => community.lookupEan(any())).thenAnswer((_) async => _communityHit);

    final r = await lookupEanTwoTier(seed: seed, community: community, barcode: '7501017001118');

    expect(r, isNotNull);
    expect(r!.name, 'Frijoles Negros Refritos La Costeña 430g');
    expect(r.category, 'Abarrotes');
    expect(r.source, 'COMMUNITY_VERIFIED');
    expect(r.confidenceScore, 5);
    verify(() => seed.lookupEan('7501017001118')).called(1);
  });

  test('si la semilla falla (sin red) igual se intenta la comunidad', () async {
    when(() => seed.lookupEan(any())).thenThrow(Exception('offline'));
    when(() => community.lookupEan(any())).thenAnswer((_) async => _communityHit);

    final r = await lookupEanTwoTier(seed: seed, community: community, barcode: '7501017001118');

    expect(r?.source, 'COMMUNITY_VERIFIED');
  });

  test('sin coincidencia en ninguno devuelve null; un fallo en comunidad también', () async {
    when(() => seed.lookupEan(any())).thenAnswer((_) async => null);
    when(() => community.lookupEan(any()))
        .thenAnswer((_) async => const tier2.EanLookupResult.notFound('999'));
    expect(await lookupEanTwoTier(seed: seed, community: community, barcode: '999'), isNull);

    when(() => community.lookupEan(any())).thenThrow(Exception('timeout'));
    expect(await lookupEanTwoTier(seed: seed, community: community, barcode: '999'), isNull);
  });

  // ── La tarjeta distingue el origen ────────────────────────────────────────
  Widget card({String? source, int? matches, String? name = 'Producto X'}) => MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: ScanResultCard(
            barcode: '7501017001118',
            suggestedName: name,
            suggestedCategory: 'Abarrotes',
            source: source,
            communityMatches: matches,
            onConfirm: (_, __, ___) {},
            onDismiss: () {},
          ),
        ),
      );

  testWidgets('ScanResultCard con origen comunitario muestra el conteo de comercios',
      (tester) async {
    await tester.pumpWidget(card(source: 'COMMUNITY_VERIFIED', matches: 5));
    await tester.pump();

    expect(find.text('Verificado por la comunidad Nexus · 5 comercios coinciden'), findsOneWidget);
    expect(find.byIcon(Icons.groups_rounded), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Producto X'), findsOneWidget);
  });

  testWidgets('ScanResultCard con origen semilla conserva el encabezado original',
      (tester) async {
    await tester.pumpWidget(card(source: 'SEED_CATALOG'));
    await tester.pump();

    expect(find.text('Producto encontrado en catálogo'), findsOneWidget);
    expect(find.byIcon(Icons.verified_rounded), findsOneWidget);
  });

  testWidgets('sin nombre sugerido sigue siendo "Código no registrado"', (tester) async {
    await tester.pumpWidget(card(name: null, source: null));
    await tester.pump();

    expect(find.text('Código no registrado'), findsOneWidget);
  });
}
