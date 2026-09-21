import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../inventory/data/inventory_repository.dart';
import '../../inventory/domain/product.dart';
import '../../purchases/presentation/widgets/phone_launcher.dart';
import '../../sales_pos/presentation/cart_provider.dart';
import '../data/whatsapp_message_formatter.dart';
import '../domain/store_order.dart';
import '../domain/whatsapp_order.dart';
import 'catalog_theme.dart' show mxn;
import 'store_orders_provider.dart';
import 'store_orders_screen.dart' show StoreOrdersScreen;
import 'whatsapp_catalog_provider.dart' show catalogSettingsProvider;
import 'widgets/cancel_reason_sheet.dart';
import 'widgets/order_edit_sheet.dart';
import 'widgets/order_status_chip.dart';

/// Existencia actual de cada renglón — lo que evita el "te lo confirmo… ah,
/// no hay". Se pide por producto; un pedido tiene pocos renglones.
final _lineStockProvider =
    FutureProvider.autoDispose.family<Product?, String>((ref, productId) async {
  try {
    return await ref.read(inventoryRepositoryProvider).getProductById(productId);
  } catch (_) {
    return null;
  }
});

/// Detalle de un pedido web: qué pidió, existencias, quién lo vio, y las
/// acciones de un toque (Listo · Entregado · Cobrar en caja · Editar ·
/// Cancelar · Reabrir · Escribirle).
class StoreOrderDetailScreen extends ConsumerStatefulWidget {
  const StoreOrderDetailScreen({super.key, required this.folio});

  final String folio;

  @override
  ConsumerState<StoreOrderDetailScreen> createState() =>
      _StoreOrderDetailScreenState();
}

class _StoreOrderDetailScreenState
    extends ConsumerState<StoreOrderDetailScreen> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(storeOrderDetailProvider(widget.folio));
    return Scaffold(
      backgroundColor: AppColors.darkSlate,
      appBar: AppBar(
        backgroundColor: AppColors.darkSlate,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              size: 20, color: AppColors.onSurface),
          onPressed: () => context.canPop()
              ? context.pop()
              : context.go(AppRoutes.storeOrders),
        ),
        title: Text(
          widget.folio,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: AppColors.onSurface,
            letterSpacing: 0.3,
          ),
        ),
        actions: [
          if (async.valueOrNull?.order.draft.customerPhone != null)
            IconButton(
              key: const Key('orderChatButton'),
              tooltip: 'Escribirle por WhatsApp',
              icon: const Icon(Icons.chat_rounded, color: AppColors.emerald),
              onPressed: () =>
                  _openChat(async.valueOrNull!.order.draft.customerPhone!),
            ),
        ],
      ),
      body: async.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.emerald)),
        error: (e, _) => _ErrorBody(
          message: e is OrderNotFound
              ? 'Este pedido no existe o ya no está en tu comercio.'
              : 'No pudimos cargar el pedido. Revisa tu conexión.',
          onRetry: () =>
              ref.invalidate(storeOrderDetailProvider(widget.folio)),
        ),
        data: (order) => _Body(
          order: order,
          busy: _busy,
          onStatus: (status, {reason}) => _setStatus(order, status, reason),
          onEdit: () => _edit(order),
          onCharge: () => _charge(order),
          onChat: _openChat,
          onNotify: () => _notifyCustomer(order),
        ),
      ),
    );
  }

  // ── Acciones ──────────────────────────────────────────────────────────────

  Future<void> _setStatus(
    StoreOrder order,
    OrderStatus status,
    CancelReason? reason,
  ) async {
    if (status == OrderStatus.cancelled && reason == null) {
      final picked = await showCancelReasonSheet(context);
      if (picked == null) return;
      reason = picked;
    }
    await _run(() => ref.read(storeOrdersProvider.notifier).setStatus(
          order.folio,
          status,
          cancelReason: reason,
          expectedUpdatedAt: order.order.updatedAt,
        ));
  }

  /// "Avisar al cliente": abre su chat con el mensaje listo — el cliente no
  /// tiene la página del ticket abierta, así que la app no puede avisarle;
  /// su canal es el chat y el tendero es quien manda.
  Future<void> _notifyCustomer(StoreOrder order) async {
    final phone = order.order.draft.customerPhone;
    if (phone == null) return;
    final storeName =
        ref.read(catalogSettingsProvider).valueOrNull?.storeName ?? 'la tienda';
    final text = WhatsAppMessageFormatter.readyText(
      order: order.order,
      storeName: storeName,
    );
    final messenger = ScaffoldMessenger.of(context);
    final ok = await ref.read(urlLauncherProvider)(
      WhatsAppMessageFormatter.waLinkFor(phone, text),
      mode: LaunchMode.externalApplication,
    );
    if (!ok) {
      messenger.showSnackBar(const SnackBar(
          content: Text('No se pudo abrir WhatsApp en este equipo.')));
    }
  }

  Future<void> _edit(StoreOrder order) async {
    final edit = await showOrderEditSheet(context, order: order);
    if (edit == null) return;
    await _run(
        () => ref.read(storeOrdersProvider.notifier).edit(order.folio, edit));
  }

  /// "Cobrar en caja": el POS abre con el carrito exacto del pedido; al
  /// terminar el cobro, `CartNotifier` liga la venta y marca Entregado.
  void _charge(StoreOrder order) {
    ref.read(cartProvider.notifier).loadFromStoreOrder(order);
    context.go(AppRoutes.sales);
  }

  Future<void> _openChat(String phone) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await ref.read(urlLauncherProvider)(
      whatsAppUri(phone),
      mode: LaunchMode.externalApplication,
    );
    if (!ok) {
      messenger.showSnackBar(const SnackBar(
          content: Text('No se pudo abrir WhatsApp en este equipo.')));
    }
  }

  Future<StoreOrder?> _run(Future<StoreOrder> Function() action) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      return await action();
    } on OrderConflict catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } on OrderActionRejected catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text(e.message),
        backgroundColor: AppColors.error,
      ));
    } catch (_) {
      messenger.showSnackBar(const SnackBar(
        content: Text('Sin conexión — el cambio no se guardó. Inténtalo de nuevo.'),
        backgroundColor: AppColors.error,
      ));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    return null;
  }
}

