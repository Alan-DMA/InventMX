// ============================================================================
// NEXUS MX v3.0 - CENTRO DE MANDO / HOME DASHBOARD
// Ley de Gobernanza: AGENTS.md - Clean Architecture & Comentarios Línea por Línea
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

// Núcleo de rutas y paleta de colores del sistema Nexus
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';

// Módulo de cuentas y almacenes operativos
import '../../account/presentation/account_provider.dart';

// Módulo de inventario y modal de alta rápida
import '../../inventory/presentation/inventory_provider.dart';
import '../../inventory/presentation/widgets/add_product_modal.dart';

// Módulo de administración y membresías
import '../../management/presentation/management_provider.dart';

// Dominio de ventas y formateador de moneda MXN
import '../../sales_pos/domain/sale_summary.dart';
import '../../saas_admin/presentation/saas_provider.dart' show clockProvider;
import '../../saas_admin/domain/subscription.dart' show mxn;

// Dominio del Dashboard
import '../domain/daily_snapshot.dart';
import '../domain/stock_alert.dart';
import '../domain/pending_purchase_alert.dart';
import '../domain/quick_action_item.dart';

// Catálogo WhatsApp / Pedidos web
import '../../whatsapp_catalog/presentation/store_orders_provider.dart';

// Proveedores del Dashboard y widgets de apoyo
import 'dashboard_provider.dart';
import 'quick_actions_preference.dart';
import 'widgets/app_drawer.dart';
import 'widgets/currency_selector.dart';
import 'widgets/customize_actions_modal.dart';
import 'widgets/quick_stock_adjust_sheet.dart';

/// Centro de mando (SR-02 / N-08) — Pantalla principal y landing del sistema.
///
/// Implementa un centro operativo en tiempo real conectado a PostgreSQL:
/// 1. Saludo dinámico con emoji según la franja horaria.
/// 2. Cuadrícula 2x2 de KPIs financieros y de inventario.
/// 3. Catálogo configurable de acciones rápidas (3 accesos directos persistidos).
/// 4. Monitor de pedidos web y alertas críticas de stock y compras pendientes.
class HomeDashboardScreen extends ConsumerWidget {
  const HomeDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Observa el snapshot diario con datos reales traídos de FastAPI / PostgreSQL
    final snapshot = ref.watch(dailySnapshotProvider);
    // Observa el contador de notificaciones no leídas para la campana de avisos
    final unread = ref.watch(unreadNotificationsProvider);

