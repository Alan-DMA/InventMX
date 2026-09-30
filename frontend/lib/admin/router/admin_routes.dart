/// Rutas del panel de plataforma.
abstract final class AdminRoutes {
  static const access = '/acceso';
  static const today = '/hoy';
  static const cases = '/casos';
  static const audit = '/bitacora';
  static const helpTopics = '/temas';

  static String casePath(String id) => '$cases/$id';

  /// La ficha de una tienda vive en la dirección (`?tienda=<id>`): sobrevive a
  /// F5 y a la sesión vencida, y se abre sobre cualquier sección.
  static const storeParam = 'tienda';

  static String withStore(Uri current, String tenantId) =>
      current.replace(queryParameters: {...current.queryParameters, storeParam: tenantId}).toString();

  static String withoutStore(Uri current) {
    final query = Map.of(current.queryParameters)..remove(storeParam);
    return Uri(path: current.path, queryParameters: query.isEmpty ? null : query).toString();
  }

  /// Adónde regresar tras entrar: sólo rutas propias del panel (nunca una URL
  /// externa ni el propio acceso).
  static String safeReturn(String? raw) {
    if (raw == null || raw.isEmpty || !raw.startsWith('/') || raw.startsWith('//')) return today;
    if (raw == access || raw.startsWith('$access?')) return today;
    return raw;
  }

  AdminRoutes._();
}
