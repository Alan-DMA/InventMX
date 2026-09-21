import 'package:nexus_app/features/whatsapp_catalog/domain/public_catalog.dart';
import 'package:nexus_app/features/whatsapp_catalog/domain/store_order.dart';
import 'package:nexus_app/features/whatsapp_catalog/domain/whatsapp_order.dart';

/// Reloj fijo de las fixtures: 16 sep 2026, 12:00.
final fixedNow = DateTime(2026, 9, 16, 12, 0);

const cocaCola = PublicCatalogProduct(
  id: 'prod-001',
  name: 'Coca-Cola 600ml',
  sku: 'COC-600',
  priceMxn: 18.5,
  categoryName: 'Bebidas',
  availableStock: 24,
);

const sabritas = PublicCatalogProduct(
  id: 'prod-002',
  name: 'Sabritas 45g',
  sku: 'SAB-45',
  priceMxn: 16,
  categoryName: 'Botanas',
  availableStock: 3,
);

/// Pedido de Laura: 3 Coca-Colas a domicilio, paga con $100, hace 12 min.
StoreOrder lauraOrder({
  String folio = 'P-260916-AB12',
  OrderStatus status = OrderStatus.newOrder,
  DateTime? seenAt,
  String? saleId,
  DeliveryMethod delivery = DeliveryMethod.delivery,
  String? possibleDuplicateOf,
  List<OrderRevision> revisions = const [],
}) {
  final issued = fixedNow.subtract(const Duration(minutes: 12));
  const subtotal = 55.5;
  final fee = delivery == DeliveryMethod.delivery ? 20.0 : 0.0;
  return StoreOrder(
    order: SavedOrder(
      folio: folio,
      slug: 'tiendita-nexus',
      issuedAt: issued,
      updatedAt: issued,
      status: status,
      draft: WhatsAppOrderDraft(
        customerName: 'Laura Jiménez',
        customerPhone: '+525518324477',
        deliveryMethod: delivery,
        deliveryAddress:
            delivery == DeliveryMethod.delivery ? 'Av. Reforma 10, Centro' : null,
        cashTenderedMxn: 100,
        orderNotes: 'Tocar el timbre',
        lines: const [
          CartLine(product: cocaCola, quantity: 3, notes: 'bien frías'),
        ],
      ),
      totals: WhatsAppOrderBuild(
        waLink: Uri.parse('https://wa.me/525518324477'),
        formattedText: 'pedido',
        subtotalMxn: subtotal,
        deliveryFeeMxn: fee,
        totalMxn: subtotal + fee,
        changeMxn: 100 - (subtotal + fee),
        itemCount: 1,
      ),
    ),
    seenAt: seenAt,
    seenByName: seenAt == null ? null : 'Eduardo',
    saleId: saleId,
    possibleDuplicateOf: possibleDuplicateOf,
    revisions: revisions,
  );
}

/// Pedido de Pedro: recoger en tienda, ya visto, listo.
StoreOrder pedroOrder({OrderStatus status = OrderStatus.ready}) => StoreOrder(
      order: SavedOrder(
        folio: 'P-260916-CD34',
        slug: 'tiendita-nexus',
        issuedAt: fixedNow.subtract(const Duration(hours: 2)),
        updatedAt: fixedNow.subtract(const Duration(hours: 1)),
        status: status,
        draft: const WhatsAppOrderDraft(
          customerName: 'Pedro Ramírez',
          lines: [CartLine(product: sabritas, quantity: 2)],
        ),
        totals: WhatsAppOrderBuild(
          waLink: Uri.parse('https://wa.me/'),
          formattedText: 'pedido',
          subtotalMxn: 32,
          totalMxn: 32,
          itemCount: 1,
        ),
      ),
      seenAt: fixedNow.subtract(const Duration(hours: 1)),
      seenByName: 'Eduardo',
      attendedByName: 'Eduardo',
    );
