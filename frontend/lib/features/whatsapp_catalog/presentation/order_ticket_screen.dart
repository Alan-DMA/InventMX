import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../domain/public_catalog.dart';
import '../domain/whatsapp_order.dart';
import 'catalog_theme.dart';
import 'whatsapp_catalog_provider.dart';
import 'widgets/order_ticket.dart';

/// El ticket de un pedido — `/tienda/{slug}/pedido/{folio}` (Tarea 13.2.2,
/// iteración 3 de QA).
///
/// Es lo que abre la tienda desde el enlace del chat de WhatsApp. El mensaje
/// del chat es solo el aviso (folio, total, enlace); el pedido de verdad está
/// aquí, tal como el cliente lo confirmó. Sin sesión, tema claro de la
/// vitrina.
class OrderTicketScreen extends ConsumerStatefulWidget {
  const OrderTicketScreen({
    super.key,
    required this.slug,
    required this.folio,
    this.accessKey,
    this.pollEvery = const Duration(seconds: 10),
    this.slowPollAfter = const Duration(minutes: 5),
    this.slowPollEvery = const Duration(seconds: 30),
  });

  final String slug;
  final String folio;

  /// `?k=` del enlace del chat. Sin ella el backend responde 404.
  final String? accessKey;

  /// Cada cuánto se vuelve a leer el pedido mientras la página está abierta:
  /// el cliente no tiene sesión ni socket, pero "Listo" debe verse solo.
  /// Pasados [slowPollAfter] baja a [slowPollEvery] y se detiene cuando el
  /// pedido ya está entregado o cancelado (una pestaña olvidada no debe
  /// seguir pegándole al servidor).
  final Duration pollEvery;
  final Duration slowPollAfter;
  final Duration slowPollEvery;

  @override
  ConsumerState<OrderTicketScreen> createState() => _OrderTicketScreenState();
}

class _OrderTicketScreenState extends ConsumerState<OrderTicketScreen> {
  Timer? _poll;
  late final DateTime _openedAt = DateTime.now();

  ({String slug, String folio, String? accessKey}) get _key =>
      (slug: widget.slug, folio: widget.folio, accessKey: widget.accessKey);

  @override
  void initState() {
    super.initState();
    if (widget.pollEvery > Duration.zero) _schedule(widget.pollEvery);
  }

  void _schedule(Duration every) {
    _poll?.cancel();
    _poll = Timer(every, _tick);
  }

  void _tick() {
    if (!mounted) return;
    final current = ref.read(savedOrderProvider(_key)).valueOrNull;
    if (current != null && current.status.isClosed) return; // ya no cambia
    // `refresh` (no `invalidate`) conserva el ticket en pantalla mientras
    // llega el nuevo; un fallo de red pasajero no tira la página.
    unawaited(ref
        .refresh(savedOrderProvider(_key).future)
        .then<void>((_) {}, onError: (_) {}));
    final elapsed = DateTime.now().difference(_openedAt);
    _schedule(elapsed >= widget.slowPollAfter
        ? widget.slowPollEvery
        : widget.pollEvery);
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final slug = widget.slug;
    final folio = widget.folio;
    final order = ref.watch(savedOrderProvider(_key));

    return Theme(
      data: CatalogTheme.light,
      child: Scaffold(
        backgroundColor: CatalogColors.tile,
        appBar: AppBar(
          backgroundColor: CatalogColors.ground,
          foregroundColor: CatalogColors.ink,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          title: Text(
            'Pedido $folio',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          shape: const Border(bottom: BorderSide(color: CatalogColors.line)),
        ),
        body: order.when(
          loading: () => const Center(
            child: CircularProgressIndicator(color: CatalogColors.accent),
          ),
          error: (error, _) => _OrderFailure(
            error: error,
            folio: folio,
            onCatalog: () => context.go(AppRoutes.publicCatalogPath(slug)),
            onRetry: () =>
                ref.invalidate(savedOrderProvider(_key)),
          ),
          data: (saved) => RefreshIndicator(
            color: CatalogColors.accent,
            onRefresh: () => ref.refresh(savedOrderProvider(_key).future),
            child: _OrderBody(order: saved, slug: slug),
          ),
        ),
      ),
    );
  }
}

class _OrderBody extends ConsumerWidget {
  const _OrderBody({required this.order, required this.slug});

