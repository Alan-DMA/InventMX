import 'package:flutter/material.dart';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../purchases/presentation/widgets/phone_launcher.dart';
import '../../../../core/utils/form_focus.dart';
import '../../../../core/constants/catalog_config.dart';
import '../../data/whatsapp_message_formatter.dart';
import '../../domain/public_catalog.dart';
import '../../domain/whatsapp_order.dart';
import '../catalog_theme.dart';
import '../whatsapp_catalog_provider.dart';
import 'order_ticket.dart';
import 'product_card.dart';

/// Abre "Tu pedido" — Tarea 13.2.2.
Future<void> showOrderSheet(
  BuildContext context, {
  required PublicStoreInfo store,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: CatalogColors.ground,
    // El `Material` del sheet lo crea la app con su tema OSCURO y fija un
    // `DefaultTextStyle` claro; sin un Material propio dentro del tema claro
    // todo texto sin color explícito salía blanco sobre blanco (QA de
    // Eduardo: "títulos que no se ven").
    builder: (_) => Theme(
      data: CatalogTheme.light,
      child: FractionallySizedBox(
        heightFactor: 0.94,
        child: Material(
          color: CatalogColors.ground,
          child: OrderSheet(store: store),
        ),
      ),
    ),
  );
}

/// El pedido completo antes de mandarlo: renglones editables, datos del
/// cliente, entrega, pago, totales y — la parte que importa — **el mensaje
/// tal como le llegará a la tienda**. El cliente ve exactamente lo que se
/// envía; no hay sorpresas después del toque.
///
/// Solo se piden los datos que el pedido necesita: nombre siempre; teléfono
/// opcional; dirección solo a domicilio; "¿con cuánto pagas?" solo en
/// efectivo y opcional (decisión de Eduardo: nunca pedir de más).
class OrderSheet extends ConsumerStatefulWidget {
  const OrderSheet({super.key, required this.store});

  final PublicStoreInfo store;

  @override
  ConsumerState<OrderSheet> createState() => _OrderSheetState();
}

