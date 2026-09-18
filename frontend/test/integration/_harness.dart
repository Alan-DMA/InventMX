import 'package:dio/dio.dart';
import 'package:nexus_app/core/network/dio_client.dart';
import 'package:nexus_app/core/storage/secure_storage.dart';
import 'package:nexus_app/features/auth/data/auth_repository.dart';

/// Harness compartido para los tests de integración (Fase actual, Sep 2026).
///
/// Estos tests NO son widget tests: instancian los repositorios *Impl
/// directo, con un `DioClient` real apuntando al backend levantado en
/// `127.0.0.1:8000` (mismo host que la guía de QA en
/// `docs/architecture/registro_implementacion.md`). No requieren
/// dispositivo/emulador — sólo que el backend esté corriendo.
///
/// Usan un tenant dedicado (`integrationTestEmail`) para no mezclar datos
/// de prueba con el tenant real que se usa para QA manual
/// (`eduardo@nexus.com`).
const String integrationBaseUrl = 'http://127.0.0.1:8000';

const String integrationTestEmail = 'integration-test@nexus.mx';
const String integrationTestPassword = 'Integracion123';
const String integrationTestSlug = 'tienda-integracion-tests';

/// `true` si el backend responde en `/health`. Se usa para saltar el grupo
/// entero con un mensaje claro en vez de tronar con un error de conexión
/// confuso cuando alguien corre `flutter test` sin el backend levantado.
Future<bool> isBackendUp() async {
  try {
    final dio = Dio(BaseOptions(
      baseUrl: integrationBaseUrl,
      connectTimeout: const Duration(seconds: 2),
      receiveTimeout: const Duration(seconds: 2),
    ));
    final response = await dio.get<dynamic>('/health');
    return response.statusCode == 200;
  } catch (_) {
    return false;
  }
}

/// Sesión autenticada contra el backend real, lista para construir
/// cualquier `*RepositoryImpl` que necesite un `DioClient` con Bearer.
class IntegrationSession {
  const IntegrationSession({required this.storage, required this.client});

  final SecureStorage storage;
  final DioClient client;
}

/// Inicia sesión con el tenant dedicado a tests de integración —lo registra
/// la primera vez que corre, y en las siguientes sólo hace login (idempotente,
/// no falla si el tenant ya existe de una corrida anterior).
Future<IntegrationSession> signInIntegrationTenant() async {
  final storage = SecureStorage();
  final client = DioClient(baseUrl: integrationBaseUrl, storage: storage);
  final auth = AuthRepositoryImpl(client: client, storage: storage);

  try {
    await auth.login(
      email: integrationTestEmail,
      password: integrationTestPassword,
    );
  } on AuthException {
    // No existe todavía — se registra una única vez.
    await client.post<dynamic>('/api/v1/auth/register', data: {
      'store_name': 'Tienda de Integración',
      'slug': integrationTestSlug,
      'full_name': 'Integration Test',
      'email': integrationTestEmail,
      'password': integrationTestPassword,
    });
    await auth.login(
      email: integrationTestEmail,
      password: integrationTestPassword,
    );
  }

  return IntegrationSession(storage: storage, client: client);
}

/// El registro de tenant crea un almacén por defecto ("Almacén Principal").
/// `GET /api/v1/inventory/warehouses` no pasa por `InventoryRepository`
/// (la propia app lo llama directo, ver `inventory_provider.dart`).
Future<String> fetchDefaultWarehouseId(DioClient client) async {
  final response = await client.get<dynamic>('/api/v1/inventory/warehouses');
  final data = response.data as List;
  return (data.first as Map)['id'].toString();
}
