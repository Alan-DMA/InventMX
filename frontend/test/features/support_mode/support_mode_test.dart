import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_app/core/network/auth_interceptor.dart';
import 'package:nexus_app/core/theme/app_colors.dart';
import 'package:nexus_app/features/support_mode/data/support_session_api.dart';
import 'package:nexus_app/features/support_mode/data/support_token_storage.dart';
import 'package:nexus_app/features/support_mode/data/tab_browser.dart';
import 'package:nexus_app/features/support_mode/domain/support_session.dart';
import 'package:nexus_app/features/support_mode/presentation/support_app.dart';
import 'package:nexus_app/features/support_mode/presentation/support_session_controller.dart';

/// Pestaña de soporte de sólo lectura (Centro de soporte, etapa 4b, P37–P42).
final _t0 = DateTime(2026, 9, 30, 14, 0);

class FakeSessionApi implements SupportSessionApi {
  FakeSessionApi(this.now);

  DateTime Function() now;
  DateTime? expiresAt;
  DateTime? grantExpiresAt;
  Object? openError;
  Object? statusError;
  Object? extendError;
  final List<String> calls = [];

  SupportSessionStatus _status() {
    final exp = expiresAt ?? now().add(const Duration(minutes: 30));
    final grant = grantExpiresAt ?? now().add(const Duration(hours: 1));
    return SupportSessionStatus(
      sessionId: 's1',
      tenantName: 'Abarrotes Rosy',
      operatorName: 'Eduardo',
      reason: 'Revisar el inventario de refrescos',
      openedAt: now(),
      expiresAt: exp,
      grantExpiresAt: grant,
    );
  }

  @override
  Future<(String, SupportSessionStatus)> open(String code) async {
    calls.add('open:$code');
    if (openError != null) throw openError!;
    return ('token-1', _status());
  }

  @override
  Future<SupportSessionStatus> status(String token) async {
    calls.add('status:$token');
    if (statusError != null) throw statusError!;
    return _status();
  }

  @override
  Future<(String, SupportSessionStatus)> extend(String token) async {
    calls.add('extend:$token');
    if (extendError != null) throw extendError!;
    expiresAt = (expiresAt ?? now()).add(const Duration(minutes: 30));
    return ('token-2', _status());
  }

  @override
  Future<void> end(String token) async => calls.add('end:$token');
}

class _Harness {
  _Harness({String? code, String? token}) {
    tab = MemoryTabBrowser(linkCode: code)..token = token;
    api = FakeSessionApi(() => now);
  }

  DateTime now = _t0;
  late final MemoryTabBrowser tab;
  late final FakeSessionApi api;
  late ProviderContainer container;

  Future<void> pump(WidgetTester tester, {Size size = const Size(1440, 900)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        tabBrowserProvider.overrideWithValue(tab),
        supportSessionApiProvider.overrideWithValue(api),
        supportClockProvider.overrideWithValue(() => now),
        supportSessionPollProvider.overrideWithValue(const Duration(seconds: 30)),
        supportStoreBuilderProvider.overrideWithValue(
          (ref) => const Center(child: Text('TIENDA DEL DUEÑO', key: Key('fakeStore'))),
        ),
      ],
      child: const SupportApp(),
    ));
    container = ProviderScope.containerOf(tester.element(find.byType(SupportApp)));
    await tester.pumpAndSettle();
  }

  /// Desmonta para que no queden temporizadores vivos.
  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
  }
}