class _OrderSheetState extends ConsumerState<OrderSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _cashCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  late DeliveryMethod _delivery = widget.store.pickupEnabled
      ? DeliveryMethod.pickup
      : DeliveryMethod.delivery;
  PaymentMethodPreview _payment = PaymentMethodPreview.cash;
  bool _sending = false;

  /// Fecha con la que la vista previa calcula el folio provisional; el folio
  /// definitivo lo asigna el registro del pedido.
  final _issuedAt = DateTime.now();

  /// Los errores del formulario aparecen solo después del primer intento de
  /// envío: marcar en rojo la dirección antes de que el cliente la toque es
  /// regañarlo por algo que aún no hizo.
  bool _submitted = false;
  String? _sendError;
  String? _fallbackText;

  static const _formatter = WhatsAppMessageFormatter();

  @override
  void initState() {
    super.initState();
    for (final c in [
      _nameCtrl,
      _phoneCtrl,
      _addressCtrl,
      _cashCtrl,
      _notesCtrl
    ]) {
      c.addListener(_onFieldChanged);
    }
  }

  @override
  void dispose() {
    for (final c in [
      _nameCtrl,
      _phoneCtrl,
      _addressCtrl,
      _cashCtrl,
      _notesCtrl
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void _onFieldChanged() => setState(() => _sendError = null);

  // ── Estado derivado ───────────────────────────────────────────────────────

  PublicStoreInfo get _store => widget.store;

  double? get _cashTendered {
    final raw = _cashCtrl.text.trim().replaceAll(',', '');
    if (raw.isEmpty) return null;
    return double.tryParse(raw);
  }

  WhatsAppOrderDraft _draft(OrderCart cart) => WhatsAppOrderDraft(
        customerName: _nameCtrl.text.trim(),
        customerPhone:
            _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
        deliveryMethod: _delivery,
        deliveryAddress: _delivery == DeliveryMethod.delivery
            ? _addressCtrl.text.trim()
            : null,
        paymentMethod: _payment,
        cashTenderedMxn:
            _payment == PaymentMethodPreview.cash ? _cashTendered : null,
        orderNotes:
            _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        lines: cart.lines.values.toList(),
      );

  double get _deliveryFee =>
      _delivery == DeliveryMethod.delivery ? _store.deliveryFeeMxn : 0;

  /// Lo que falta para el pedido mínimo, o 0.
  double _shortfall(OrderCart cart) {
    final min = _store.minOrderAmountMxn;
    if (min <= 0 || cart.subtotalMxn >= min) return 0;
    return min - cart.subtotalMxn;
  }

  /// Vista previa local (mismo formateador que el backend): el borrador con
  /// marcadores donde el cliente aún no escribió, y el resultado — o la
  /// razón por la que el pedido todavía no se puede armar.
  ({WhatsAppOrderDraft draft, WhatsAppOrderBuild? build, String? reason})
      _preview(OrderCart cart) {
    final draft = _draft(cart).copyWithNameFallback();
    try {
      final build = _formatter.build(store: _store, draft: draft);
      return (draft: draft, build: build, reason: null);
    } on OrderRejected catch (e) {
      return (draft: draft, build: null, reason: e.message);
    }
  }

  // ── Acciones ──────────────────────────────────────────────────────────────

  /// Valida el pedido (mismas reglas que el backend) y devuelve el resultado
  /// o `null` si no pasa — el error ya quedó en pantalla.
  Future<WhatsAppOrderBuild?> _validate(OrderCart cart) async {
    setState(() => _submitted = true);
    if (!(_formKey.currentState?.validate() ?? false)) {
      // El error se muestra donde está el campo, no donde está el botón.
      focusFirstInvalidField(_formKey);
      return null;
    }
    setState(() {
      _sending = true;
      _sendError = null;
      _fallbackText = null;
    });
    try {
      return await ref
          .read(whatsappCatalogRepositoryProvider)
          .buildWhatsAppOrder(_store.slug, _draft(cart));
    } on OrderRejected catch (e) {
      if (!mounted) return null;
      setState(() {
        _sending = false;
        _sendError = e.message;
      });
      return null;
    } catch (_) {
      // Sin servidor el pedido no se pierde: se arma aquí mismo.
      try {
        return _formatter.build(store: _store, draft: _draft(cart));
      } on OrderRejected catch (e) {
        if (!mounted) return null;
        setState(() {
          _sending = false;
          _sendError = e.message;
        });
        return null;
      }
    }
  }

  /// Envía el pedido: se **registra** (folio) y el chat de la tienda se abre
  /// directo (`wa.me/{número}`) con un aviso corto + enlace al ticket. El
  /// detalle vive en el servidor: editar el mensaje no cambia el pedido, y
  /// no hace falta tener a la tienda en contactos (iteración 3 de QA).
  Future<void> _send() async {
    final cart = ref.read(orderCartProvider);
    setState(() => _submitted = true);
    if (!(_formKey.currentState?.validate() ?? false)) {
      focusFirstInvalidField(_formKey);
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _sending = true;
      _sendError = null;
      _fallbackText = null;
    });

    final SavedOrder order;
    try {
      order = await ref
          .read(whatsappCatalogRepositoryProvider)
          .submitOrder(_store.slug, _draft(cart));
    } on OrderRejected catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _sendError = e.message;
      });
      return;
    } catch (_) {
      // Sin servidor no hay folio ni enlace: el pedido no se pierde, va con
      // el detalle completo en el texto (el formato del backend).
      if (!mounted) return;
      final build = await _validate(cart);
      if (build == null || !mounted) return;
      await _launchText(build, messenger);
      return;
    }
    if (!mounted) return;

    final text = WhatsAppMessageFormatter.orderLinkText(
      store: _store,
      order: order,
      ticketUrl:
          publicOrderUrl(_store.slug, order.folio, key: order.accessKey),
    );
    final opened = await ref.read(urlLauncherProvider)(
      WhatsAppMessageFormatter.waLinkFor(_store.whatsappNumber, text),
      mode: LaunchMode.externalApplication,
    );
    if (!mounted) return;
    if (opened) {
      setState(() => _sending = false);
      Navigator.of(context).pop();
      messenger.showSnackBar(SnackBar(
        content: Text('Pedido ${order.folio} listo. Solo toca enviar en '
            'WhatsApp.'),
      ));
    } else {
      setState(() {
        _sending = false;
        _fallbackText = text;
      });
    }
  }

  Future<void> _launchText(
    WhatsAppOrderBuild build,
    ScaffoldMessengerState messenger,
  ) async {
    final opened = await ref.read(urlLauncherProvider)(
      build.waLink,
      mode: LaunchMode.externalApplication,
    );
    if (!mounted) return;
    if (opened) {
      setState(() => _sending = false);
      Navigator.of(context).pop();
      messenger.showSnackBar(const SnackBar(
        content: Text('Tu pedido se abrió en WhatsApp. Solo toca enviar.'),
      ));
    } else {
      setState(() {
        _sending = false;
        _fallbackText = build.formattedText;
      });
    }
  }

  Future<void> _copyFallback() async {
    final text = _fallbackText;
    if (text == null) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Mensaje copiado. Pégalo en el chat de la tienda.'),
    ));
  }

  // ── UI ────────────────────────────────────────────────────────────────────

  /// U-09 (WC-02) — nota por renglón ("bien frío", "sin cebolla"). Va en el
  /// mensaje de WhatsApp junto al producto; el backend ya la acepta.
  Future<void> _editNote(CartLine line) async {
    final result = await showDialog<String>(
      context: context,
      builder: (_) => _NoteDialog(
        productName: line.product.name,
        initial: line.notes ?? '',
      ),
    );
    if (result == null || !mounted) return;
    ref
        .read(orderCartProvider.notifier)
        .setNotes(line.product.id, result.trim().isEmpty ? null : result.trim());
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(orderCartProvider);
    final notifier = ref.read(orderCartProvider.notifier);
    final shortfall = _shortfall(cart);
    final total = cart.subtotalMxn + _deliveryFee;
    final change = _payment == PaymentMethodPreview.cash &&
            _cashTendered != null &&
            _cashTendered! >= total
        ? _cashTendered! - total
        : null;
    final canSend =
        !cart.isEmpty && shortfall == 0 && _store.canReceiveOrders && !_sending;

    if (cart.isEmpty) {
      return _EmptyOrder(onBrowse: () => Navigator.of(context).pop());
    }

    return Column(
      children: [
        const _Handle(),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 12, 4),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Tu pedido',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                ),
              ),
              TextButton(
                key: const Key('orderClear'),
                onPressed: () {
                  notifier.clear();
                  Navigator.of(context).pop();
                },
                style: TextButton.styleFrom(
                    foregroundColor: CatalogColors.inkMuted),
                child: const Text('Vaciar'),
              ),
            ],
          ),
        ),
        Expanded(
          child: Form(
            key: _formKey,
            autovalidateMode: _submitted
                ? AutovalidateMode.onUserInteraction
                : AutovalidateMode.disabled,
            // Sin `ListView`: el contenido es corto y así todo existe en el
            // árbol (los `ensureVisible` de los tests y del teclado funcionan).
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final line in cart.lines.values)
                    _OrderLine(
                      line: line,
                      onAdd: () => notifier.add(line.product),
                      onRemove: () => notifier.remove(line.product.id),
                      onEditNote: () => _editNote(line),
                    ),
                  if (shortfall > 0) ...[
                    const SizedBox(height: 8),
                    _Notice(
                      key: const Key('orderMinNotice'),
                      icon: Icons.info_outline_rounded,
                      text:
                          'El pedido mínimo es ${mxn(_store.minOrderAmountMxn)}. '
                          'Te faltan ${mxn(shortfall)}.',
                    ),
                  ],
                  const SizedBox(height: 22),
                  const _SectionTitle('¿A nombre de quién?'),
                  TextFormField(
                    key: const Key('orderName'),
                    controller: _nameCtrl,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(hintText: 'Tu nombre'),
                    validator: (v) => (v ?? '').trim().length < 2
                        ? 'Escribe tu nombre para que la tienda sepa de quién es.'
                        : null,
                  ),
                  // El teléfono solo cuando hay entrega: para recoger, el
                  // chat de WhatsApp ya trae el número de quien escribe.
                  if (_delivery == DeliveryMethod.delivery) ...[
                    const SizedBox(height: 10),
                    TextFormField(
                      key: const Key('orderPhone'),
                      controller: _phoneCtrl,
                      keyboardType: TextInputType.phone,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                          hintText: 'Tu teléfono (opcional)'),
                    ),
                  ],
                  const SizedBox(height: 22),
                  const _SectionTitle('¿Cómo lo recibes?'),
                  _Choice<DeliveryMethod>(
                    value: _delivery,
                    options: [
                      if (_store.pickupEnabled) DeliveryMethod.pickup,
                      if (_store.deliveryEnabled) DeliveryMethod.delivery,
                    ],
                    label: (m) => m == DeliveryMethod.delivery &&
                            _store.deliveryFeeMxn > 0
                        ? '${m.label} · +${mxn(_store.deliveryFeeMxn)}'
                        : m.label,
                    keyFor: (m) => Key('delivery-${m.name}'),
                    onChanged: (m) => setState(() => _delivery = m),
                  ),
                  if (_delivery == DeliveryMethod.delivery) ...[
                    const SizedBox(height: 10),
                    TextFormField(
                      key: const Key('orderAddress'),
                      controller: _addressCtrl,
                      textCapitalization: TextCapitalization.sentences,
                      maxLines: 2,
                      decoration: const InputDecoration(
                          hintText: 'Calle, número y colonia'),
                      validator: (v) => _delivery == DeliveryMethod.delivery &&
                              (v ?? '').trim().length < 5
                          ? 'Escribe la dirección de entrega.'
                          : null,
                    ),
                  ],
                  const SizedBox(height: 22),
                  const _SectionTitle('¿Cómo vas a pagar?'),
                  _Choice<PaymentMethodPreview>(
                    value: _payment,
                    options: PaymentMethodPreview.values,
                    label: (m) => m.label,
                    keyFor: (m) => Key('payment-${m.name}'),
                    onChanged: (m) => setState(() => _payment = m),
                  ),
                  if (_payment == PaymentMethodPreview.cash) ...[
                    const SizedBox(height: 10),
                    TextFormField(
                      key: const Key('orderCash'),
                      controller: _cashCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        hintText: '¿Con cuánto pagas? (opcional)',
                        prefixText: '\$ ',
                      ),
                      validator: (v) {
                        final raw = (v ?? '').trim();
                        if (raw.isEmpty) return null;
                        final amount = double.tryParse(raw.replaceAll(',', ''));
                        if (amount == null) return 'Escribe solo la cantidad.';
                        if (amount < total) {
                          return 'Es menos que el total (${mxn(total)}).';
                        }
                        return null;
                      },
                    ),
                    if (change != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        'Cambio: ${mxn(change)}',
                        key: const Key('orderChange'),
                        style: const TextStyle(
                          color: CatalogColors.inkMuted,
                          fontFeatures: CatalogTheme.tabular,
                        ),
                      ),
                    ],
                  ],
                  const SizedBox(height: 22),
                  const _SectionTitle('¿Algo más que deba saber la tienda?'),
                  TextFormField(
                    key: const Key('orderNotes'),
                    controller: _notesCtrl,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                        hintText: 'Ej. tocar el timbre, sin bolsa… (opcional)'),
                  ),
                  const SizedBox(height: 22),
                  _Totals(
                    subtotal: cart.subtotalMxn,
                    deliveryFee: _deliveryFee,
                    showDelivery: _delivery == DeliveryMethod.delivery,
                    total: total,
                  ),
                  const SizedBox(height: 22),
                  const _SectionTitle('Así le llegará a la tienda'),
                  _TicketPreview(
                    store: _store,
                    preview: _preview(cart),
                    issuedAt: _issuedAt,
                  ),
                  if (!_store.canReceiveOrders) ...[
                    const SizedBox(height: 16),
                    const _Notice(
                      key: Key('orderNoWhatsapp'),
                      icon: Icons.phone_disabled_outlined,
                      text: 'Esta tienda todavía no tiene WhatsApp configurado '
                          'para recibir pedidos.',
                    ),
                  ],
                  if (_sendError != null) ...[
                    const SizedBox(height: 16),
                    _Notice(
                      key: const Key('orderSendError'),
                      icon: Icons.error_outline_rounded,
                      text: _sendError!,
                      danger: true,
                    ),
                  ],
                  if (_fallbackText != null) ...[
                    const SizedBox(height: 16),
                    _FallbackCopy(onCopy: _copyFallback),
                  ],
                ],
              ),
            ),
          ),
        ),
        _SendBar(
          enabled: canSend,
          sending: _sending,
          total: total,
          storeName: _store.name,
          onSend: _send,
        ),
      ],
    );
  }
}