    return Scaffold(
      backgroundColor: AppColors.darkSlate,
      // Menú lateral deslizable (Drawer) con accesos a todo el ecosistema Nexus
      drawer: const AppDrawer(),
      appBar: AppBar(
        backgroundColor: AppColors.darkSlate,
        elevation: 0,
        // Botón hamburguesa que abre el AppDrawer
        leading: Builder(
          builder: (scaffoldContext) => IconButton(
            key: const Key('homeDrawerButton'),
            icon: const Icon(Icons.menu_rounded, color: AppColors.onSurface),
            onPressed: () => Scaffold.of(scaffoldContext).openDrawer(),
            tooltip: 'Menú principal',
          ),
        ),
        // Identificador de marca Nexus
        title: const Text(
          'Nexus',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppColors.onSurface,
            letterSpacing: 0.5,
          ),
        ),
        // Acciones superiores: Selector de divisa, campana y perfil de cuenta
        actions: [
          const CurrencySelector(),
          _NotificationsBell(unread: unread),
          IconButton(
            key: const Key('homeAccountButton'),
            onPressed: () => context.push(AppRoutes.account),
            icon: const Icon(Icons.account_circle_outlined,
                color: AppColors.onSurface),
            tooltip: 'Mi cuenta',
          ),
          const SizedBox(width: 4),
        ],
      ),
      // Soporte para refresco manual por gesto swipe-down
      body: RefreshIndicator(
        color: AppColors.emerald,
        backgroundColor: AppColors.surface,
        onRefresh: () => ref.read(dailySnapshotProvider.notifier).refresh(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            // Saludo personalizado con contexto temporal y almacén operativo
            const _GreetingHeader(),
            const SizedBox(height: 4),
            const _ContextLine(),
            const SizedBox(height: 20),

            // Encabezado de acciones rápidas con botón para personalizarlas
            Row(
              children: [
                const _SectionLabel('Acciones rápidas'),
                const Spacer(),
                TextButton.icon(
                  key: const Key('homeCustomizeActionsButton'),
                  onPressed: () => showCustomizeActionsModal(context),
                  icon: const Icon(Icons.tune_rounded,
                      size: 14, color: AppColors.emerald),
                  label: const Text(
                    'Personalizar',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.emerald,
                    ),
                  ),
                  style: TextButton.styleFrom(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // Fila con los 3 accesos directos configurados por el usuario
            const _QuickActions(),
            const SizedBox(height: 14),

            // Tarjeta de pedidos web recibidos desde el catálogo WhatsApp
            const _WebOrdersCard(),
            const SizedBox(height: 24),

            // Sección de alertas operativas (Stock bajo y Órdenes de compra)
            const _SectionLabel('Alertas'),
            const SizedBox(height: 10),
            snapshot.when(
              loading: () => const _SectionSkeleton(),
              error: (e, _) => _SectionError(e),
              data: (data) => _AlertsSection(snapshot: data),
            ),
            const SizedBox(height: 24),

            // Sección "Cómo va el día": Cuadrícula 2x2 de métricas y últimas ventas
            const _SectionLabel('Cómo va el día'),
            const SizedBox(height: 10),
            snapshot.when(
              loading: () => const _SectionSkeleton(),
              error: (e, _) => _SectionError(e),
              data: (data) => _DaySummary(snapshot: data),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Saludo dinámico y contexto (fecha · almacén operativo)
// ---------------------------------------------------------------------------

/// Extrae el primer nombre del usuario para un trato cercano y profesional.
String _firstName(String? fullName) {
  if (fullName == null || fullName.trim().isEmpty) return '';
  return fullName.trim().split(RegExp(r'\s+')).first;
}

/// Determina el saludo según la hora del día en el reloj del negocio.
String _greeting(DateTime now) {
  final h = now.hour;
  if (h < 12) return 'Buenos días';
  if (h < 19) return 'Buenas tardes';
  return 'Buenas noches';
}

/// Emoji contextual para acompañar el saludo según la posición del sol.
String _greetingEmoji(DateTime now) {
  final h = now.hour;
  if (h < 12) return '🌞';
  if (h < 19) return '🌤️';
  return '🌙';
}

const _weekdays = [
  'lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado', 'domingo',
];
const _months = [
  'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio',
  'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre',
];

/// Formatea la fecha de forma legible en español (ej. "Miércoles 16 de septiembre").
String _longDate(DateTime d) {
  final weekday = _weekdays[d.weekday - 1];
  final capitalized = weekday[0].toUpperCase() + weekday.substring(1);
  return '$capitalized ${d.day} de ${_months[d.month - 1]}';
}

/// Encabezado de saludo dinámico respetando pruebas preexistentes y estética visual.
class _GreetingHeader extends ConsumerWidget {
  const _GreetingHeader();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Obtiene la membresía activa y el reloj inyectado
    final member = ref.watch(currentMemberProvider).valueOrNull;
    final firstName = _firstName(member?.name);
    final now = ref.watch(clockProvider)();
    final greeting = _greeting(now);
    final emoji = _greetingEmoji(now);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Texto con Key exacta requerida por pruebas unitarias de Eduardo
        Flexible(
          child: Text(
            firstName.isEmpty ? greeting : '$greeting, $firstName',
            key: const Key('homeGreeting'),
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 21,
              fontWeight: FontWeight.w700,
              color: AppColors.onSurface,
            ),
          ),
        ),
        const SizedBox(width: 6),
        // Emoji dinámico posicionado al lado
        Text(
          emoji,
          style: const TextStyle(fontSize: 20),
        ),
      ],
    );
  }
}

/// Muestra la fecha del día y el almacén operativo donde está activo el empleado.
class _ContextLine extends ConsumerWidget {
  const _ContextLine();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(clockProvider)();
    final warehouse = ref.watch(operatingWarehouseProvider).valueOrNull;

    final text = warehouse == null
        ? _longDate(now)
        : '${_longDate(now)} · ${warehouse.name}';

    return Text(
      text,
      key: const Key('homeContextLine'),
      style: const TextStyle(fontSize: 13, color: AppColors.onSurfaceMuted),
    );
  }
}

// ---------------------------------------------------------------------------
// Campana de notificaciones con insignia de no leídos
// ---------------------------------------------------------------------------

class _NotificationsBell extends StatelessWidget {
  const _NotificationsBell({required this.unread});

  final int unread;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        IconButton(
          key: const Key('homeNotificationsButton'),
          onPressed: () => context.push(AppRoutes.notifications),
          icon: const Icon(Icons.notifications_none_rounded,
              color: AppColors.onSurface),
          tooltip: 'Avisos',
        ),
        if (unread > 0)
          Positioned(
            top: 8,
            right: 6,
            child: Container(
              key: const Key('homeNotificationsBadge'),
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              constraints: const BoxConstraints(minWidth: 17),
              decoration: BoxDecoration(
                color: AppColors.error,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                unread > 9 ? '9+' : '$unread',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Acciones rápidas personalizables
// ---------------------------------------------------------------------------

class _QuickActions extends ConsumerWidget {
  const _QuickActions();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Lee la lista de accesos rápidos activos elegidos por el usuario
    final activeActionIds = ref.watch(quickActionsProvider);

    return Row(
      children: [
        for (int i = 0; i < activeActionIds.length; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          Expanded(
            child: _buildActionItem(context, activeActionIds[i]),
          ),
        ],
      ],
    );
  }

  /// Construye cada botón de acción rápida mapeando su identificador, clave y ruta
  Widget _buildActionItem(BuildContext context, QuickActionId id) {
    final def = QuickActionDefinition.fromId(id);
    Key itemKey;
    String label;
    VoidCallback onTap;

    switch (id) {
      case QuickActionId.sell:
        itemKey = const Key('homeActionSell');
        label = 'Vender';
        onTap = () => context.go(AppRoutes.sales);
        break;
      case QuickActionId.addProduct:
        itemKey = const Key('homeActionAddProduct');
        label = 'Agregar\nproducto';
        onTap = () => showAddProductModal(context);
        break;
      case QuickActionId.adjustStock:
        itemKey = const Key('homeActionAdjustStock');
        label = 'Ajustar\nstock';
        onTap = () => showQuickStockAdjustSheet(context);
        break;
      case QuickActionId.newPurchase:
        itemKey = const Key('homeActionNewPurchase');
        label = 'Nueva\ncompra';
        onTap = () => context.push(AppRoutes.purchaseCreate);
        break;
      case QuickActionId.gondola:
        itemKey = const Key('homeActionGondola');
        label = 'Modo\ngóndola';
        onTap = () => context.push(AppRoutes.gondola);
        break;
      case QuickActionId.webCatalog:
        itemKey = const Key('homeActionWebCatalog');
        label = 'Vitrina\nweb';
        onTap = () => context.push(AppRoutes.storeOrders);
        break;
      case QuickActionId.importExcel:
        itemKey = const Key('homeActionImportExcel');
        label = 'Importar\nExcel';
        onTap = () => context.push(AppRoutes.import);
        break;
      case QuickActionId.purchasesHub:
        itemKey = const Key('homeActionPurchasesHub');
        label = 'Ver\ncompras';
        onTap = () => context.go(AppRoutes.purchases);
        break;
    }

    return _ActionCard(
      itemKey: itemKey,
      icon: def.icon,
      label: label,
      accentColor: def.accentColor,
      onTap: onTap,
    );
  }
}

/// Tarjeta individual para una acción rápida
class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.itemKey,
    required this.icon,
    required this.label,
    required this.onTap,
    this.accentColor = AppColors.emerald,
  });

  final Key itemKey;
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        key: itemKey,
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          height: 96,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: accentColor, size: 24),
              const SizedBox(height: 8),
              Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12.5,
                  height: 1.2,
                  fontWeight: FontWeight.w600,
                  color: AppColors.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Alertas operativas (Stock bajo + Órdenes de compra por recibir)
// ---------------------------------------------------------------------------

class _AlertsSection extends ConsumerWidget {
  const _AlertsSection({required this.snapshot});

  final DailySnapshot snapshot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasStockAlerts = snapshot.stockAlertCount > 0;
    final hasPendingPurchases = snapshot.pendingPurchaseAlerts.isNotEmpty;

    // Si no hay alertas de ningún tipo, muestra el estado tranquilo
    if (!hasStockAlerts && !hasPendingPurchases) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: const Row(
          children: [
            Icon(Icons.check_circle_outline_rounded,
                color: AppColors.emerald, size: 20),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Todo en orden — sin productos por acabarse',
                style: TextStyle(fontSize: 13, color: AppColors.onSurface),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          // Alertas de existencias de inventario
          if (hasStockAlerts) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 8, 8),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded,
                      color: AppColors.warning, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${snapshot.stockAlertCount} producto${snapshot.stockAlertCount == 1 ? '' : 's'} necesitan atención',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.onSurface,
                      ),
                    ),
                  ),
                  TextButton(
                    key: const Key('homeAlertsSeeAll'),
                    onPressed: () {
                      ref.read(inventoryProvider.notifier).setLowStock(true);
                      context.go(AppRoutes.inventory);
                    },
                    child: const Text('Ver todas'),
                  ),
                ],
              ),
            ),
            for (final alert in snapshot.lowStockAlerts)
              _AlertRow(alert: alert),
          ],

          // Alertas de órdenes de compra pendientes
          if (hasPendingPurchases) ...[
            if (hasStockAlerts)
              const Divider(height: 1, color: AppColors.border),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 8, 8),
              child: Row(
                children: [
                  const Icon(Icons.local_shipping_outlined,
                      color: AppColors.skyBlue, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${snapshot.pendingPurchaseAlerts.length} orden${snapshot.pendingPurchaseAlerts.length == 1 ? '' : 'es'} de compra por recibir',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.onSurface,
                      ),
                    ),
                  ),
                  TextButton(
                    key: const Key('homePurchaseAlertsSeeAll'),
                    onPressed: () => context.go(AppRoutes.purchases),
                    child: const Text('Ver compras'),
                  ),
                ],
              ),
            ),
            for (final po in snapshot.pendingPurchaseAlerts)
              _PendingPurchaseAlertRow(alert: po),
          ],
        ],
      ),
    );
  }
}

