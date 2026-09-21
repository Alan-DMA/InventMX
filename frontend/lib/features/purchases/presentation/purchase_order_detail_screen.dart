import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../data/purchases_repository.dart' show PurchasesException;
import '../domain/account_payable.dart';
import '../domain/purchase_order.dart';
import 'purchase_create_screen.dart';
import 'purchase_format.dart';
import 'purchases_provider.dart';
import 'widgets/purchase_status_pill.dart';
import 'widgets/receive_purchase_modal.dart';

/// Detalle de una orden de compra.
///
/// El tendero no abre esto para "consultar un registro": llega con una
/// pregunta concreta, y la pregunta cambia según el estado de la orden
/// (confirmada → ¿cuándo llega?; parcial → ¿qué me falta?; recibida → ¿cuánto
/// debo y cuándo vence?). Por eso la pantalla abre con una **respuesta** y no
/// con un encabezado: un folio arriba es un número de archivo, no le dice
/// nada a quien está de pie frente al repartidor.
///
/// Hasta esta pantalla, tocar una orden en el hub no hacía nada (`onTap`
/// vacío) y una vez recibida no quedaba forma de ver qué se había comprado —
/// el único lugar que listaba los productos era el modal de "Recibir", que
/// desaparece justo cuando la orden ya llegó (hallazgo de QA, Sep 19).
enum _OrderAction { edit, cancel }

class PurchaseOrderDetailScreen extends ConsumerWidget {
  const PurchaseOrderDetailScreen({super.key, required this.order});

  /// Orden con la que se abrió la pantalla. Sirve de semilla: lo que se pinta
  /// es la versión viva del provider, para que recibir mercancía desde aquí
  /// se refleje sin salir y volver a entrar.
  final PurchaseOrder order;

