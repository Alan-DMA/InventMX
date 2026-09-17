import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/dio_client.dart';
import '../../auth/data/auth_repository.dart';
import '../domain/clone_catalog.dart';
import '../domain/product.dart';

// ---------------------------------------------------------------------------
// Contrato
// ---------------------------------------------------------------------------

typedef CloneProgressCallback = void Function(CloneProgress progress);

abstract class CloneCatalogRepository {
  /// Resuelve una tienda destino por su código público. Null si no existe.
  ///
  /// Sin contrato en `docs/api` todavía (Tarea 15.1 pendiente): la
  /// implementación real apunta a `GET /inventory/clone-targets/{code}` y
  /// queda documentada como supuesto en la bitácora.
  Future<CloneTarget?> findTargetByCode(String code);

  /// `POST /inventory/clone-catalog` — duplica el catálogo con stock en 0.
  ///
  /// [sourceProducts] es el catálogo local ya cargado: el mock lo usa para
  /// contar y reportar avance; la implementación real lo ignora (el backend
  /// clona desde su propia base). [onProgress] es opcional y solo lo alimenta
  /// el mock.
  Future<CloneCatalogResult> cloneCatalog(
    CloneCatalogRequest request, {
    List<Product> sourceProducts = const [],
    CloneProgressCallback? onProgress,
  });
}

// ---------------------------------------------------------------------------
// Mock — activo hasta que Alan entregue Tarea 15.1.2 (servicio de clonación)
// ---------------------------------------------------------------------------

class CloneCatalogRepositoryMock implements CloneCatalogRepository {
  CloneCatalogRepositoryMock({
    this.stepDelay = const Duration(milliseconds: 90),
    this.lookupDelay = const Duration(milliseconds: 350),
  });

  final Duration stepDelay;
  final Duration lookupDelay;

  /// Tiendas de ejemplo para QA. Se buscan por código, como en producción:
  /// el dueño de la otra tienda comparte su código, no se listan ajenas.
  static const List<CloneTarget> targets = [
    CloneTarget(
      tenantId: 't-sucursal-centro',
      code: '220118',
      name: 'Bodega El Sol — Sucursal Centro',
      productCount: 0,
    ),
    CloneTarget(
      tenantId: 't-aliada-norte',
      code: '310542',
      name: 'Abarrotes Doña Mary (aliada)',
      productCount: 12,
    ),
  ];

  @override
  Future<CloneTarget?> findTargetByCode(String code) async {
    await Future.delayed(lookupDelay);
    final clean = code.trim();
    return targets.where((t) => t.code == clean).firstOrNull;
  }

  @override
  Future<CloneCatalogResult> cloneCatalog(
    CloneCatalogRequest request, {
    List<Product> sourceProducts = const [],
    CloneProgressCallback? onProgress,
  }) async {
    final target = targets.where((t) => t.tenantId == request.targetTenantId).firstOrNull;
    if (target == null) {
      throw const CloneCatalogException(
        'No encontramos esa tienda. Revisa el código con su dueño.',
        code: 'TENANT_NOT_FOUND',
      );
    }

    final toClone = sourceProducts
        .where((p) => p.isActive)
        .where((p) => request.filterCategory == null || p.category == request.filterCategory)
        .toList();

    for (var i = 0; i < toClone.length; i++) {
      await Future.delayed(stepDelay);
      onProgress?.call(CloneProgress(
        done: i + 1,
        total: toClone.length,
        currentName: toClone[i].name,
      ));
    }

    return CloneCatalogResult(
      productsCloned: toClone.length,
      targetTenantId: target.tenantId,
      clonedAt: DateTime.now(),
    );
  }
}

// ---------------------------------------------------------------------------
// Implementación real — contrato docs/api/inventory.yaml
// ---------------------------------------------------------------------------

class CloneCatalogRepositoryImpl implements CloneCatalogRepository {
  CloneCatalogRepositoryImpl({required this.client});

  final DioClient client;

  static dynamic _unwrap(dynamic body) =>
      body is Map && body.containsKey('data') ? body['data'] : body;

  @override
  Future<CloneTarget?> findTargetByCode(String code) async {
    try {
      final res = await client.get(
        '/api/v1/inventory/clone-targets/${Uri.encodeComponent(code.trim())}',
      );
      final data = _unwrap(res.data);
      return data is Map ? CloneTarget.fromJson(data) : null;
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      throw CloneCatalogException(_message(e));
    }
  }

  @override
  Future<CloneCatalogResult> cloneCatalog(
    CloneCatalogRequest request, {
    List<Product> sourceProducts = const [],
    CloneProgressCallback? onProgress,
  }) async {
    try {
      final res = await client.post(
        '/api/v1/inventory/clone-catalog',
        data: request.toJson(),
      );
      final data = _unwrap(res.data);
      if (data is! Map) {
        throw const CloneCatalogException('Respuesta inesperada del servidor.');
      }
      return CloneCatalogResult.fromJson(data);
    } on DioException catch (e) {
      throw CloneCatalogException(_message(e), code: _code(e));
    }
  }

  static String? _code(DioException e) {
    final body = e.response?.data;
    if (body is Map && body['error'] is Map) {
      return (body['error'] as Map)['code']?.toString();
    }
    return null;
  }

  static String _message(DioException e) {
    final body = e.response?.data;
    if (body is Map && body['error'] is Map) {
      final m = (body['error'] as Map)['message']?.toString();
      if (m != null && m.isNotEmpty) return m;
    }
    return switch (e.response?.statusCode) {
      403 => 'La clonación de catálogos solo está disponible en el plan Corporativo.',
      404 => 'No encontramos esa tienda. Revisa el código con su dueño.',
      _ => 'No se pudo clonar el catálogo. Revisa tu conexión e intenta de nuevo.',
    };
  }
}

// ---------------------------------------------------------------------------
// Provider — mock por defecto (D15): el endpoint no existe en el backend
// montado. `--dart-define=CLONE_MOCK=false` para apuntar al real.
// ---------------------------------------------------------------------------

const bool kCloneUseMock = bool.fromEnvironment('CLONE_MOCK', defaultValue: true);

final cloneCatalogRepositoryProvider = Provider<CloneCatalogRepository>((ref) {
  if (kCloneUseMock) return CloneCatalogRepositoryMock();
  return CloneCatalogRepositoryImpl(client: ref.watch(dioClientProvider));
});
