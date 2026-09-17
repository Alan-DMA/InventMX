import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/dio_client.dart';
import '../../auth/data/auth_repository.dart';
import '../domain/ean_lookup_result.dart';

// ---------------------------------------------------------------------------
// Contrato
// ---------------------------------------------------------------------------

abstract class CommunityCatalogRepository {
  /// `GET /inventory/lookup-ean/{barcode}` — motor de dos niveles (RF-29).
  ///
  /// Nunca lanza por "no encontrado": devuelve `EanLookupResult.notFound`.
  /// Solo lanza ante fallo de red, y el llamador lo trata como "sin
  /// sugerencia" — la red comunitaria jamás bloquea una venta.
  Future<EanLookupResult> lookupEan(String barcode);
}

// ---------------------------------------------------------------------------
// Mock — activo hasta que Alan entregue Tarea 15.1 (consenso comunitario).
// Por defecto (D15): el endpoint no existe en el backend montado, así que el
// real respondería 404 siempre y el distintivo nunca se vería.
// `--dart-define=COMMUNITY_MOCK=false` para apuntar al backend real.
// ---------------------------------------------------------------------------

class CommunityCatalogRepositoryMock implements CommunityCatalogRepository {
  CommunityCatalogRepositoryMock({this.delay = const Duration(milliseconds: 400)});

  final Duration delay;

  /// Códigos de ejemplo para QA. Ninguno coincide con los 15 productos del
  /// inventario mock (`inventory_mock_data.dart`), así que al teclearlos en
  /// el POS siempre se llega al estado "sin resultados locales" y aparece la
  /// sugerencia. Barcodes reales de productos mexicanos.
  static const Map<String, EanLookupResult> seed = {
    // Tier 1 — catálogo semilla GS1 México
    '7501055300075': EanLookupResult(
      barcode: '7501055300075',
      source: EanSource.seedCatalog,
      name: 'Coca-Cola Original 600ml NR',
      category: 'Bebidas',
    ),
    '7501000611119': EanLookupResult(
      barcode: '7501000611119',
      source: EanSource.seedCatalog,
      name: 'Galletas Marías Gamesa 170g',
      category: 'Galletas',
    ),
    // Tier 2 — verificado por consenso de ≥ 3 comercios
    '7501017001118': EanLookupResult(
      barcode: '7501017001118',
      source: EanSource.communityVerified,
      name: 'Frijoles Negros Refritos La Costeña 430g',
      category: 'Abarrotes',
      confidenceScore: 5,
    ),
    '7501058617890': EanLookupResult(
      barcode: '7501058617890',
      source: EanSource.communityVerified,
      name: 'Café Soluble Nescafé Clásico 120g',
      category: 'Abarrotes',
      confidenceScore: 3,
    ),

    // ── Ampliación D15 (QA de Eduardo) ──────────────────────────────────
    // Tier 1 — 5 más del Top de abarrotes México (mismos códigos que
    // `ImportRepositoryMock` para que POS y Góndola coincidan)
    '7501030424564': EanLookupResult(
      barcode: '7501030424564',
      source: EanSource.seedCatalog,
      name: 'Pan Blanco Bimbo Grande 680g',
      category: 'Panadería',
    ),
    '7501020512113': EanLookupResult(
      barcode: '7501020512113',
      source: EanSource.seedCatalog,
      name: 'Leche Lala Entera 1L Tetra Pak',
      category: 'Lácteos',
    ),
    '7501005101010': EanLookupResult(
      barcode: '7501005101010',
      source: EanSource.seedCatalog,
      name: 'Harina de Maíz Nixtamalizado Maseca 1kg',
      category: 'Abarrotes',
    ),
    '7501031322401': EanLookupResult(
      barcode: '7501031322401',
      source: EanSource.seedCatalog,
      name: 'Peñafiel Mineral con Gas 600ml',
      category: 'Bebidas',
    ),
    '7501011115668': EanLookupResult(
      barcode: '7501011115668',
      source: EanSource.seedCatalog,
      name: 'Sabritas Sal 45g',
      category: 'Botanas y Snacks',
    ),
    // Tier 2 — 5 más verificados por consenso (3 a 7 comercios)
    '7501008000010': EanLookupResult(
      barcode: '7501008000010',
      source: EanSource.communityVerified,
      name: 'Atún Dolores en Agua 140g',
      category: 'Abarrotes',
      confidenceScore: 7,
    ),
    '7501005112023': EanLookupResult(
      barcode: '7501005112023',
      source: EanSource.communityVerified,
      name: 'Mayonesa McCormick con Limón 390g',
      category: 'Abarrotes',
      confidenceScore: 4,
    ),
    '7501000622221': EanLookupResult(
      barcode: '7501000622221',
      source: EanSource.communityVerified,
      name: 'Galletas Chokis Clásicas 76g',
      category: 'Galletas',
      confidenceScore: 6,
    ),
    '7501064191234': EanLookupResult(
      barcode: '7501064191234',
      source: EanSource.communityVerified,
      name: 'Cerveza Corona Extra 355ml Lata',
      category: 'Bebidas y Licores',
      confidenceScore: 3,
    ),
    '7501017002221': EanLookupResult(
      barcode: '7501017002221',
      source: EanSource.communityVerified,
      name: 'Chiles Jalapeños Enteros La Costeña 220g',
      category: 'Abarrotes',
      confidenceScore: 5,
    ),
  };

  @override
  Future<EanLookupResult> lookupEan(String barcode) async {
    await Future.delayed(delay);
    final clean = barcode.trim();
    return seed[clean] ?? EanLookupResult.notFound(clean);
  }
}

// ---------------------------------------------------------------------------
// Implementación real — contrato docs/api/inventory.yaml
// ---------------------------------------------------------------------------

class CommunityCatalogRepositoryImpl implements CommunityCatalogRepository {
  CommunityCatalogRepositoryImpl({required this.client});

  final DioClient client;

  @override
  Future<EanLookupResult> lookupEan(String barcode) async {
    final clean = Uri.encodeComponent(barcode.trim());
    try {
      final response = await client.get('/api/v1/inventory/lookup-ean/$clean');
      final dynamic body = response.data;
      // El contrato envuelve en `{ success, data }`; se tolera el cuerpo plano.
      final dynamic data = body is Map && body.containsKey('data') ? body['data'] : body;
      if (data is! Map) return EanLookupResult.notFound(barcode);
      return EanLookupResult.fromJson(data);
    } on DioException catch (e) {
      // 404 BARCODE_NOT_FOUND es un resultado, no un error.
      if (e.response?.statusCode == 404) return EanLookupResult.notFound(barcode);
      rethrow;
    }
  }
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

const bool kCommunityUseMock =
    bool.fromEnvironment('COMMUNITY_MOCK', defaultValue: true);

final communityCatalogRepositoryProvider = Provider<CommunityCatalogRepository>(
  (ref) {
    if (kCommunityUseMock) return CommunityCatalogRepositoryMock();
    return CommunityCatalogRepositoryImpl(client: ref.watch(dioClientProvider));
  },
);