/// Fila para alerta de producto agotado o con stock bajo
class _AlertRow extends StatelessWidget {
  const _AlertRow({required this.alert});

  final StockAlertItem alert;

  @override
  Widget build(BuildContext context) {
    final tint = alert.isOutOfStock ? AppColors.error : AppColors.warning;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: Key('homeAlertRow-${alert.productId}'),
        onTap: () => context.go(AppRoutes.productDetailPath(alert.productId)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              Icon(
                alert.isOutOfStock
                    ? Icons.remove_shopping_cart_outlined
                    : Icons.inventory_2_outlined,
                size: 16,
                color: tint,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  alert.productName,
                  style: const TextStyle(
                      fontSize: 13.5, color: AppColors.onSurface),
                ),
              ),
              Text(
                alert.isOutOfStock
                    ? 'Agotado'
                    : 'Quedan ${alert.availableStock}',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: tint,
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right_rounded,
                  size: 18, color: AppColors.onSurfaceMuted),
            ],
          ),
        ),
      ),
    );
  }
}

/// Fila para alerta de orden de compra pendiente
class _PendingPurchaseAlertRow extends StatelessWidget {
  const _PendingPurchaseAlertRow({required this.alert});

  final PendingPurchaseAlert alert;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: Key('homeAlertRow-po-${alert.id}'),
        onTap: () => context.go(AppRoutes.purchases),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              const Icon(
                Icons.schedule_rounded,
                size: 16,
                color: AppColors.skyBlue,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${alert.supplierName} · ${alert.folio}',
                      style: const TextStyle(
                          fontSize: 13.5, color: AppColors.onSurface),
                    ),
                    Text(
                      '${alert.daysPending} d pendientes · ${alert.isOverdue ? 'Vencida' : 'En espera'}',
                      style: const TextStyle(
                          fontSize: 11.5, color: AppColors.onSurfaceMuted),
                    ),
                  ],
                ),
              ),
              Text(
                mxn(alert.totalMxn),
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.onSurface,
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right_rounded,
                  size: 18, color: AppColors.onSurfaceMuted),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Resumen del día: Cuadrícula 2x2 de métricas financieras y últimas ventas