  final SavedOrder order;
  final String slug;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(publicCatalogProvider(slug)).value?.store ??
        PublicStoreInfo(name: _storeNameFallback(order), slug: slug);

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
      child: Column(
        children: [
          // Estado del pedido — lo que la tienda marcó en su app. Es el único
          // feedback que este enlace da al cliente; el resto va por el chat.
          _StatusBanner(order: order, store: store),
          const SizedBox(height: 14),
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              boxShadow: [
                BoxShadow(
                  color: CatalogColors.ink.withValues(alpha: 0.10),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: OrderTicket(
              key: const Key('savedOrderTicket'),
              store: store,
              draft: order.draft,
              totals: order.totals,
              folio: order.folio,
              issuedAt: order.issuedAt,
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            'Este pedido lo confirmó el cliente desde el catálogo. Lo que '
            'diga el mensaje del chat no cambia lo que ves aquí.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12.5,
              height: 1.4,
              color: CatalogColors.inkMuted,
            ),
          ),
          const SizedBox(height: 14),
          TextButton(
            key: const Key('orderOpenCatalog'),
            onPressed: () => context.go(AppRoutes.publicCatalogPath(slug)),
            child: const Text('Ver el catálogo'),
          ),
        ],
      ),
    );
  }

  static String _storeNameFallback(SavedOrder order) => order.slug
      .split('-')
      .where((w) => w.isNotEmpty)
      .map((w) => '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');
}

class _OrderFailure extends StatelessWidget {
  const _OrderFailure({
    required this.error,
    required this.folio,
    required this.onCatalog,
    required this.onRetry,
  });

  final Object error;
  final String folio;
  final VoidCallback onCatalog;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final (title, body, retry) = switch (error) {
      OrderNotFound() => (
          'No encontramos el pedido $folio',
          'Puede que el enlace esté incompleto o que el pedido se haya '
              'registrado en otro dispositivo. Pídele al cliente que lo vuelva '
              'a enviar desde el catálogo.',
          false,
        ),
      StoreNotFound() => (
          'No encontramos esta tienda',
          'Revisa que el enlace esté completo.',
          false,
        ),
      _ => (
          'No pudimos cargar el pedido',
          'Revisa tu conexión e inténtalo de nuevo.',
          true,
        ),
    };
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          key: const Key('orderFailure'),
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.receipt_long_outlined,
                size: 44, color: CatalogColors.inkMuted),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              body,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                height: 1.45,
                color: CatalogColors.inkMuted,
              ),
            ),
            const SizedBox(height: 22),
            if (retry)
              FilledButton(
                  onPressed: onRetry, child: const Text('Intentar de nuevo'))
            else
              OutlinedButton(
                  onPressed: onCatalog, child: const Text('Ver el catálogo')),
          ],
        ),
      ),
    );
  }
}

/// "Listo para recoger", "Entregado", "Cancelado" o "Recibido" + la marca de
/// "Actualizado por la tienda" cuando hubo una edición tras el chat. Sin esto
/// el enlace mentiría después de que la tienda cambiara el pedido.
class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.order, required this.store});

  final SavedOrder order;
  final PublicStoreInfo store;

  @override
  Widget build(BuildContext context) {
    final delivery = order.draft.deliveryMethod == DeliveryMethod.delivery;
    final (icon, title, body, color, soft) = switch (order.status) {
      OrderStatus.newOrder => (
          Icons.schedule_rounded,
          'Pedido recibido',
          '${store.name} lo verá en su app y te contesta por el chat.',
          CatalogColors.inkMuted,
          CatalogColors.tile,
        ),
      OrderStatus.ready => (
          delivery ? Icons.delivery_dining_rounded : Icons.shopping_bag_rounded,
          delivery ? 'Tu pedido va en camino' : 'Listo para recoger',
          delivery
              ? 'La tienda ya lo tiene preparado y sale a tu dirección.'
              : 'Ya puedes pasar por él a ${store.name}.',
          CatalogColors.accent,
          CatalogColors.accentSoft,
        ),
      OrderStatus.delivered => (
          Icons.check_circle_rounded,
          'Entregado',
          '¡Gracias por tu compra!',
          CatalogColors.accent,
          CatalogColors.accentSoft,
        ),
      OrderStatus.cancelled => (
          Icons.cancel_rounded,
          'Pedido cancelado',
          'Si no fuiste tú, escríbele a la tienda por el chat.',
          CatalogColors.danger,
          CatalogColors.dangerSoft,
        ),
    };
    final edited = order.storeEditedAt;

    return Container(
      key: const Key('orderStatusBanner'),
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: soft,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            body,
            style: const TextStyle(
                fontSize: 12.5, height: 1.35, color: CatalogColors.ink),
          ),
          if (edited != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.edit_note_rounded,
                    size: 16, color: CatalogColors.inkMuted),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    'Actualizado por la tienda a las '
                    '${edited.hour.toString().padLeft(2, '0')}:'
                    '${edited.minute.toString().padLeft(2, '0')} — '
                    'esto es lo que acordaron por el chat.',
                    key: const Key('orderEditedNote'),
                    style: const TextStyle(
                        fontSize: 11.5, color: CatalogColors.inkMuted),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
