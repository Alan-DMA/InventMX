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
class OrderTicketScreen extends ConsumerWidget {
  const OrderTicketScreen({
    super.key,
    required this.slug,
    required this.folio,
  });

  final String slug;
  final String folio;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final order = ref.watch(savedOrderProvider((slug: slug, folio: folio)));

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
                ref.invalidate(savedOrderProvider((slug: slug, folio: folio))),
          ),
          data: (saved) => _OrderBody(order: saved, slug: slug),
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
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
      child: Column(
        children: [
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