// ---------------------------------------------------------------------------
// Cuerpo
// ---------------------------------------------------------------------------

typedef _StatusAction = Future<void> Function(OrderStatus status,
    {CancelReason? reason});

class _Body extends ConsumerWidget {
  const _Body({
    required this.order,
    required this.busy,
    required this.onStatus,
    required this.onEdit,
    required this.onCharge,
    required this.onChat,
    required this.onNotify,
  });

  final StoreOrder order;
  final bool busy;
  final _StatusAction onStatus;
  final VoidCallback onEdit;
  final VoidCallback onCharge;
  final ValueChanged<String> onChat;
  final VoidCallback onNotify;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final saved = order.order;
    final draft = saved.draft;
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              _HeaderCard(order: order),
              const SizedBox(height: 12),
              _Section(
                title: 'Cliente',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _kv('Nombre', draft.customerName),
                    if (draft.customerPhone != null)
                      _kv('Teléfono', draft.customerPhone!,
                          trailing: TextButton.icon(
                            key: const Key('orderChatLink'),
                            onPressed: () => onChat(draft.customerPhone!),
                            icon: const Icon(Icons.chat_rounded, size: 16),
                            label: const Text('Escribirle'),
                          ))
                    else
                      _kv('Teléfono', 'No lo dejó — respóndele en el chat',
                          muted: true),
                    _kv(
                      'Entrega',
                      draft.deliveryMethod == DeliveryMethod.delivery
                          ? 'A domicilio'
                          : 'Recoger en tienda',
                    ),
                    if (draft.deliveryMethod == DeliveryMethod.delivery)
                      _kv('Dirección', draft.deliveryAddress ?? '—'),
                    _kv('Pago', _paymentLabel(draft)),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _Section(
                title: 'Pedido · ${saved.itemCount} pzas',
                child: Column(
                  children: [
                    for (final line in draft.lines) _LineRow(line: line),
                    const Divider(color: AppColors.border, height: 18),
                    _amount('Subtotal', saved.totals.subtotalMxn),
                    if (draft.deliveryMethod == DeliveryMethod.delivery)
                      _amount('Envío', saved.totals.deliveryFeeMxn),
                    _amount('Total', saved.totals.totalMxn, strong: true),
                    if (draft.cashTenderedMxn != null) ...[
                      _amount('Paga con', draft.cashTenderedMxn!),
                      if (saved.totals.changeMxn != null)
                        _amount('Cambio', saved.totals.changeMxn!),
                    ],
                  ],
                ),
              ),
              if ((draft.orderNotes ?? '').trim().isNotEmpty) ...[
                const SizedBox(height: 12),
                _Section(
                  title: 'Observaciones',
                  child: Text(
                    draft.orderNotes!.trim(),
                    style: const TextStyle(
                        fontSize: 14, height: 1.4, color: AppColors.onSurface),
                  ),
                ),
              ],
              if (order.revisions.isNotEmpty) ...[
                const SizedBox(height: 12),
                _RevisionsSection(order: order),
              ],
            ],
          ),
        ),
        _ActionBar(
          order: order,
          busy: busy,
          onStatus: onStatus,
          onEdit: onEdit,
          onCharge: onCharge,
          onNotify: onNotify,
        ),
      ],
    );
  }

  static String _paymentLabel(WhatsAppOrderDraft draft) =>
      switch (draft.paymentMethod) {
        PaymentMethodPreview.cash => 'Efectivo',
        PaymentMethodPreview.transfer => 'Transferencia / SPEI',
        PaymentMethodPreview.cardOnDelivery => 'Tarjeta al recibir',
      };

  static Widget _kv(String label, String value,
          {Widget? trailing, bool muted = false}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: 82,
              child: Text(label,
                  style: const TextStyle(
                      fontSize: 12.5, color: AppColors.onSurfaceMuted)),
            ),
            Expanded(
              child: Text(
                value,
                style: TextStyle(
                  fontSize: 14,
                  color: muted ? AppColors.onSurfaceMuted : AppColors.onSurface,
                  fontStyle: muted ? FontStyle.italic : null,
                ),
              ),
            ),
            if (trailing != null) trailing,
          ],
        ),
      );

  static Widget _amount(String label, double value, {bool strong = false}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Expanded(
              child: Text(label,
                  style: TextStyle(
                    fontSize: strong ? 15 : 13,
                    fontWeight: strong ? FontWeight.w700 : FontWeight.w400,
                    color: strong ? AppColors.onSurface : AppColors.onSurfaceMuted,
                  )),
            ),
            Text(
              mxn(value),
              style: TextStyle(
                fontSize: strong ? 17 : 13.5,
                fontWeight: strong ? FontWeight.w800 : FontWeight.w600,
                color: strong ? AppColors.emerald : AppColors.onSurface,
              ),
            ),
          ],
        ),
      );
}

