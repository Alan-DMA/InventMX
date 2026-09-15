import 'package:equatable/equatable.dart';

/// Datos públicos del comercio en la cabecera de la vitrina — espejo de
/// `PublicStoreInfoResponse` del backend real
/// (`backend/app/modules/whatsapp_catalog/schemas/public_catalog.py`).
///
/// Tarea 13.2. Se modela contra el backend y no contra
/// `docs/api/catalog.yaml`: el yaml describe rutas y schemas que el backend
/// no implementa (discrepancia registrada para Alan en
/// `registro_implementacion.md`).
class PublicStoreInfo extends Equatable {
  const PublicStoreInfo({
    required this.name,
    required this.slug,
    this.whatsappNumber,
    this.welcomeMessage,
    this.businessHours,
    this.minOrderAmountMxn = 0,
    this.deliveryFeeMxn = 0,
    this.deliveryEnabled = true,
    this.pickupEnabled = true,
    this.isCatalogEnabled = true,
  });

  final String name;
  final String slug;
  final String? whatsappNumber;
  final String? welcomeMessage;
  final String? businessHours;
  final double minOrderAmountMxn;
  final double deliveryFeeMxn;
  final bool deliveryEnabled;
  final bool pickupEnabled;
  final bool isCatalogEnabled;

  /// Sin número no hay a quién mandarle el pedido.
  bool get canReceiveOrders =>
      whatsappNumber != null && whatsappNumber!.trim().isNotEmpty;

  @override
  List<Object?> get props => [
        name,
        slug,
        whatsappNumber,
        welcomeMessage,
        businessHours,
        minOrderAmountMxn,
        deliveryFeeMxn,
        deliveryEnabled,
        pickupEnabled,
        isCatalogEnabled,
      ];
}

/// Renglón de producto visible al cliente — `PublicProductItemResponse`.
class PublicCatalogProduct extends Equatable {
  const PublicCatalogProduct({
    required this.id,
    required this.name,
    required this.sku,
    required this.priceMxn,
    this.categoryId,
    this.categoryName,
    this.imageUrl,
    this.inStock = true,
    this.availableStock = 0,
  });

  final String id;
  final String name;
  final String sku;
  final String? categoryId;
  final String? categoryName;
  final double priceMxn;
  final String? imageUrl;
  final bool inStock;
  final double availableStock;

  @override
  List<Object?> get props => [
        id,
        name,
        sku,
        categoryId,
        categoryName,
        priceMxn,
        imageUrl,
        inStock,
        availableStock,
      ];
}

/// Categoría con conteo — `PublicCategoryResponse`.
class PublicCategory extends Equatable {
  const PublicCategory({
    required this.id,
    required this.name,
    this.productCount = 0,
  });

  final String id;
  final String name;
  final int productCount;

  @override
  List<Object?> get props => [id, name, productCount];
}

/// Respuesta completa de `GET /public/catalog/{store_slug}`.
class PublicCatalog extends Equatable {
  const PublicCatalog({
    required this.store,
    this.categories = const [],
    this.products = const [],
    this.totalProducts = 0,
  });

  final PublicStoreInfo store;
  final List<PublicCategory> categories;
  final List<PublicCatalogProduct> products;
  final int totalProducts;

  @override
  List<Object?> get props => [store, categories, products, totalProducts];
}

/// Fallos con pantalla propia en la vitrina — distinguirlos importa porque
/// la salida es distinta: "vuelve más tarde" no es "revisa tu conexión".
sealed class PublicCatalogFailure implements Exception {
  const PublicCatalogFailure();
}

/// El slug no corresponde a ningún comercio.
class StoreNotFound extends PublicCatalogFailure {
  const StoreNotFound(this.slug);

  final String slug;
}

/// El comercio existe pero apagó su catálogo.
class CatalogDisabled extends PublicCatalogFailure {
  const CatalogDisabled(this.storeName);

  final String storeName;
}

/// Sin red o el servidor no respondió.
class CatalogUnavailable extends PublicCatalogFailure {
  const CatalogUnavailable();
}