// ---------------------------------------------------------------------------

class _DaySummary extends StatelessWidget {
  const _DaySummary({required this.snapshot});

  final DailySnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final delta = snapshot.salesDeltaPercent;

    return Column(
      children: [
        // Cuadrícula 2x2 con diseño responsivo alineado a la imagen referencial
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _SalesCard(snapshot: snapshot, delta: delta),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _MarginCard(snapshot: snapshot),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _MetricCard(
                itemKey: const Key('homePayables'),
                icon: Icons.receipt_long_outlined,
                tint: snapshot.payablesOverdueCount > 0
                    ? AppColors.error
                    : AppColors.onSurface,
                value: mxn(snapshot.payablesDueMxn),
                label: snapshot.payablesOverdueCount > 0
                    ? '${snapshot.payablesOverdueCount} cuenta vencida'
                    : 'por pagar a proveedores',
                onTap: () => context.go(AppRoutes.purchases),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _CashCard(snapshot: snapshot),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Kardex condensado de últimas transacciones
        const _RecentSalesSection(),
      ],
    );
  }
}

/// Tarjeta 1 del Grid 2x2: Ventas del día con comparación porcentual
class _SalesCard extends StatelessWidget {
  const _SalesCard({required this.snapshot, required this.delta});

  final DailySnapshot snapshot;
  final double? delta;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        key: const Key('homeSalesCard'),
        onTap: () => context.push(AppRoutes.reports),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Expanded(
                    child: Text(
                      'Vendido hoy',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.onSurfaceMuted),
                    ),
                  ),
                  if (delta != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: (delta! >= 0
                                ? AppColors.emerald
                                : AppColors.error)
                            .withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            delta! >= 0
                                ? Icons.trending_up_rounded
                                : Icons.trending_down_rounded,
                            size: 13,
                            color: delta! >= 0
                                ? AppColors.emerald
                                : AppColors.error,
                          ),
                          const SizedBox(width: 2),
                          Text(
                            '${delta! >= 0 ? '+' : ''}${delta!.toStringAsFixed(0)}%',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: delta! >= 0
                                  ? AppColors.emerald
                                  : AppColors.error,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                mxn(snapshot.salesTodayMxn),
                key: const Key('homeSalesTodayAmount'),
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: AppColors.onSurface,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                '${snapshot.salesTodayCount} ventas',
                style: const TextStyle(
                    fontSize: 11.5, color: AppColors.onSurfaceMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tarjeta 2 del Grid 2x2: Margen bruto de ganancia y porcentaje
class _MarginCard extends StatelessWidget {
  const _MarginCard({required this.snapshot});

  final DailySnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final marginPercent = snapshot.marginTodayPercent;

    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        key: const Key('homeMarginCard'),
        onTap: () => context.push(AppRoutes.reports),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      'Margen de hoy',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.onSurfaceMuted),
                    ),
                  ),
                  SizedBox(width: 4),
                  Icon(Icons.percent_rounded,
                      size: 14, color: AppColors.onSurfaceMuted),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '${mxn(snapshot.marginTodayMxn)}'
                '${marginPercent != null ? ' (${marginPercent.toStringAsFixed(0)}%)' : ''}',
                key: const Key('homeMarginToday'),
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 16.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.emerald,
                ),
              ),
              const SizedBox(height: 3),
              const Text(
                'Ganancia bruta',
                style: TextStyle(
                    fontSize: 11.5, color: AppColors.onSurfaceMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tarjeta 3 del Grid 2x2: Cuentas por pagar a proveedores
class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.itemKey,
    required this.icon,
    required this.tint,
    required this.value,
    required this.label,
    required this.onTap,
  });

  final Key itemKey;
  final IconData icon;
  final Color tint;
  final String value;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        key: itemKey,
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 16, color: tint),
                  const Spacer(),
                  const Icon(Icons.chevron_right_rounded,
                      size: 16, color: AppColors.onSurfaceMuted),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                value,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: tint,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 11.5, color: AppColors.onSurfaceMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tarjeta 4 del Grid 2x2: Estado de la caja registradora y efectivo esperado