/// Estado, cuánto lleva, quién lo vio/atendió, venta ligada y duplicado.
class _HeaderCard extends StatelessWidget {
  const _HeaderCard({required this.order});

  final StoreOrder order;

  @override
  Widget build(BuildContext context) {
    final saved = order.order;
    final lines = <String>[
      'Recibido ${timeAgo(saved.issuedAt)} · ${hourMinute(saved.issuedAt)}',
      if (order.seenByName != null) 'Lo vio ${order.seenByName}',
      if (order.attendedByName != null &&
          order.attendedByName != order.seenByName)
        'Lo atiende ${order.attendedByName}',
      if (saved.storeEditedAt != null)
        'Editado por ${order.editedByName ?? 'la tienda'} · ${hourMinute(saved.storeEditedAt!)}',
      if (saved.status == OrderStatus.cancelled && saved.cancelReason != null)
        'Motivo: ${saved.cancelReason!.label}',
    ];
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              OrderStatusChip(status: saved.status),
              const SizedBox(width: 8),
              if (order.saleId != null)
                Expanded(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      key: const Key('orderSaleLink'),
                      onPressed: () => context
                          .push(AppRoutes.saleDetailPath(order.saleId!)),
                      icon: const Icon(Icons.receipt_long_rounded, size: 16),
                      label: const Text('Cobrado en caja',
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          for (final l in lines)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(l,
                  style: const TextStyle(
                      fontSize: 12.5, color: AppColors.onSurfaceMuted)),
            ),
          if (saved.status.isClosed) ...[
            // Cerrado: ya no está en Activos. Decir a dónde fue evita el
            // "¿y ahora dónde está?" (observación de Eduardo en QA, 20 sep).
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.history_rounded,
                    size: 15, color: AppColors.onSurfaceMuted),
                const SizedBox(width: 6),
                const Expanded(
                  child: Text(
                    'Este pedido está en Historial',
                    key: Key('orderInHistoryNote'),
                    style: TextStyle(
                        fontSize: 12.5, color: AppColors.onSurfaceMuted),
                  ),
                ),
                Consumer(
                  builder: (context, ref, _) => TextButton(
                    key: const Key('orderGoHistory'),
                    onPressed: () {
                      ref.read(storeOrdersTabRequestProvider.notifier).state = 1;
                      context.go(StoreOrdersScreen.historyLocation);
                    },
                    child: const Text('Ver'),
                  ),
                ),
              ],
            ),
          ],
          if (order.possibleDuplicateOf != null) ...[
            const SizedBox(height: 10),
            InkWell(
              key: const Key('duplicateLink'),
              onTap: () => context.push(
                  AppRoutes.storeOrderPath(order.possibleDuplicateOf!)),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.content_copy_rounded,
                        size: 15, color: AppColors.warning),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Parece repetido: mismo cliente y mismos productos que '
                        '${order.possibleDuplicateOf} minutos antes. Revisa antes de preparar los dos.',
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.warning, height: 1.3),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title.toUpperCase(),
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: AppColors.onSurfaceMuted.withValues(alpha: 0.8),
              ),
            ),
            const SizedBox(height: 8),
            child,
          ],
        ),
      );
}

