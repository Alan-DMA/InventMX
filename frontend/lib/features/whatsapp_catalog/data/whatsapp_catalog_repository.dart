import '../../inventory/data/inventory_mock_data.dart';
import '../../inventory/domain/product.dart';
import '../domain/catalog_settings.dart';
import '../domain/public_catalog.dart';
import '../domain/whatsapp_order.dart';
import 'whatsapp_message_formatter.dart';

/// Contrato del catálogo digital — Tarea 13.2.
///
/// Dos caras: la **pública** (sin sesión, lo que ve el cliente) y la del
/// **tendero** (autenticada, `GET/PUT /catalog-settings`). Rutas reales del
/// backend (`whatsapp_catalog/api/endpoints.py`), no las del yaml.
abstract class WhatsappCatalogRepository {
  /// `GET /public/catalog/{store_slug}?search=&category_id=`.
  Future<PublicCatalog> fetchPublicCatalog(
    String slug, {
    String? search,
    String? categoryId,
  });

  /// `POST /public/catalog/{store_slug}/build-whatsapp-order`.
  Future<WhatsAppOrderBuild> buildWhatsAppOrder(
    String slug,
    WhatsAppOrderDraft draft,
  );

  /// Registra el pedido y devuelve su folio — **endpoint que el backend aún
  /// no tiene** (iteración 3 de QA, Sep 2026). Propuesto para Alan:
  /// `POST /public/catalog/{slug}/orders` → `SavedOrder`. Mientras, el mock
  /// lo guarda en memoria.
  Future<SavedOrder> submitOrder(String slug, WhatsAppOrderDraft draft);

  /// El ticket que abre la tienda desde el enlace del chat —
  /// `GET /public/catalog/{slug}/orders/{folio}` (propuesto).
  Future<SavedOrder> fetchOrder(String slug, String folio);

  /// `GET /catalog-settings` (tenant de la sesión).
  Future<CatalogSettings> getSettings();

  /// `PUT /catalog-settings` — solo los campos que 13.2.3 edita.
  Future<CatalogSettings> updateSettings({
    bool? isCatalogEnabled,
    String? whatsappNumber,
  });
}

// ---------------------------------------------------------------------------
// Mock — activo mientras la app corre sin `DioClient` (todos los módulos)
// ---------------------------------------------------------------------------

/// Vitrina sembrada con los mismos productos del inventario mock, para que
/// el tendero vea en "Ver como cliente" exactamente lo que tiene en su
/// inventario (la sensación de RF-25 sin backend).
///
/// El slug se deriva del nombre del negocio del onboarding (`slugify`); con
/// backend real llega en la configuración del tenant.
class WhatsappCatalogRepositoryMock implements WhatsappCatalogRepository {
  WhatsappCatalogRepositoryMock({
    required this.storeName,
    List<Product>? products,
    this.formatter = const WhatsAppMessageFormatter(),
    this.latency = const Duration(milliseconds: 400),
    String? whatsappNumber = '+52 55 1234 5678',
    DateTime Function()? now,
  })  : now = now ?? DateTime.now,
        _products = products ?? mockProducts,
        _settings = CatalogSettings(
          slug: slugify(storeName),
          storeName: storeName,
          whatsappNumber: whatsappNumber,
          businessHours: 'Lunes a Sábado 8:00 AM - 8:00 PM',
          minOrderAmountMxn: 50,
          deliveryFeeMxn: 20,
        );

  final String storeName;
  final WhatsAppMessageFormatter formatter;
  final Duration latency;
  final List<Product> _products;
  CatalogSettings _settings;

  /// Pedidos registrados en esta sesión (folio → pedido). Con backend real
  /// esto vive en la base de datos y el enlace funciona desde cualquier
  /// teléfono; con el mock solo dentro de la misma pestaña.
  final _orders = <String, SavedOrder>{};

  /// Inyectable para folios deterministas en tests.
  final DateTime Function() now;