class _CashCard extends StatelessWidget {
  const _CashCard({required this.snapshot});

  final DailySnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final open = snapshot.isCashSessionOpen;

    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        key: const Key('homeCashCard'),
        onTap: () => context.go(AppRoutes.cash),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    open ? Icons.lock_open_rounded : Icons.lock_outline_rounded,
                    size: 16,
                    color: open ? AppColors.emerald : AppColors.onSurfaceMuted,
                  ),
                  const Spacer(),
                  const Icon(Icons.chevron_right_rounded,
                      size: 16, color: AppColors.onSurfaceMuted),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                open ? 'Turno abierto' : 'Sin turno',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.onSurface,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                open
                    ? 'Esperado: ${mxn(snapshot.cashExpectedMxn)}'
                    : 'Abrir turno antes de cobrar',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 11.5, color: AppColors.onSurfaceMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Últimas ventas del día
// ---------------------------------------------------------------------------

class _RecentSalesSection extends ConsumerWidget {
  const _RecentSalesSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sales = ref.watch(recentSalesProvider);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 8, 4),
            child: Row(
              children: [
                const Text(
                  'Últimas ventas',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.onSurface,
                  ),
                ),
                const Spacer(),
                TextButton(
                  key: const Key('homeSalesSeeAll'),
                  onPressed: () => context.push(AppRoutes.salesHistory),
                  child: const Text('Ver todo'),
                ),
              ],
            ),
          ),
          sales.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppColors.emerald),
                ),
              ),
            ),
            error: (e, _) => Padding(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
              child: Text(
                e.toString().replaceFirst('Exception: ', ''),
                style: const TextStyle(
                    fontSize: 12, color: AppColors.onSurfaceMuted),
              ),
            ),
            data: (items) => items.isEmpty
                ? const Padding(
                    padding: EdgeInsets.fromLTRB(14, 4, 14, 14),
                    child: Text(
                      'Sin ventas todavía hoy',
                      style: TextStyle(
                          fontSize: 12.5, color: AppColors.onSurfaceMuted),
                    ),
                  )
                : Column(
                    children: [
                      for (final sale in items) _RecentSaleRow(sale: sale),
                      const SizedBox(height: 4),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _RecentSaleRow extends StatelessWidget {
  const _RecentSaleRow({required this.sale});

  final SaleSummary sale;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: Key('homeRecentSale-${sale.id}'),
        onTap: () => context.push(AppRoutes.salesHistory),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            children: [
              Icon(sale.paymentKind.icon,
                  size: 15, color: sale.paymentKind.color),
              const SizedBox(width: 10),
              Text(
                _formatTime(sale.completedAt),
                style: const TextStyle(
                    fontSize: 12.5, color: AppColors.onSurfaceMuted),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  sale.folio,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 12.5, color: AppColors.onSurfaceMuted),
                ),
              ),
              if (sale.isRefunded)
                const Padding(
                  padding: EdgeInsets.only(right: 6),
                  child: Text(
                    'Reembolsada',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.onSurfaceMuted,
                    ),
                  ),
                ),
              Text(
                mxn(sale.totalMxn),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTime(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

// ---------------------------------------------------------------------------
// Tarjeta de Pedidos Web del Catálogo WhatsApp
// ---------------------------------------------------------------------------

class _WebOrdersCard extends ConsumerWidget {
  const _WebOrdersCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final newCount = ref.watch(newOrdersCountProvider);
    final activeCount = ref.watch(activeOrdersCountProvider);
    final hasNew = newCount > 0;

    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        key: const Key('homeWebOrdersCard'),
        onTap: () => context.push(AppRoutes.storeOrders),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: hasNew
                  ? AppColors.skyBlue.withValues(alpha: 0.55)
                  : AppColors.border,
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.shopping_bag_outlined,
                size: 20,
                color: hasNew ? AppColors.skyBlue : AppColors.onSurfaceMuted,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hasNew
                          ? 'Pedidos web · $newCount nuevo${newCount == 1 ? '' : 's'}'
                          : 'Pedidos web',
                      key: const Key('homeWebOrdersTitle'),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      activeCount == 0
                          ? 'Nada pendiente de tu catálogo'
                          : '$activeCount por atender',
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.onSurfaceMuted),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded,
                  color: AppColors.onSurfaceMuted),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Utilidades de etiqueta y estado
// ---------------------------------------------------------------------------

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          color: AppColors.onSurfaceMuted,
        ),
      );
}

class _SectionSkeleton extends StatelessWidget {
  const _SectionSkeleton();

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(
            child: CircularProgressIndicator(color: AppColors.emerald)),
      );
}

class _SectionError extends StatelessWidget {
  const _SectionError(this.error);
  final Object error;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text(
          error.toString().replaceFirst('Exception: ', ''),
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.onSurfaceMuted),
        ),
      );
}
