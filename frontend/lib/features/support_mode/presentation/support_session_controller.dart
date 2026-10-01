import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/auth_interceptor.dart';
import '../data/support_session_api.dart';
import '../data/tab_browser.dart';
import '../domain/support_session.dart';

/// En qué está la pestaña de soporte.
sealed class SupportPhase {
  const SupportPhase();
}

class SupportOpening extends SupportPhase {
  const SupportOpening();
}

/// El enlace no abrió nada (usado, vencido, sin red, pestaña sin enlace).
class SupportLinkFailed extends SupportPhase {
  const SupportLinkFailed(this.message);
  final String message;
}

class SupportActive extends SupportPhase {
  const SupportActive(this.status);
  final SupportSessionStatus status;
}

/// Terminó: la pestaña ya está limpia.
class SupportClosed extends SupportPhase {
  const SupportClosed(this.end);
  final SupportEnd end;
}

final tabBrowserProvider = Provider<TabBrowser>((_) => createTabBrowser());

final supportSessionApiProvider = Provider<SupportSessionApi>(
  (_) => SupportSessionApiImpl(baseUrl: getEffectiveApiBaseUrl()),
);

/// Cada cuánto se confirma con el servidor que la sesión sigue (el dueño
/// pudo retirar el permiso aunque el operador no toque nada).
final supportSessionPollProvider = Provider<Duration>((_) => const Duration(seconds: 30));

final supportClockProvider = Provider<DateTime Function()>((_) => DateTime.now);

/// Aviso breve en la franja ("no se guardó nada"); la franja lo borra sola.
final supportNoticeProvider = StateProvider<String?>((_) => null);

final supportSessionProvider = NotifierProvider<SupportSessionController, SupportPhase>(
  SupportSessionController.new,
);

class SupportSessionController extends Notifier<SupportPhase> {
  Timer? _poll;
  bool _busy = false;

  TabBrowser get _tab => ref.read(tabBrowserProvider);
  SupportSessionApi get _api => ref.read(supportSessionApiProvider);

  @override
  SupportPhase build() {
    ref.onDispose(() => _poll?.cancel());
    return const SupportOpening();
  }

  /// Arranque: canjea el código del enlace o, tras un F5, retoma el token de la pestaña.
  Future<void> start() async {
    final code = _tab.takeLinkCode();
    try {
      if (code != null) {
        final (token, status) = await _api.open(code);
        _tab.writeToken(token);
        _activate(status);
        return;
      }
      final token = _tab.readToken();
      if (token == null || token.isEmpty) {
        state = const SupportLinkFailed(
          'Esta pestaña se abre desde el panel, con «Ver la tienda (sólo lectura)» en la ficha de la tienda.',
        );
        return;
      }
      _activate(await _api.status(token));
    } on SupportSessionEnded catch (e) {
      await close(e.end);
    } on SupportLinkProblem catch (e) {
      state = SupportLinkFailed(e.message);
    }
  }

  /// Vuelve a preguntar al servidor; si ya terminó, cierra.
  Future<void> refresh() async {
    final token = _tab.readToken();
    if (token == null || state is! SupportActive) return;
    try {
      _activate(await _api.status(token));
    } on SupportSessionEnded catch (e) {
      await close(e.end);
    } on SupportLinkProblem {
      // Sin red: la franja sigue con la última hora conocida; el próximo intento decide
    }
  }

  /// "Seguir 30 min más". Devuelve un mensaje si el servidor no lo permitió.
  Future<String?> extend() async {
    final token = _tab.readToken();
    if (token == null || _busy) return null;
    _busy = true;
    try {
      final (newToken, status) = await _api.extend(token);
      _tab.writeToken(newToken);
      _activate(status);
      return null;
    } on SupportSessionEnded catch (e) {
      await close(e.end);
      return null;
    } on SupportLinkProblem catch (e) {
      return e.message;
    } finally {
      _busy = false;
    }
  }

  /// "Terminar" desde la franja.
  Future<void> end() async {
    final token = _tab.readToken();
    if (token != null) await _api.end(token);
    await close(SupportEnd.operator);
  }

  /// Señal del interceptor de la app (cualquier pantalla).
  void onSignal(String signal) {
    if (signal.startsWith(AuthInterceptor.supportAccessEnded)) {
      final reason = signal.contains(':') ? signal.split(':').last : null;
      unawaited(close(SupportEnd.fromCode(reason)));
    } else if (signal == AuthInterceptor.supportReadOnly) {
      ref.read(supportNoticeProvider.notifier).state = 'Sólo lectura: no se guardó nada';
    } else if (signal == AuthInterceptor.supportNotAllowed) {
      ref.read(supportNoticeProvider.notifier).state = 'Esto no está disponible en modo soporte';
    }
  }

  /// Lo último que dijo el servidor: distingue "retiró" de "venció" al cerrar.
  SupportSessionStatus? _lastStatus;

  Future<void> close(SupportEnd end) async {
    if (state is SupportClosed) return;
    // GRANT_ENDED no dice cuál de los dos: si el permiso aún no vencía, el dueño lo retiró
    final known = _lastStatus;
    if (end == SupportEnd.grantEnded && known != null) {
      final now = ref.read(supportClockProvider)();
      end = now.isBefore(known.grantExpiresAt) ? SupportEnd.grantRevoked : SupportEnd.grantExpired;
    }
    _poll?.cancel();
    _poll = null;
    await _tab.wipe();
    state = SupportClosed(end);
  }

  void _activate(SupportSessionStatus status) {
    _lastStatus = status;
    state = SupportActive(status);
    _poll ??= Timer.periodic(ref.read(supportSessionPollProvider), (_) => refresh());
  }
}