extension on WhatsAppOrderDraft {
  /// Para la vista previa antes de que el cliente llene los campos: se
  /// sustituyen con marcadores en vez de fallar la validación.
  WhatsAppOrderDraft copyWithNameFallback() => copyWith(
        customerName: customerName.isEmpty ? '(tu nombre)' : null,
        deliveryAddress: deliveryMethod == DeliveryMethod.delivery &&
                (deliveryAddress ?? '').trim().length < 5
            ? '(tu dirección)'
            : null,
      );
}

// ---------------------------------------------------------------------------
// Piezas
// ---------------------------------------------------------------------------

class _Handle extends StatelessWidget {
  const _Handle();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 6),
      child: Center(
        child: Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: CatalogColors.line,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        text,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _OrderLine extends StatelessWidget {
  const _OrderLine({
    required this.line,
    required this.onAdd,
    required this.onRemove,
    required this.onEditNote,
  });

  final CartLine line;
  final VoidCallback onAdd;
  final VoidCallback onRemove;
  final VoidCallback onEditNote;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: ValueKey('orderLine-${line.product.id}'),
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: CatalogColors.line)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  line.product.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 14.5, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 3),
                Text(
                  '${mxn(line.product.priceMxn)} c/u',
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: CatalogColors.inkMuted,
                    fontFeatures: CatalogTheme.tabular,
                  ),
                ),
                // Nota por renglón (U-09): un toque para escribirla o cambiarla.
                InkWell(
                  key: ValueKey('orderLineNote-${line.product.id}'),
                  onTap: onEditNote,
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.only(top: 4, bottom: 2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          (line.notes?.isNotEmpty ?? false)
                              ? Icons.sticky_note_2_outlined
                              : Icons.add_comment_outlined,
                          size: 14,
                          color: CatalogColors.accent,
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            (line.notes?.isNotEmpty ?? false)
                                ? line.notes!
                                : 'Agregar nota',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: CatalogColors.accent,
                              fontStyle: (line.notes?.isNotEmpty ?? false)
                                  ? FontStyle.italic
                                  : FontStyle.normal,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 72,
            child: Text(
              mxn(line.subtotalMxn),
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                fontFeatures: CatalogTheme.tabular,
              ),
            ),
          ),
          const SizedBox(width: 12),
          QuantityStepper(
            quantity: line.quantity,
            onAdd: onAdd,
            onRemove: onRemove,
            compact: true,
          ),
        ],
      ),
    );
  }
}

