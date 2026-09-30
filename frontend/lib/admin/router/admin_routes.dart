/// Rutas del panel de plataforma.
abstract final class AdminRoutes {
  static const access = '/acceso';
  static const today = '/hoy';
  static const cases = '/casos';
  static const audit = '/bitacora';
  static const helpTopics = '/temas';

  static String casePath(String id) => '$cases/$id';

  /// Adónde regresar tras entrar: sólo rutas propias del panel (nunca una URL
  /// externa ni el propio acceso).
  static String safeReturn(String? raw) {
    if (raw == null || raw.isEmpty || !raw.startsWith('/') || raw.startsWith('//')) return today;
    if (raw == access || raw.startsWith('$access?')) return today;
    return raw;
  }

  AdminRoutes._();
}
