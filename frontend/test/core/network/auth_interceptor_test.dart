import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nexus_app/core/network/auth_interceptor.dart';
import 'package:nexus_app/core/storage/secure_storage.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class MockSecureStorage extends Mock implements SecureStorage {}

class MockRequestInterceptorHandler extends Mock
    implements RequestInterceptorHandler {}

class MockErrorInterceptorHandler extends Mock
    implements ErrorInterceptorHandler {}

// ---------------------------------------------------------------------------
// Fakes — requeridos por mocktail para usar any() con tipos personalizados
// Causa 1: registerFallbackValue debe llamarse antes de any(that: predicate<T>)
// ---------------------------------------------------------------------------

class FakeRequestOptions extends Fake implements RequestOptions {}

class FakeDioException extends Fake implements DioException {}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

RequestOptions _buildOptions({Map<String, dynamic>? headers}) {
  return RequestOptions(
    path: '/api/v1/inventory/products',
    headers: headers ?? {},
  );
}

DioException _build401(RequestOptions options) {
  return DioException(
    requestOptions: options,
    response: Response(requestOptions: options, statusCode: 401),
    type: DioExceptionType.badResponse,
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // Causa 1: registrar fallbacks antes de cualquier test
  setUpAll(() {
    registerFallbackValue(FakeRequestOptions());
    registerFallbackValue(FakeDioException());
  });

  late MockSecureStorage storage;
  late Dio dio;
  late AuthInterceptor interceptor;
  late MockRequestInterceptorHandler requestHandler;
  late MockErrorInterceptorHandler errorHandler;

  setUp(() {
    storage = MockSecureStorage();
    dio = Dio(BaseOptions(baseUrl: 'http://localhost:8000'));
    interceptor = AuthInterceptor(storage: storage, dio: dio);
    requestHandler = MockRequestInterceptorHandler();
    errorHandler = MockErrorInterceptorHandler();

    // Causa 2: los stubs deben retornar Future explícitamente.
    // thenAnswer((_) async => null) garantiza Future<String?> no Null.
    when(() => storage.readAccessToken()).thenAnswer((_) async => null);
    when(() => storage.readRefreshToken()).thenAnswer((_) async => null);
    when(() => storage.clearAll()).thenAnswer((_) async {});
    when(() => requestHandler.next(any())).thenReturn(null);
    when(() => errorHandler.next(any())).thenReturn(null);
  });

  // --- auth_interceptor_header_test ---
  group('onRequest — adjunta header Bearer', () {
    test('adjunta Authorization: Bearer cuando hay access token', () async {
      when(() => storage.readAccessToken())
          .thenAnswer((_) async => 'test.access.token');

      final options = _buildOptions();
      await interceptor.onRequest(options, requestHandler);

      verify(
        () => requestHandler.next(
          any(
            that: predicate<RequestOptions>(
              (o) => o.headers['Authorization'] == 'Bearer test.access.token',
            ),
          ),
        ),
      ).called(1);
    });

    test('no adjunta Authorization cuando no hay token', () async {
      // stub ya configurado en setUp: readAccessToken → null
      final options = _buildOptions();
      await interceptor.onRequest(options, requestHandler);

      verify(
        () => requestHandler.next(
          any(
            that: predicate<RequestOptions>(
              (o) => !o.headers.containsKey('Authorization'),
            ),
          ),
        ),
      ).called(1);
    });

    test('no adjunta Authorization cuando token está vacío', () async {
      when(() => storage.readAccessToken()).thenAnswer((_) async => '');

      final options = _buildOptions();
      await interceptor.onRequest(options, requestHandler);

      verify(
        () => requestHandler.next(
          any(
            that: predicate<RequestOptions>(
              (o) => !o.headers.containsKey('Authorization'),
            ),
          ),
        ),
      ).called(1);
    });
  });

  // --- auth_interceptor_logout_test ---
  group('onError 401 — limpieza de sesión cuando no hay refresh token', () {
    test('llama clearAll y propaga el error si no hay refresh token', () async {
      // readRefreshToken ya retorna null por defecto (setUp)
      bool logoutCalled = false;

      // Causa 3: instancia nueva con handler fresco para evitar estado sucio
      final freshErrorHandler = MockErrorInterceptorHandler();
      when(() => freshErrorHandler.next(any())).thenReturn(null);

      final interceptorWithLogout = AuthInterceptor(
        storage: storage,
        dio: dio,
        onLogout: () async => logoutCalled = true,
      );

      final options = _buildOptions();
      final err = _build401(options);

      await interceptorWithLogout.onError(err, freshErrorHandler);

      verify(() => storage.clearAll()).called(1);
      expect(logoutCalled, isTrue);
      verify(() => freshErrorHandler.next(err)).called(1);
    });

    test('no intenta refresh si el request ya tiene el header de reintento',
        () async {
      final options = _buildOptions(headers: {'X-Retry-Request': 'true'});
      final err = _build401(options);

      await interceptor.onError(err, errorHandler);

      verifyNever(() => storage.readRefreshToken());
      verify(() => errorHandler.next(err)).called(1);
    });
  });

  // --- auth_interceptor_refresh_test ---
  group('onError 401 — estructura del flujo de refresh', () {
    test('llama readRefreshToken cuando hay un 401 sin flag de reintento',
        () async {
      when(() => storage.readRefreshToken())
          .thenAnswer((_) async => 'mock.refresh.token');

      final options = _buildOptions();
      final err = _build401(options);

      // El refresh real fallará (sin servidor), pero validamos que
      // el flujo llegue a leer el refresh token antes de intentarlo.
      await interceptor.onError(err, errorHandler);

      verify(() => storage.readRefreshToken()).called(1);
    });
  });
}