  void _openEdit(BuildContext context, PurchaseOrder live) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PurchaseCreateScreen(initial: live),
      ),
    );
  }

  /// Cancelar es irreversible y no hay "deshacer": la confirmación nombra el
  /// folio para que no se cancele una orden por otra, y el motivo es opcional
  /// porque pedirlo obligatorio sólo agregaría fricción a algo que ya se
  /// decidió.
  Future<void> _confirmCancel(
    BuildContext context,
    WidgetRef ref,
    PurchaseOrder live,
  ) async {
    final messenger = ScaffoldMessenger.of(context);

    // `null` = se cerró el diálogo sin cancelar la orden; `''` = se confirmó
    // sin escribir motivo.
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => _CancelOrderDialog(order: live),
    );
    if (reason == null) return;

    try {
      await ref.read(purchaseOrdersProvider.notifier).cancelOrder(
            purchaseOrderId: live.id,
            reason: reason.isEmpty ? null : reason,
          );
      messenger.showSnackBar(
        SnackBar(
          content: Text('Orden ${live.folio} cancelada'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          // El 422 del backend ya explica por qué no se pudo.
          content: Text(e is PurchasesException
              ? e.message
              : 'No se pudo cancelar la orden.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final live = ref
            .watch(purchaseOrdersProvider)
            .orders
            .where((o) => o.id == order.id)
            .firstOrNull ??
        order;

    // La CxP nace de la recepción de esta orden; obligar a cambiarse de
    // pestaña y recordar el folio para saber cuánto se debe sería pedirle al
    // usuario que cargue el contexto él. El cruce es local: no hay llamada.
    final payable = ref
        .watch(accountsPayableProvider)
        .items
        .where((p) => p.purchaseOrderId == live.id)
        .firstOrNull;

    final canReceive = live.status != PurchaseOrderStatus.received &&
        live.status != PurchaseOrderStatus.cancelled;

    return Scaffold(
      backgroundColor: AppColors.darkSlate,
      appBar: AppBar(
        backgroundColor: AppColors.darkSlate,
        title: const Text('Orden de compra'),
        actions: [
          // Editar y cancelar viven en el menú, no en la barra inferior: la
          // acción de todos los días es recibir, y una acción destructiva no
          // debe estar al alcance del pulgar por accidente. El backend las
          // rechaza en cuanto entra mercancía, así que aquí ni se ofrecen.
          if (canReceive)
            PopupMenuButton<_OrderAction>(
              key: const Key('purchaseDetailMenu'),
              tooltip: 'Más acciones',
              color: AppColors.surface,
              icon: const Icon(Icons.more_vert_rounded,
                  color: AppColors.onSurface),
              onSelected: (action) => switch (action) {
                _OrderAction.edit => _openEdit(context, live),
                _OrderAction.cancel => _confirmCancel(context, ref, live),
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: _OrderAction.edit,
                  child: Row(
                    children: [
                      Icon(Icons.edit_outlined,
                          size: 18, color: AppColors.onSurface),
                      SizedBox(width: 10),
                      Text('Editar orden',
                          style: TextStyle(color: AppColors.onSurface)),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: _OrderAction.cancel,
                  child: Row(
                    children: [
                      Icon(Icons.cancel_outlined,
                          size: 18, color: AppColors.error),
                      SizedBox(width: 10),
                      Text('Cancelar orden',
                          style: TextStyle(color: AppColors.error)),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            _Header(order: live),
            const SizedBox(height: 16),
            _AnswerBlock(order: live),
            const SizedBox(height: 24),
            const _SectionLabel('Productos'),
            const SizedBox(height: 8),
            _ItemsCard(order: live),
            const SizedBox(height: 16),
            _Totals(order: live),
            if (payable != null) ...[
              const SizedBox(height: 24),
              const _SectionLabel('Cuenta por pagar'),
              const SizedBox(height: 8),
              _PayableCard(payable: payable),
            ],
            if (live.invoiceReference != null || live.notes != null) ...[
              const SizedBox(height: 24),
              _Footnotes(order: live),
            ],
          ],
        ),
      ),
      bottomNavigationBar: canReceive ? _ReceiveBar(order: live) : null,
    );
  }
}

// ---------------------------------------------------------------------------
// Confirmación de cancelación
// ---------------------------------------------------------------------------

/// Widget propio y no un `AlertDialog` armado al vuelo: así el
/// `TextEditingController` muere cuando la ruta del diálogo termina de salir,
/// y no mientras su campo todavía se está dibujando.
class _CancelOrderDialog extends StatefulWidget {
  const _CancelOrderDialog({required this.order});

  final PurchaseOrder order;

  @override
  State<_CancelOrderDialog> createState() => _CancelOrderDialogState();
}

class _CancelOrderDialogState extends State<_CancelOrderDialog> {
  final _reasonCtrl = TextEditingController();

  @override
  void dispose() {
    _reasonCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text(
        '¿Cancelar la orden ${widget.order.folio}?',
        style: const TextStyle(fontSize: 17, color: AppColors.onSurface),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'La orden a ${widget.order.supplierName} queda cancelada. No se '
            'borra: seguirá en el historial marcada como cancelada.',
            style: const TextStyle(
                fontSize: 13, height: 1.4, color: AppColors.onSurfaceMuted),
          ),
          const SizedBox(height: 16),
          TextField(
            key: const Key('cancelOrderReasonField'),
            controller: _reasonCtrl,
            style: const TextStyle(fontSize: 14, color: AppColors.onSurface),
            decoration: const InputDecoration(
              labelText: 'Motivo (opcional)',
              hintText: 'Ej: el proveedor ya no tiene existencias',
              isDense: true,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Mejor no'),
        ),
        TextButton(
          key: const Key('cancelOrderConfirmButton'),
          onPressed: () => Navigator.of(context).pop(_reasonCtrl.text.trim()),
          style: TextButton.styleFrom(foregroundColor: AppColors.error),
          child: const Text('Cancelar orden'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Encabezado — quién y en qué va; el folio queda en segundo plano
// ---------------------------------------------------------------------------

class _Header extends StatelessWidget {
  const _Header({required this.order});

  final PurchaseOrder order;

  @override
  Widget build(BuildContext context) {
    final meta = [
      order.folio,
      if (order.warehouseName != null) order.warehouseName!,
    ].join(' · ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                order.supplierName,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: AppColors.onSurface,
                  height: 1.2,
                ),
              ),
            ),
            const SizedBox(width: 12),
            PurchaseStatusPill(status: order.status),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          meta,
          style: const TextStyle(fontSize: 12, color: AppColors.onSurfaceMuted),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// La respuesta — lo primero que se lee, y cambia según el estado
// ---------------------------------------------------------------------------

class _AnswerBlock extends StatelessWidget {
  const _AnswerBlock({required this.order});

  final PurchaseOrder order;

  /// Piezas pedidas que todavía no llegan.
  int get _pendingUnits => order.items.fold<int>(
        0,
        (sum, i) {
          final missing = i.quantity - i.quantityReceived;
          return sum + (missing > 0 ? missing : 0);
        },
      );

  (IconData, Color, String, String?) get _answer {
    switch (order.status) {
      case PurchaseOrderStatus.cancelled:
        return (
          Icons.cancel_outlined,
          AppColors.error,
          'Orden cancelada',
          null,
        );
      case PurchaseOrderStatus.received:
        return (
          Icons.check_circle_outline_rounded,
          AppColors.success,
          order.receivedDate == null
              ? 'Recibida completa'
              : 'Recibida completa el ${formatPurchaseDate(order.receivedDate!)}',
          null,
        );
      case PurchaseOrderStatus.partiallyReceived:
        final units = _pendingUnits;
        return (
          Icons.hourglass_bottom_rounded,
          AppColors.warning,
          units == 1
              ? 'Falta 1 pieza por llegar'
              : 'Faltan $units piezas por llegar',
          order.receivedDate == null
              ? null
              : 'Llegó parte el ${formatPurchaseDate(order.receivedDate!)}',
        );
      case PurchaseOrderStatus.draft:
      case PurchaseOrderStatus.sent:
      case PurchaseOrderStatus.confirmed:
        return order.expectedDeliveryDate == null
            ? (
                Icons.local_shipping_outlined,
                AppColors.onSurfaceMuted,
                'Sin fecha de entrega acordada',
                null,
              )
            : (
                Icons.local_shipping_outlined,
                AppColors.info,
                'Llega el ${formatPurchaseDate(order.expectedDeliveryDate!)}',
                null,
              );
    }
  }

  @override
  Widget build(BuildContext context) {
    final (icon, color, headline, detail) = _answer;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  headline,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: color,
                    height: 1.25,
                  ),
                ),
                if (detail != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    detail,
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.onSurfaceMuted),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Productos
// ---------------------------------------------------------------------------

class _ItemsCard extends StatelessWidget {
  const _ItemsCard({required this.order});

  final PurchaseOrder order;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < order.items.length; i++) ...[
            if (i > 0) const Divider(height: 1, color: AppColors.border),
            _ItemRow(
              item: order.items[i],
              // El avance por renglón sólo cuenta una historia cuando la orden
              // ya empezó a llegar: en una orden que no ha recibido nada, un
              // "0 de 12" en cada línea es ruido, y la respuesta de arriba ya
              // dijo cuándo llega.
              showProgress:
                  order.status == PurchaseOrderStatus.partiallyReceived,
            ),
          ],
        ],
      ),
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({required this.item, required this.showProgress});

  final PurchaseOrderItem item;
  final bool showProgress;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.productName,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.onSurface,
                      ),
                    ),
                    if (item.productSku != null) ...[
                      const SizedBox(height: 1),
                      Text(
                        item.productSku!,
                        style: const TextStyle(
                            fontSize: 11, color: AppColors.onSurfaceMuted),
                      ),
                    ],
                    const SizedBox(height: 3),
                    Text(
                      '${item.quantity} × \$${item.unitCostMxn.toStringAsFixed(2)}',
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.onSurfaceMuted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '\$${item.subtotalMxn.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.onSurface,
                ),
              ),
            ],
          ),
          if (showProgress) ...[
            const SizedBox(height: 8),
            _ReceptionProgress(item: item),
          ],
        ],
      ),
    );
  }
}

/// Avance de recepción de un renglón — sólo aparece dentro de una orden que
/// llegó a medias, que es cuando el dato distingue un producto de otro.
class _ReceptionProgress extends StatelessWidget {
  const _ReceptionProgress({required this.item});

  final PurchaseOrderItem item;

  @override
  Widget build(BuildContext context) {
    if (item.isFullyReceived) {
      return const Row(
        children: [
          Icon(Icons.check_rounded, size: 13, color: AppColors.success),
          SizedBox(width: 5),
          Text(
            'Completa',
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.success),
          ),
        ],
      );
    }

    final received = item.quantityReceived;
    final color = received == 0 ? AppColors.error : AppColors.warning;
    final ratio = item.quantity == 0 ? 0.0 : received / item.quantity;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: ratio,
            minHeight: 4,
            backgroundColor: AppColors.surfaceVariant,
            valueColor: AlwaysStoppedAnimation(color),
          ),
        ),
        const SizedBox(height: 5),
        Text(
          received == 0
              ? 'Sin recibir'
              : '$received de ${item.quantity} recibidas',
          style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w600, color: color),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Totales — los renglones que valen 0 no ocupan espacio
