import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/admin_http.dart';
import 'admin_session.dart';

/// "Salir" del panel: primero avisa al servidor para que termine las sesiones
/// de soporte abiertas del operador (etapa 4), luego borra la sesión local.
/// Si el servidor no responde, se sale igual: la sesión de soporte vence sola.
Future<void> signOutOfPanel(WidgetRef ref) async {
  final session = ref.read(adminSessionProvider).session;
  if (session != null) {
    try {
      // Las rutas /auth/* no llevan el token automáticamente: aquí sí hace falta
      await ref.read(adminDioProvider).post<void>(
            '/auth/logout',
            options: Options(headers: {'Authorization': 'Bearer ${session.token}'}),
          );
    } catch (_) {}
  }
  ref.read(adminSessionProvider.notifier).signOut();
}
