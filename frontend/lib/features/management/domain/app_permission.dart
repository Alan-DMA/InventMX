import 'package:equatable/equatable.dart';

/// Un permiso del catálogo del comercio.
///
/// Los códigos replican **exactamente** los sembrados en
/// `backend/migrations/versions/0002_seed_rbac_permissions.py`
/// (`<módulo>.<acción>`, en inglés). Son los que viajan en
/// `GET /auth/me → role.permissions[].code` y los que `require_permission`
/// exige en cada endpoint: una puerta del frontend sobre un código que no
/// exista en el servidor sería una mentira.
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

/// Catálogo de permisos del comercio (21 códigos del seed).
///
/// `saas.manage` / la condición de fundador no aparece aquí: es de la
/// plataforma (panel de fundadores, Tarea 14.2), no del tenant.
abstract final class Permissions {
  static const inventoryView = 'inventory.view';
  static const inventoryCreate = 'inventory.create';
  static const inventoryEditPrice = 'inventory.edit_price';
  static const inventoryAdjustStock = 'inventory.adjust_stock';
  static const inventoryDelete = 'inventory.delete';

  static const salesView = 'sales.view';
  static const salesCheckout = 'sales.checkout';
  static const salesApplyDiscount = 'sales.apply_discount';
  static const salesCancel = 'sales.cancel';

  static const cashView = 'cash.view';
  static const cashOpenSession = 'cash.open_session';
  static const cashCloseSession = 'cash.close_session';
  static const cashManualMovement = 'cash.manual_movement';

  static const purchasesView = 'purchases.view';
  static const purchasesCreate = 'purchases.create';
  static const purchasesPayCredit = 'purchases.pay_credit';

  static const reportsViewBasic = 'reports.view_basic';
  static const reportsViewAdvanced = 'reports.view_advanced';

  static const settingsManageUsers = 'settings.manage_users';
  static const settingsManageStore = 'settings.manage_store';
  static const settingsBilling = 'settings.billing';

  static const catalog = <AppPermission>[
    AppPermission(
      name: inventoryView,
      module: 'inventory',
      description: 'Ver productos, categorías y existencias',
    ),
    AppPermission(
      name: inventoryCreate,
      module: 'inventory',
      description: 'Dar de alta productos e importar desde Excel',
    ),
    AppPermission(
      name: inventoryEditPrice,
      module: 'inventory',
      description: 'Editar productos, precios y costos en \$ MXN',
    ),
    AppPermission(
      name: inventoryAdjustStock,
      module: 'inventory',
      description: 'Ajustes de stock, traslados, mermas y modo góndola',
    ),
    AppPermission(
      name: inventoryDelete,
      module: 'inventory',
      description: 'Dar de baja productos',
    ),
    AppPermission(
      name: salesView,
      module: 'sales',
      description: 'Ver el historial de ventas y los pedidos web',
    ),
    AppPermission(
      name: salesCheckout,
      module: 'sales',
      description: 'Cobrar en el punto de venta (descuenta stock)',
    ),
    AppPermission(
      name: salesApplyDiscount,
      module: 'sales',
      description: 'Aplicar descuentos o cortesías al cobrar',
    ),
    AppPermission(
      name: salesCancel,
      module: 'sales',
      description: 'Reembolsar o anular ventas ya cobradas',
    ),
    AppPermission(
      name: cashView,
      module: 'cash',
      description: 'Ver el estado de la caja y los cortes',
    ),
    AppPermission(
      name: cashOpenSession,
      module: 'cash',
      description: 'Abrir turno con fondo inicial',
    ),
    AppPermission(
      name: cashCloseSession,
      module: 'cash',
      description: 'Cerrar turno y hacer el corte de caja',
    ),
    AppPermission(
      name: cashManualMovement,
      module: 'cash',
      description: 'Registrar retiros y entradas de caja chica',
    ),
    AppPermission(
      name: purchasesView,
      module: 'purchases',
      description: 'Ver proveedores, compras y cuentas por pagar',
    ),
    AppPermission(
      name: purchasesCreate,
      module: 'purchases',
      description: 'Registrar compras y recibir mercancía',
    ),
    AppPermission(
      name: purchasesPayCredit,
      module: 'purchases',
      description: 'Abonar a proveedores',
    ),
    AppPermission(
      name: reportsViewBasic,
      module: 'reports',
      description: 'Ver Reportes: ventas, ganancia y stock',
    ),
    AppPermission(
      name: reportsViewAdvanced,
      module: 'reports',
      description: 'Analítica avanzada, márgenes netos y KPIs',
    ),
    AppPermission(
      name: settingsManageUsers,
      module: 'settings',
      description: 'Dar de alta usuarios, asignar rol, almacén y comisión',
    ),
    AppPermission(
      name: settingsManageStore,
      module: 'settings',
      description:
          'Preferencias operativas: almacenes, categorías, margen y catálogo web',
    ),
    AppPermission(
      name: settingsBilling,
      module: 'settings',
      description: 'Mi suscripción y pagos a Nexus',
    ),
  ];

  /// Etiqueta legible de cada módulo, en el orden en que se muestran.
  static const moduleLabels = <String, String>{
    'inventory': 'Inventario',
    'sales': 'Ventas',
    'cash': 'Caja',
    'purchases': 'Compras',
    'reports': 'Reportes',
    'settings': 'Administración',
  };

  /// Todos los códigos — lo que tiene un `OWNER` (el servidor no le siembra
  /// filas: `require_permission` lo deja pasar por definición).
  static Set<String> get all => catalog.map((p) => p.name).toSet();

  static List<AppPermission> ofModule(String module) =>
      catalog.where((p) => p.module == module).toList();

  static AppPermission? byName(String name) {
    for (final permission in catalog) {
      if (permission.name == name) return permission;
    }
    return null;
  }
}