/// Renglón con la existencia actual al lado ("quedan 2", "agotado").
class _LineRow extends ConsumerWidget {
  const _LineRow({required this.line});

  final CartLine line;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stock = ref.watch(_lineStockProvider(line.product.id)).valueOrNull;
    final available = stock?.availableStock;
    final short = available != null && available < line.quantity;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            padding: const EdgeInsets.symmetric(vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '${line.quantity}×',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.onSurface),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(line.product.name,
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.onSurface)),
                Text(
                  '${mxn(line.product.priceMxn)} c/u'
                  '${line.notes != null ? ' · ${line.notes}' : ''}',
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.onSurfaceMuted),
                ),
                if (available != null)
                  Text(
                    available <= 0
                        ? 'Agotado'
                        : short
                            ? 'Sólo quedan $available'
                            : 'Quedan $available',
                    key: Key('lineStock-${line.product.id}'),
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: available <= 0 || short
                          ? AppColors.warning
                          : AppColors.emerald,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            mxn(line.subtotalMxn),
            style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.onSurface),
          ),
        ],
      ),
    );
  }
}

/// "Versiones anteriores" — para cuando el cliente dice "yo pedí 3".
class _RevisionsSection extends StatelessWidget {
  const _RevisionsSection({required this.order});

  final StoreOrder order;