// ---------------------------------------------------------------------------

class _Totals extends StatelessWidget {
  const _Totals({required this.order});

  final PurchaseOrder order;

  @override
  Widget build(BuildContext context) {
    final hasBreakdown = order.taxMxn > 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          if (hasBreakdown) ...[
            _TotalRow(label: 'Subtotal', amount: order.subtotalMxn),
            const SizedBox(height: 6),
            _TotalRow(label: 'Impuestos', amount: order.taxMxn),
            const SizedBox(height: 10),
            const Divider(height: 1, color: AppColors.border),
            const SizedBox(height: 10),
          ],
          _TotalRow(label: 'Total', amount: order.totalMxn, emphasized: true),
        ],
      ),
    );
  }
}

class _TotalRow extends StatelessWidget {
  const _TotalRow({
    required this.label,
    required this.amount,
    this.emphasized = false,
  });

  final String label;
  final double amount;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: emphasized ? 14 : 12,
            fontWeight: emphasized ? FontWeight.w600 : FontWeight.w400,
            color: AppColors.onSurfaceMuted,
          ),
        ),
        Text(
          '\$${amount.toStringAsFixed(2)}${emphasized ? ' MXN' : ''}',
          style: TextStyle(
            fontSize: emphasized ? 18 : 13,
            fontWeight: emphasized ? FontWeight.w700 : FontWeight.w500,
            color: emphasized ? AppColors.skyBlue : AppColors.onSurface,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Cuenta por pagar generada por esta orden
// ---------------------------------------------------------------------------

class _PayableCard extends StatelessWidget {
  const _PayableCard({required this.payable});

  final AccountPayable payable;

  @override
  Widget build(BuildContext context) {
    final dueColor = switch (payable.urgency) {
      PayableUrgency.overdue => AppColors.error,
      PayableUrgency.dueSoon => AppColors.warning,
      PayableUrgency.onTime => AppColors.onSurfaceMuted,
    };
    final isSettled = payable.balanceMxn <= 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  payable.folio ?? payable.status.label,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.onSurface,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  isSettled
                      ? 'Pagada'
                      : 'Vence el ${formatPurchaseDate(payable.dueDate)}',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isSettled ? AppColors.success : dueColor),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text(
                'SALDO',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: AppColors.onSurfaceMuted,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '\$${payable.balanceMxn.toStringAsFixed(2)}',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: isSettled ? AppColors.success : AppColors.onSurface,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Factura y notas — si no existen, no hay renglón vacío que leer
// ---------------------------------------------------------------------------

class _Footnotes extends StatelessWidget {
  const _Footnotes({required this.order});

  final PurchaseOrder order;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (order.invoiceReference != null)
          _FootnoteRow(
            icon: Icons.receipt_long_outlined,
            text: 'Factura: ${order.invoiceReference}',
          ),
        if (order.invoiceReference != null && order.notes != null)
          const SizedBox(height: 8),
        if (order.notes != null)
          _FootnoteRow(
            icon: Icons.sticky_note_2_outlined,
            text: order.notes!,
          ),
      ],
    );
  }
}

class _FootnoteRow extends StatelessWidget {
  const _FootnoteRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon, size: 14, color: AppColors.onSurfaceMuted),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
                fontSize: 12, height: 1.4, color: AppColors.onSurfaceMuted),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Acción — la misma que ya se usa desde la tarjeta del listado
// ---------------------------------------------------------------------------

class _ReceiveBar extends StatelessWidget {
  const _ReceiveBar({required this.order});

  final PurchaseOrder order;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: ElevatedButton.icon(
          key: const Key('purchaseDetailReceiveButton'),
          onPressed: () => showReceivePurchaseModal(context, order),
          icon: const Icon(Icons.check_rounded, size: 18),
          label: const Text('Recibir mercancía'),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: AppColors.onSurface,
      ),
    );
  }
}