class _Choice<T> extends StatelessWidget {
  const _Choice({
    required this.value,
    required this.options,
    required this.label,
    required this.keyFor,
    required this.onChanged,
  });

  final T value;
  final List<T> options;
  final String Function(T) label;
  final Key Function(T) keyFor;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final option in options)
          _ChoiceChip(
            key: keyFor(option),
            label: label(option),
            selected: option == value,
            onTap: () => onChanged(option),
          ),
      ],
    );
  }
}

class _ChoiceChip extends StatelessWidget {
  const _ChoiceChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Material(
        color: selected ? CatalogColors.accent : CatalogColors.ground,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          // Sin `alignment` en el Container: con él se expande a todo el
          // ancho del Wrap y las opciones dejan de ser píldoras.
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: selected ? CatalogColors.accent : CatalogColors.line,
              ),
            ),
            child: Center(
              widthFactor: 1,
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: selected ? CatalogColors.onAccent : CatalogColors.ink,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Totals extends StatelessWidget {
  const _Totals({
    required this.subtotal,
    required this.deliveryFee,
    required this.showDelivery,
    required this.total,
  });

  final double subtotal;
  final double deliveryFee;
  final bool showDelivery;
  final double total;

  @override
  Widget build(BuildContext context) {
    Widget row(String label, double amount, {bool strong = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: strong ? 16 : 14,
                    fontWeight: strong ? FontWeight.w800 : FontWeight.w500,
                    color: strong ? CatalogColors.ink : CatalogColors.inkMuted,
                  ),
                ),
              ),
              Text(
                mxn(amount),
                style: TextStyle(
                  fontSize: strong ? 18 : 14,
                  fontWeight: strong ? FontWeight.w800 : FontWeight.w600,
                  fontFeatures: CatalogTheme.tabular,
                ),
              ),
            ],
          ),
        );

    return Container(
      key: const Key('orderTotals'),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
        color: CatalogColors.tile,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          row('Subtotal', subtotal),
          if (showDelivery) row('Envío a domicilio', deliveryFee),
          const Divider(height: 12),
          row('Total', total, strong: true),
        ],
      ),
    );
  }
}