  @override
  Future<PublicCatalog> fetchPublicCatalog(
    String slug, {
    String? search,
    String? categoryId,
  }) async {
    await Future<void>.delayed(latency);
    if (slug != _settings.slug) throw StoreNotFound(slug);
    if (!_settings.isCatalogEnabled) throw CatalogDisabled(storeName);

    final visible = _products
        .where((p) => p.isActive && p.isOnCatalog)
        .map(_toPublic)
        .toList();

    // Categorías con conteo — sobre todo lo visible, no sobre lo filtrado,
    // para que los chips no desaparezcan al buscar.
    final counts = <String, int>{};
    for (final p in visible) {
      counts.update(p.categoryName ?? 'Otros', (n) => n + 1, ifAbsent: () => 1);
    }
    final categories = [
      for (final entry in counts.entries)
        PublicCategory(
          id: slugify(entry.key),
          name: entry.key,
          productCount: entry.value,
        ),
    ]..sort((a, b) => a.name.compareTo(b.name));

    var filtered = visible;
    if (categoryId != null && categoryId.isNotEmpty) {
      filtered = filtered.where((p) => p.categoryId == categoryId).toList();
    }
    final q = search?.trim().toLowerCase() ?? '';
    if (q.isNotEmpty) {
      filtered = filtered
          .where((p) =>
              p.name.toLowerCase().contains(q) ||
              p.sku.toLowerCase().contains(q))
          .toList();
    }

    return PublicCatalog(
      store: _storeInfo(),
      categories: categories,
      products: filtered,
      totalProducts: visible.length,
    );
  }

  @override
  Future<WhatsAppOrderBuild> buildWhatsAppOrder(
    String slug,
    WhatsAppOrderDraft draft,
  ) async {
    await Future<void>.delayed(latency);
    if (slug != _settings.slug) throw StoreNotFound(slug);
    return formatter.build(store: _storeInfo(), draft: draft);
  }

  @override
  Future<SavedOrder> submitOrder(String slug, WhatsAppOrderDraft draft) async {
    await Future<void>.delayed(latency);
    if (slug != _settings.slug) throw StoreNotFound(slug);
    final totals = formatter.build(store: _storeInfo(), draft: draft);
    final issuedAt = now();
    final order = SavedOrder(
      folio: orderFolio(totals.formattedText, issuedAt),
      slug: slug,
      issuedAt: issuedAt,
      draft: draft,
      totals: totals,
    );
    _orders[order.folio] = order;
    return order;
  }

  @override
  Future<SavedOrder> fetchOrder(String slug, String folio) async {
    await Future<void>.delayed(latency);
    if (slug != _settings.slug) throw StoreNotFound(slug);
    final order = _orders[folio];
    if (order == null) throw OrderNotFound(folio);
    return order;
  }

  @override
  Future<CatalogSettings> getSettings() async {
    await Future<void>.delayed(latency);
    return _settings;
  }

  @override
  Future<CatalogSettings> updateSettings({
    bool? isCatalogEnabled,
    String? whatsappNumber,
  }) async {
    await Future<void>.delayed(latency);
    _settings = _settings.copyWith(
      isCatalogEnabled: isCatalogEnabled,
      whatsappNumber: whatsappNumber == null ? null : () => whatsappNumber,
    );
    return _settings;
  }

  PublicStoreInfo _storeInfo() => PublicStoreInfo(
        name: _settings.storeName,
        slug: _settings.slug,
        whatsappNumber: _settings.whatsappNumber,
        welcomeMessage: _settings.welcomeMessage,
        businessHours: _settings.businessHours,
        minOrderAmountMxn: _settings.minOrderAmountMxn,
        deliveryFeeMxn: _settings.deliveryFeeMxn,
        deliveryEnabled: _settings.deliveryEnabled,
        pickupEnabled: _settings.pickupEnabled,
        isCatalogEnabled: _settings.isCatalogEnabled,
      );

  static PublicCatalogProduct _toPublic(Product p) => PublicCatalogProduct(
        id: p.id,
        name: p.name,
        sku: p.sku,
        categoryId: slugify(p.category),
        categoryName: p.category,
        priceMxn: p.priceMxn,
        imageUrl: p.imageUrl,
        inStock: p.availableStock > 0,
        availableStock: p.availableStock.toDouble(),
      );
}
