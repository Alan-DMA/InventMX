import 'dart:js_interop';

import 'package:hive_flutter/hive_flutter.dart';
import 'package:web/web.dart' as web;

import 'tab_browser.dart';

TabBrowser createTabBrowser() => _BrowserTab();

const _tokenKey = 'nexus_support_session';

class _BrowserTab implements TabBrowser {
  final _fallback = MemoryTabBrowser();

  @override
  String? readToken() {
    try {
      return web.window.sessionStorage.getItem(_tokenKey);
    } catch (_) {
      return _fallback.readToken();
    }
  }

  @override
  void writeToken(String token) {
    try {
      web.window.sessionStorage.setItem(_tokenKey, token);
    } catch (_) {
      _fallback.writeToken(token);
    }
  }

  @override
  String? takeLinkCode() {
    final uri = Uri.base;
    final code = uri.queryParameters['c'];
    if (code == null || code.isEmpty) return null;
    // El código no se queda en la barra ni en el historial
    final clean = uri.replace(queryParameters: Map.of(uri.queryParameters)..remove('c'));
    try {
      web.window.history.replaceState(null, '', clean.toString().replaceFirst(RegExp(r'\?$'), ''));
    } catch (_) {}
    return code;
  }

  @override
  Future<void> wipe() async {
    _fallback.token = null;
    try {
      web.window.sessionStorage.clear();
    } catch (_) {}
    try {
      web.window.localStorage.clear();
    } catch (_) {}
    try {
      await Hive.deleteFromDisk();
    } catch (_) {}
    // Lo que Hive no abrió en esta sesión también se va
    try {
      final dbs = await web.window.indexedDB.databases().toDart;
      for (final db in dbs.toDart) {
        final name = db.name;
        if (name.isNotEmpty) web.window.indexedDB.deleteDatabase(name);
      }
    } catch (_) {}
  }

  @override
  void closeTab() {
    try {
      web.window.close();
    } catch (_) {}
  }
}
