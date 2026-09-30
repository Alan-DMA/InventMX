import 'package:web/web.dart' as web;

import 'session_store.dart';

SessionStore createSessionStore() => _BrowserSessionStore();

/// `sessionStorage` puede lanzar (almacenamiento bloqueado, modo privado de
/// algunos navegadores): entonces el panel sigue en memoria y sólo pierde la
/// sesión al recargar.
class _BrowserSessionStore implements SessionStore {
  final _fallback = MemorySessionStore();

  @override
  String? read(String key) {
    try {
      return web.window.sessionStorage.getItem(key);
    } catch (_) {
      return _fallback.read(key);
    }
  }

  @override
  void write(String key, String value) {
    try {
      web.window.sessionStorage.setItem(key, value);
    } catch (_) {
      _fallback.write(key, value);
    }
  }

  @override
  void remove(String key) {
    try {
      web.window.sessionStorage.removeItem(key);
    } catch (_) {}
    _fallback.remove(key);
  }

  @override
  Iterable<String> keys() {
    try {
      final storage = web.window.sessionStorage;
      return [
        for (var i = 0; i < storage.length; i++)
          if (storage.key(i) case final key?) key,
      ];
    } catch (_) {
      return _fallback.keys();
    }
  }
}