/// El ticket tal como se enviará, o la razón por la que aún no se puede
/// armar. Es lo mismo que la tienda verá al abrir el enlace del chat: "lo
/// que ves es lo que va".
class _TicketPreview extends StatelessWidget {
  const _TicketPreview({
    required this.store,
    required this.preview,
    required this.issuedAt,
  });

  final PublicStoreInfo store;
  final ({
    WhatsAppOrderDraft draft,
    WhatsAppOrderBuild? build,
    String? reason
  }) preview;
  final DateTime issuedAt;

  @override
  Widget build(BuildContext context) {
    final build = preview.build;
    if (build == null) {
      return _Notice(
        key: const Key('orderPreviewReason'),
        icon: Icons.receipt_long_outlined,
        text: preview.reason ?? '',
      );
    }
    return Center(
      child: Container(
        key: const Key('orderPreview'),
        decoration: BoxDecoration(
          border: Border.all(color: CatalogColors.line),
          borderRadius: BorderRadius.circular(6),
          boxShadow: [
            BoxShadow(
              color: CatalogColors.ink.withValues(alpha: 0.08),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: OrderTicket(
          store: store,
          draft: preview.draft,
          totals: build,
          folio: orderFolio(build.formattedText, issuedAt),
          issuedAt: issuedAt,
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({
    super.key,
    required this.icon,
    required this.text,
    this.danger = false,
  });

  final IconData icon;
  final String text;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger ? CatalogColors.danger : CatalogColors.ink;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: danger ? CatalogColors.dangerSoft : CatalogColors.tile,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 13.5, height: 1.4, color: color),
            ),
          ),
        ],
      ),
    );
  }
}

