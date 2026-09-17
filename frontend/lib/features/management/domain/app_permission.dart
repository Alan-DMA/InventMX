import 'package:equatable/equatable.dart';

/// Un permiso del catálogo del comercio.
///
/// Los nombres replican exactamente los sembrados en `backend/app/seed.py`
/// (`<módulo>.<acción>`) para que, cuando Alan exponga el CRUD de roles del
/// tenant, el swap sea sólo cambiar el repositorio y no re-mapear cadenas.
class AppPermission extends Equatable {
  const AppPermission({
    required this.name,
    required this.module,
    required this.description,
  });

  final String name;
  final String module;
  final String description;

  @override
  List<Object?> get props => [name, module, description];
}

/// Catálogo de permisos administrables por el dueño de un comercio.
///
/// `saas.manage` existe en el backend pero **no** aparece aquí: es de la
/// plataforma (panel de fundadores, Tarea 14.2), no del tenant — un
/// comerciante no puede otorgárselo a sus empleados.
abstract final class Permissions {
  static const inventarioVer = 'inventario.ver';
  static const inventarioCrear = 'inventario.crear';
  static const inventarioEditar = 'inventario.editar';
  static const inventarioEditarPrecios = 'inventario.editar_precios';
  static const inventarioEliminar = 'inventario.eliminar';

  /// Propuesto en la decisión técnica #11 — todavía **no existe** en
  /// `seed.py`. Gobierna el selector de almacén operativo (Perfil) y la
  /// sección de Almacenes de Gestión. Al conectar el backend real: si el
  /// permiso no llega en la lista, la UI queda fail-closed.
  static const inventarioGestionarAlmacenes = 'inventario.gestionar_almacenes';

  static const ventasVer = 'ventas.ver';
  static const ventasCrear = 'ventas.crear';
  static const ventasCobrar = 'ventas.cobrar';
  static const ventasVerCostos = 'ventas.ver_costos';
  static const ventasEliminar = 'ventas.eliminar';

  static const comprasVer = 'compras.ver';
  static const comprasCrear = 'compras.crear';
  static const comprasEliminar = 'compras.eliminar';

  static const cajaVer = 'caja.ver';
  static const cajaArquear = 'caja.arquear';
  static const cajaMovimientos = 'caja.movimientos';

  static const usuariosVer = 'usuarios.ver';
  static const usuariosGestionar = 'usuarios.gestionar';

  static const catalog = <AppPermission>[
    AppPermission(
      name: inventarioVer,
      module: 'inventario',
      description: 'Ver productos y existencias',
    ),
    AppPermission(
      name: inventarioCrear,
      module: 'inventario',
      description: 'Dar de alta productos nuevos',
    ),
    AppPermission(
      name: inventarioEditar,
      module: 'inventario',
      description: 'Editar la información de un producto',
    ),
    AppPermission(
      name: inventarioEditarPrecios,
      module: 'inventario',
      description: 'Modificar precios y costos en \$ MXN',
    ),
    AppPermission(
      name: inventarioEliminar,
      module: 'inventario',
      description: 'Dar de baja productos',
    ),
    AppPermission(
      name: inventarioGestionarAlmacenes,
      module: 'inventario',
      description:
          'Crear almacenes y cambiar el almacén donde opera cada quien',
    ),
    AppPermission(
      name: ventasVer,
      module: 'ventas',
      description: 'Ver el historial de ventas',
    ),
    AppPermission(
      name: ventasCrear,
      module: 'ventas',
      description: 'Armar el carrito y preparar una venta',
    ),
    AppPermission(
      name: ventasCobrar,
      module: 'ventas',
      description: 'Cobrar y cerrar la venta (descuenta stock)',
    ),
    AppPermission(
      name: ventasVerCostos,
      module: 'ventas',
      description: 'Ver ganancia y costo de compra en cada venta',
    ),
    AppPermission(
      name: ventasEliminar,
      module: 'ventas',
      description: 'Anular o devolver ventas ya cobradas',
    ),
    AppPermission(
      name: comprasVer,
      module: 'compras',
      description: 'Ver proveedores y órdenes de compra',
    ),
    AppPermission(
      name: comprasCrear,
      module: 'compras',
      description: 'Registrar compras y recibir mercancía',
    ),
    AppPermission(
      name: comprasEliminar,
      module: 'compras',
      description: 'Anular compras registradas',
    ),
    AppPermission(
      name: cajaVer,
      module: 'caja',
      description: 'Ver el estado de la caja y los cortes',
    ),
    AppPermission(
      name: cajaArquear,
      module: 'caja',
      description: 'Abrir turno y hacer el corte de caja',
    ),
    AppPermission(
      name: cajaMovimientos,
      module: 'caja',
      description: 'Registrar retiros y entradas de caja menor',
    ),
    AppPermission(
      name: usuariosVer,
      module: 'usuarios',
      description: 'Ver quién trabaja en el negocio',
    ),
    AppPermission(
      name: usuariosGestionar,
      module: 'usuarios',
      description: 'Dar de alta usuarios y cambiar sus permisos',
    ),
  ];

  /// Etiqueta legible de cada módulo, en el orden en que se muestran.
  static const moduleLabels = <String, String>{
    'inventario': 'Inventario',
    'ventas': 'Ventas',
    'compras': 'Compras',
    'caja': 'Caja',
    'usuarios': 'Usuarios',
  };

  static List<AppPermission> ofModule(String module) =>
      catalog.where((p) => p.module == module).toList();

  static AppPermission? byName(String name) {
    for (final permission in catalog) {
      if (permission.name == name) return permission;
    }
    return null;
  }
}