void main() {
  testWidgets('abre con el enlace: franja con la tienda y el tiempo, la tienda en columna de teléfono', (tester) async {
    final h = _Harness(code: 'abc');
    await h.pump(tester);

    expect(h.api.calls, ['open:abc']);
    expect(h.tab.token, 'token-1');
    expect(h.tab.linkCode, isNull, reason: 'el código se toma una vez');
    expect(find.text('MODO SOPORTE · SÓLO LECTURA'), findsOneWidget);
    expect(find.byKey(const Key('supportStripTenant')), findsOneWidget);
    expect(find.text('Abarrotes Rosy'), findsOneWidget);
    expect(find.text('quedan 30 min'), findsOneWidget);
    expect(find.byKey(const Key('supportStripExtend')), findsNothing);
    expect(find.byKey(const Key('fakeStore')), findsOneWidget);
    // La tienda cree estar en un teléfono
    final media = MediaQuery.of(tester.element(find.byKey(const Key('fakeStore'))));
    expect(media.size.width, SupportApp.phoneWidth);
    await h.dispose(tester);
  });

  testWidgets('en 390 px la franja se compacta y sigue diciendo que es sólo lectura', (tester) async {
    final h = _Harness(code: 'abc');
    await h.pump(tester, size: const Size(390, 844));
    expect(find.text('SOPORTE · SÓLO LECTURA'), findsOneWidget);
    expect(find.text('30 min'), findsOneWidget);
    expect(find.byKey(const Key('supportStripTenant')), findsNothing);
    expect(find.byKey(const Key('supportStripEnd')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await h.dispose(tester);
  });

  testWidgets('enlace ya usado o vencido: dice por qué y qué hacer', (tester) async {
    final h = _Harness(code: 'usado');
    h.api.openError = const SupportLinkProblem('Este enlace ya se usó o no es válido. Ábrelo de nuevo desde el panel.');
    await h.pump(tester);
    expect(find.text('No se pudo abrir la tienda'), findsOneWidget);
    expect(find.textContaining('Ábrelo de nuevo desde el panel'), findsOneWidget);
    expect(find.byKey(const Key('fakeStore')), findsNothing);
    await tester.tap(find.byKey(const Key('supportGateClose')));
    expect(h.tab.closed, isTrue);
    await h.dispose(tester);
  });

  testWidgets('sin enlace ni sesión en la pestaña: explica de dónde se abre', (tester) async {
    final h = _Harness();
    await h.pump(tester);
    expect(find.textContaining('se abre desde el panel'), findsOneWidget);
    expect(h.api.calls, isEmpty);
    await h.dispose(tester);
  });

  testWidgets('F5: retoma la sesión con el token de la pestaña, sin reiniciar el reloj', (tester) async {
    final h = _Harness(token: 'token-1');
    h.api.expiresAt = _t0.add(const Duration(minutes: 12));
    await h.pump(tester);
    expect(h.api.calls, ['status:token-1']);
    expect(find.text('quedan 12 min'), findsOneWidget);
    await h.dispose(tester);
  });

  testWidgets('escribir algo: aviso en la franja que se va solo', (tester) async {
    final h = _Harness(code: 'abc');
    await h.pump(tester);
    h.container.read(supportSessionProvider.notifier).onSignal(AuthInterceptor.supportReadOnly);
    await tester.pump();
    expect(find.text('Sólo lectura: no se guardó nada'), findsOneWidget);
    expect(find.byKey(const Key('fakeStore')), findsOneWidget, reason: 'la tienda sigue');
    await tester.pump(const Duration(seconds: 5));
    expect(find.byKey(const Key('supportStripNotice')), findsNothing);
    await h.dispose(tester);
  });

  testWidgets('el dueño retira el permiso: la tienda se retira y la pestaña queda limpia', (tester) async {
    final h = _Harness(code: 'abc');
    await h.pump(tester);
    h.container.read(supportSessionProvider.notifier).onSignal('SUPPORT_ACCESS_ENDED:GRANT_ENDED');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('fakeStore')), findsNothing);
    expect(find.text('El acceso terminó'), findsOneWidget);
    expect(find.textContaining('El dueño retiró el permiso.'), findsOneWidget, reason: 'aún no vencía: lo retiró');
    expect(find.textContaining('No quedó nada de la tienda guardado'), findsOneWidget);
    expect(find.text('MODO SOPORTE · TERMINADO'), findsOneWidget, reason: 'la franja nunca se va');
    expect(h.tab.wiped, isTrue);
    expect(h.tab.token, isNull);
    await h.dispose(tester);
  });

  testWidgets('con 10 min o menos: "Seguir 30 min más"; con 5 o menos, ámbar', (tester) async {
    final h = _Harness(code: 'abc');
    h.api.expiresAt = _t0.add(const Duration(minutes: 9));
    await h.pump(tester);
    expect(find.byKey(const Key('supportStripExtend')), findsOneWidget);
    var remaining = tester.widget<Text>(find.byKey(const Key('supportStripRemaining')));
    expect(remaining.style?.color, AppColors.onSurface);

    h.now = _t0.add(const Duration(minutes: 5));
    await tester.pump(const Duration(seconds: 5));
    remaining = tester.widget<Text>(find.byKey(const Key('supportStripRemaining')));
    expect(remaining.data, 'quedan 4 min');
    expect(remaining.style?.color, AppColors.warning);

    await tester.tap(find.byKey(const Key('supportStripExtend')));
    await tester.pumpAndSettle();
    expect(h.api.calls.last, 'extend:token-1');
    expect(h.tab.token, 'token-2', reason: 'el servidor da un token nuevo');
    expect(find.text('quedan 34 min'), findsOneWidget);
    expect(find.byKey(const Key('supportStripExtend')), findsNothing);
    await h.dispose(tester);
  });

  testWidgets('el servidor no deja extender: lo dice en la franja', (tester) async {
    final h = _Harness(code: 'abc');
    h.api.expiresAt = _t0.add(const Duration(minutes: 8));
    h.api.extendError = const SupportLinkProblem('El permiso del dueño termina antes: no se puede extender más.');
    await h.pump(tester);
    await tester.tap(find.byKey(const Key('supportStripExtend')));
    await tester.pumpAndSettle();
    expect(find.textContaining('no se puede extender más'), findsOneWidget);
    await h.dispose(tester);
  });

  testWidgets('Terminar: avisa al servidor y cierra', (tester) async {
    final h = _Harness(code: 'abc');
    await h.pump(tester);
    await tester.tap(find.byKey(const Key('supportStripEnd')));
    await tester.pumpAndSettle();
    expect(h.api.calls.last, 'end:token-1');
    expect(find.text('El acceso terminó'), findsOneWidget);
    expect(find.textContaining('Terminaste la sesión'), findsOneWidget);
    await h.dispose(tester);
  });

  testWidgets('el permiso venció (no lo retiraron): lo dice así', (tester) async {
    final h = _Harness(code: 'abc');
    h.api.grantExpiresAt = _t0.add(const Duration(minutes: 20));
    await h.pump(tester);
    h.now = _t0.add(const Duration(minutes: 21));
    h.container.read(supportSessionProvider.notifier).onSignal('SUPPORT_ACCESS_ENDED:GRANT_ENDED');
    await tester.pumpAndSettle();
    expect(find.textContaining('El permiso del dueño venció.'), findsOneWidget);
    await h.dispose(tester);
  });

  testWidgets('sin tocar nada, el sondeo descubre que la sesión terminó', (tester) async {
    final h = _Harness(code: 'abc');
    await h.pump(tester);
    h.api.statusError = const SupportSessionEnded(SupportEnd.expired);
    await tester.pump(const Duration(seconds: 31));
    await tester.pumpAndSettle();
    expect(find.textContaining('Se acabó el tiempo'), findsOneWidget);
    await h.dispose(tester);
  });

  test('el almacenamiento de soporte: token de la pestaña, sin refresh, sin cerrar sesión solo', () async {
    final tab = MemoryTabBrowser()..token = 'token-1';
    final storage = SupportTokenStorage(tab);
    expect(await storage.readAccessToken(), 'token-1');
    expect(await storage.readRefreshToken(), isNull);
    await storage.clearSession();
    expect(tab.token, 'token-1', reason: 'la franja termina la sesión, no un 401 suelto');
    await storage.saveTokens(accessToken: 'token-2', refreshToken: 'x');
    expect(tab.token, 'token-2');
    await storage.write('pref', 'valor');
    expect(await storage.read('pref'), 'valor');
  });

  test('el interceptor avisa a la pestaña con el motivo del fin y los rechazos', () async {
    final signals = <String>[];
    final dio = Dio(BaseOptions(baseUrl: 'http://localhost'));
    final interceptor = AuthInterceptor(
      storage: SupportTokenStorage(MemoryTabBrowser()),
      dio: dio,
      onServerSignal: signals.add,
    );
    DioException error(int status, Map<String, dynamic> body) {
      final options = RequestOptions(path: '/api/v1/inventory/products');
      return DioException(
        requestOptions: options,
        response: Response(requestOptions: options, statusCode: status, data: body),
        type: DioExceptionType.badResponse,
      );
    }

    await interceptor.onError(
      error(401, {
        'error': {'code': 'SUPPORT_ACCESS_ENDED', 'details': {'end_reason': 'GRANT_ENDED'}},
      }),
      _QuietHandler(),
    );
    await interceptor.onError(error(403, {'error': {'code': 'SUPPORT_READ_ONLY'}}), _QuietHandler());
    await interceptor.onError(error(403, {'error': {'code': 'FORBIDDEN'}}), _QuietHandler());
    await Future<void>.delayed(Duration.zero);
    expect(signals, ['SUPPORT_ACCESS_ENDED:GRANT_ENDED', 'SUPPORT_READ_ONLY']);
  });
}

/// Un handler que no completa nada (los de Dio completan con error si nadie escucha).
class _QuietHandler extends ErrorInterceptorHandler {
  @override
  void next(DioException err) {}

  @override
  void reject(DioException error, [bool callFollowingErrorInterceptor = false]) {}

  @override
  void resolve(Response<dynamic> response) {}
}