class _FallbackCopy extends StatelessWidget {
  const _FallbackCopy({required this.onCopy});

  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Notice(
          icon: Icons.open_in_new_off_rounded,
          text: 'No se pudo abrir WhatsApp en este teléfono. Copia el mensaje '
              'y pégalo en el chat de la tienda.',
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          key: const Key('orderCopyFallback'),
          onPressed: onCopy,
          icon: const Icon(Icons.copy_rounded, size: 18),
          label: const Text('Copiar mensaje'),
        ),
      ],
    );
  }
}

class _SendBar extends StatelessWidget {
  const _SendBar({
    required this.enabled,
    required this.sending,
    required this.total,
    required this.storeName,
    required this.onSend,
  });

  final bool enabled;
  final bool sending;
  final double total;
  final String storeName;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
      decoration: const BoxDecoration(
        color: CatalogColors.ground,
        border: Border(top: BorderSide(color: CatalogColors.line)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton(
            key: const Key('orderSend'),
            onPressed: enabled ? onSend : null,
            child: sending
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.4, color: CatalogColors.onAccent),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.send_rounded, size: 18),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text(
                          'Enviar pedido por WhatsApp · ${mxn(total)}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
          ),
          const SizedBox(height: 6),
          // Lo que pasa al tocar, dicho antes: se abre el chat de la tienda
          // (no hace falta tenerla en contactos) con el folio y el enlace.
          Text(
            'Se abre el chat de $storeName en WhatsApp con tu folio.',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: CatalogColors.inkMuted),
          ),
        ],
      ),
    );
  }
}

