import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'session_store_memory.dart' if (dart.library.js_interop) 'session_store_web.dart' as impl;

/// Almacén de la pestaña (P30): en web es `sessionStorage` — sobrevive a F5 y
/// muere al cerrar la pestaña. Guarda la sesión del operador y los borradores
/// de respuesta; nada más.
abstract class SessionStore {
  String? read(String key);
  void write(String key, String value);
  void remove(String key);
  Iterable<String> keys();
}

/// En memoria: tests y cualquier plataforma que no sea web.
class MemorySessionStore implements SessionStore {
  final Map<String, String> values = {};

  @override
  String? read(String key) => values[key];

  @override
  void write(String key, String value) => values[key] = value;

  @override
  void remove(String key) => values.remove(key);

  @override
  Iterable<String> keys() => values.keys.toList();
}

final sessionStoreProvider = Provider<SessionStore>((_) => impl.createSessionStore());