  @override
  Widget build(BuildContext context) {
    final revisions = order.revisions.reversed.toList();
    // Material propio: ExpansionTile pinta su tinta sobre el Material más
    // cercano, y un Container con color lo taparía.
    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          key: const Key('orderRevisions'),
          tilePadding: const EdgeInsets.symmetric(horizontal: 14),
          iconColor: AppColors.onSurfaceMuted,
          collapsedIconColor: AppColors.onSurfaceMuted,
          title: Text(
            'Versiones anteriores (${revisions.length})',
            style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: AppColors.onSurface),
          ),
          subtitle: const Text(
            'Lo que pidió el cliente antes de cada cambio',
            style: TextStyle(fontSize: 12, color: AppColors.onSurfaceMuted),
          ),
          children: [
            for (final r in revisions)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Hasta las ${hourMinute(r.at)}'
                      '${r.byName != null ? ' · cambió ${r.byName}' : ''}',
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.onSurfaceMuted),
                    ),
                    const SizedBox(height: 4),
                    for (final l in r.lines)
                      Text(
                        '${l.quantity}× ${l.product.name} — ${mxn(l.subtotalMxn)}',
                        style: const TextStyle(
                            fontSize: 13, color: AppColors.onSurface),
                      ),
                    Text(
                      '${r.deliveryMethod == DeliveryMethod.delivery ? 'A domicilio' : 'Recoger'} · Total ${mxn(r.totalMxn)}',
                      style: const TextStyle(
                          fontSize: 12.5, color: AppColors.onSurfaceMuted),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Acciones de un toque según el estado. Primaria grande; secundarias en fila.
///
/// Nuevo  → **Listo** (primaria) · Cobrar en caja · Editar · Cancelar
/// Listo  → **Cobrar en caja** (primaria) · Avisar al cliente · Editar · Cancelar
/// Cerrado → Reabrir (si no tiene venta ligada)
///
/// Entregar es vender (decisión de Eduardo, QA 20 sep): no hay "entregado sin
/// cobrar" — la única salida de un pedido Listo es el POS, que descuenta el
/// inventario y liga la venta. El backend lo exige (422 sin `sale_id`).
class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.order,
    required this.busy,
    required this.onStatus,
    required this.onEdit,
    required this.onCharge,
    required this.onNotify,
  });

  final StoreOrder order;
  final bool busy;
  final _StatusAction onStatus;
  final VoidCallback onEdit;
  final VoidCallback onCharge;
  final VoidCallback onNotify;

  @override
  Widget build(BuildContext context) {
    final status = order.status;
    final delivery = order.order.draft.deliveryMethod == DeliveryMethod.delivery;
    final hasPhone = order.order.draft.customerPhone != null;

    final Widget primary = switch (status) {
      OrderStatus.newOrder => _primary(
          key: 'orderMarkReady',
          icon: Icons.check_circle_outline_rounded,
          label: delivery ? 'Listo, sale a entrega' : 'Listo para recoger',
          onPressed: () => onStatus(OrderStatus.ready),
        ),
      OrderStatus.ready => _primary(
          key: 'orderCharge',
          icon: Icons.point_of_sale_rounded,
          label: 'Cobrar en caja',
          onPressed: onCharge,
        ),
      OrderStatus.delivered || OrderStatus.cancelled => order.canReopen
          ? _primary(
              key: 'orderReopen',
              icon: Icons.replay_rounded,
              label: 'Reabrir pedido',
              outlined: true,
              onPressed: () => onStatus(OrderStatus.newOrder),
            )
          : const SizedBox.shrink(),
    };

    final secondary = <Widget>[
      if (status == OrderStatus.newOrder && order.canCharge)
        _secondary(
          key: 'orderChargeSecondary',
          icon: Icons.point_of_sale_rounded,
          label: 'Cobrar en caja',
          color: AppColors.emerald,
          onPressed: busy ? null : onCharge,
        ),
      if (status == OrderStatus.ready && hasPhone)
        _secondary(
          key: 'orderNotifyCustomer',
          icon: Icons.notifications_active_outlined,
          label: 'Avisar al cliente',
          color: AppColors.skyBlue,
          onPressed: busy ? null : onNotify,
        ),
      _secondary(
        key: 'orderEdit',
        icon: Icons.edit_outlined,
        label: 'Editar',
        onPressed: busy ? null : onEdit,
      ),
      _secondary(
        key: 'orderCancel',
        icon: Icons.cancel_outlined,
        label: 'Cancelar',
        color: AppColors.error,
        onPressed: busy ? null : () => onStatus(OrderStatus.cancelled),
      ),
    ];

    return Container(
      padding: EdgeInsets.fromLTRB(
          16, 10, 16, MediaQuery.of(context).padding.bottom + 12),
      decoration: const BoxDecoration(
        color: AppColors.darkSlate,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (status.isActive)
            Row(
              children: [
                for (var i = 0; i < secondary.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  Expanded(child: secondary[i]),
                ],
              ],
            ),
          if (status.isActive) const SizedBox(height: 8),
          SizedBox(width: double.infinity, height: 50, child: primary),
          if (status == OrderStatus.ready)
            TextButton(
              key: const Key('orderBackToNew'),
              onPressed: busy ? null : () => onStatus(OrderStatus.newOrder),
              child: const Text('Regresar a Nuevo',
                  style: TextStyle(color: AppColors.onSurfaceMuted)),
            ),
        ],
      ),
    );
  }

  Widget _primary({
    required String key,
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    bool outlined = false,
  }) {
    final child = busy
        ? const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2))
        : Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 20),
              const SizedBox(width: 8),
              Flexible(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700)),
              ),
            ],
          );
    return outlined
        ? OutlinedButton(
            key: Key(key),
            onPressed: busy ? null : onPressed,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.onSurface,
              side: const BorderSide(color: AppColors.border),
            ),
            child: child,
          )
        : ElevatedButton(
            key: Key(key),
            onPressed: busy ? null : onPressed,
            child: child,
          );
  }

  static Widget _secondary({
    required String key,
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
    Color color = AppColors.onSurface,
  }) =>
      OutlinedButton(
        key: Key(key),
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: color,
          side: BorderSide(color: color.withValues(alpha: 0.45)),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
          minimumSize: const Size(0, 42),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16),
            const SizedBox(width: 5),
            Flexible(
              child: Text(label,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      );
}

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.receipt_long_outlined,
                  size: 44, color: AppColors.onSurfaceMuted),
              const SizedBox(height: 12),
              Text(message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 14, color: AppColors.onSurfaceMuted)),
              const SizedBox(height: 14),
              OutlinedButton(onPressed: onRetry, child: const Text('Reintentar')),
            ],
          ),
        ),
      );
}