class _EmptyOrder extends StatelessWidget {
  const _EmptyOrder({required this.onBrowse});

  final VoidCallback onBrowse;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.shopping_basket_outlined,
              size: 40, color: CatalogColors.inkMuted),
          const SizedBox(height: 12),
          const Text(
            'Tu pedido está vacío',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          const Text(
            'Toca "+" en los productos que quieras.',
            textAlign: TextAlign.center,
            style: TextStyle(color: CatalogColors.inkMuted),
          ),
          const SizedBox(height: 20),
          FilledButton(onPressed: onBrowse, child: const Text('Ver productos')),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Nota por renglón (U-09)
// ---------------------------------------------------------------------------

class _NoteDialog extends StatefulWidget {
  const _NoteDialog({required this.productName, required this.initial});

  final String productName;
  final String initial;

  @override
  State<_NoteDialog> createState() => _NoteDialogState();
}

class _NoteDialogState extends State<_NoteDialog> {
  late final _ctrl = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: CatalogColors.ground,
      title: Text(
        widget.productName,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: CatalogColors.ink),
      ),
      content: TextField(
        key: const Key('orderNoteField'),
        controller: _ctrl,
        autofocus: true,
        maxLength: 80,
        textCapitalization: TextCapitalization.sentences,
        onSubmitted: (v) => Navigator.of(context).pop(v),
        style: const TextStyle(color: CatalogColors.ink),
        decoration: const InputDecoration(
          labelText: 'Nota para la tienda',
          hintText: 'Ej. bien frío, sin cebolla',
        ),
      ),
      actions: [
        if (widget.initial.isNotEmpty)
          TextButton(
            key: const Key('orderNoteClear'),
            onPressed: () => Navigator.of(context).pop(''),
            child: const Text('Quitar nota'),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          key: const Key('orderNoteSave'),
          style: FilledButton.styleFrom(
            backgroundColor: CatalogColors.accent,
            foregroundColor: Colors.white,
          ),
          onPressed: () => Navigator.of(context).pop(_ctrl.text),
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}
