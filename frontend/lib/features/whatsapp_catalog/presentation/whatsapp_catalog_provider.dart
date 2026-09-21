import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/data/auth_repository.dart';
import '../../onboarding/data/onboarding_repository.dart';
import '../data/whatsapp_catalog_repository.dart';
import '../data/whatsapp_catalog_repository_impl.dart';
import '../domain/catalog_settings.dart';
import '../domain/public_catalog.dart';
import '../domain/whatsapp_order.dart';

/// Nombre del negocio para sembrar el **mock** en tests y demos — el del
/// onboarding (Hive) o el de la demo. Con el backend real conectado (Sep
/// 2026) el slug y el nombre llegan en `GET /catalog-settings` y en la
/// vitrina pública; la app ya no lee este provider, sólo los tests que
/// montan `WhatsappCatalogRepositoryMock`.
final catalogStoreNameProvider = FutureProvider<String>((ref) async {
  try {
    final data = await ref.read(onboardingRepositoryProvider).load();
    final name = data.businessName.trim();
    return name.isEmpty ? kDemoStoreName : name;
  } catch (_) {
    return kDemoStoreName;
  }
});

const kDemoStoreName = 'Abarrotes Don Pepe';

/// Repositorio del catálogo contra el backend real (`whatsapp_catalog`,
/// 13.1). Los tests lo sustituyen por `WhatsappCatalogRepositoryMock`.
final whatsappCatalogRepositoryProvider =
    Provider<WhatsappCatalogRepository>((ref) {
  return WhatsappCatalogRepositoryImpl(client: ref.watch(dioClientProvider));
});

// ---------------------------------------------------------------------------
// Vitrina — carga del catálogo por slug con búsqueda y categoría (13.2.1)
// ---------------------------------------------------------------------------

class PublicCatalogQuery {
  const PublicCatalogQuery({this.search = '', this.categoryId});

  final String search;
  final String? categoryId;

  PublicCatalogQuery copyWith({
    String? search,
    String? Function()? categoryId,
  }) =>
      PublicCatalogQuery(
        search: search ?? this.search,
        categoryId: categoryId == null ? this.categoryId : categoryId(),
      );
}

/// Filtros activos de la vitrina. El catálogo se vuelve a pedir con ellos:
/// con backend real el filtrado es del servidor (`?search=&category_id=`).
final publicCatalogQueryProvider =
    NotifierProvider<PublicCatalogQueryNotifier, PublicCatalogQuery>(
  PublicCatalogQueryNotifier.new,
);

class PublicCatalogQueryNotifier extends Notifier<PublicCatalogQuery> {
  @override
  PublicCatalogQuery build() => const PublicCatalogQuery();

  void search(String text) => state = state.copyWith(search: text);

  void selectCategory(String? id) =>
      state = state.copyWith(categoryId: () => id);
}

/// El catálogo de la tienda `slug` con los filtros activos.
final publicCatalogProvider =
    FutureProvider.family<PublicCatalog, String>((ref, slug) async {
  final query = ref.watch(publicCatalogQueryProvider);
  return ref.watch(whatsappCatalogRepositoryProvider).fetchPublicCatalog(
        slug,
        search: query.search,
        categoryId: query.categoryId,
      );
});

/// El pedido registrado que abre la tienda desde el enlace del chat.
final savedOrderProvider = FutureProvider.family<SavedOrder,
    ({String slug, String folio, String? accessKey})>((ref, key) async {
  return ref
      .watch(whatsappCatalogRepositoryProvider)
      .fetchOrder(key.slug, key.folio, accessKey: key.accessKey);
});

// ---------------------------------------------------------------------------
// Pedido del cliente (13.2.2) — en memoria, sin cuenta
// ---------------------------------------------------------------------------

class OrderCart {
  const OrderCart({this.lines = const {}});

  /// productId → renglón, en orden de inserción.
  final Map<String, CartLine> lines;

  bool get isEmpty => lines.isEmpty;
  int get itemCount => lines.values.fold(0, (n, l) => n + l.quantity);
  int get lineCount => lines.length;
  double get subtotalMxn =>
      lines.values.fold(0, (sum, l) => sum + l.subtotalMxn);

  int quantityOf(String productId) => lines[productId]?.quantity ?? 0;
}

final orderCartProvider = NotifierProvider<OrderCartNotifier, OrderCart>(
  OrderCartNotifier.new,
);

class OrderCartNotifier extends Notifier<OrderCart> {
  @override
  OrderCart build() => const OrderCart();

  void add(PublicCatalogProduct product) {
    if (!product.inStock) return;
    final current = state.lines[product.id];
    _put(
        product.id,
        CartLine(
          product: product,
          quantity: (current?.quantity ?? 0) + 1,
          notes: current?.notes,
        ));
  }

  void remove(String productId) {
    final current = state.lines[productId];
    if (current == null) return;
    if (current.quantity <= 1) {
      final next = Map<String, CartLine>.from(state.lines)..remove(productId);
      state = OrderCart(lines: next);
    } else {
      _put(productId, current.copyWith(quantity: current.quantity - 1));
    }
  }

  void setNotes(String productId, String? notes) {
    final current = state.lines[productId];
    if (current == null) return;
    _put(productId, current.copyWith(notes: () => notes));
  }

  void clear() => state = const OrderCart();

  void _put(String id, CartLine line) {
    final next = Map<String, CartLine>.from(state.lines)..[id] = line;
    state = OrderCart(lines: next);
  }
}

// ---------------------------------------------------------------------------
// Panel del tendero (13.2.3)
// ---------------------------------------------------------------------------

final catalogSettingsProvider =
    AsyncNotifierProvider<CatalogSettingsNotifier, CatalogSettings>(
  CatalogSettingsNotifier.new,
);

class CatalogSettingsNotifier extends AsyncNotifier<CatalogSettings> {
  @override
  Future<CatalogSettings> build() async {
    return ref.watch(whatsappCatalogRepositoryProvider).getSettings();
  }

  Future<void> setEnabled(bool enabled) => _update(isCatalogEnabled: enabled);

  Future<void> setWhatsappNumber(String number) =>
      _update(whatsappNumber: number.trim());

  /// U-08 — reglas de la tienda que la vitrina ya respeta.
  Future<void> updateRules({
    required double minOrderAmountMxn,
    required double deliveryFeeMxn,
    required bool deliveryEnabled,
    required bool pickupEnabled,
    required String businessHours,
    required String welcomeMessage,
  }) =>
      _update(
        minOrderAmountMxn: minOrderAmountMxn,
        deliveryFeeMxn: deliveryFeeMxn,
        deliveryEnabled: deliveryEnabled,
        pickupEnabled: pickupEnabled,
        businessHours: businessHours,
        welcomeMessage: welcomeMessage,
      );

  /// Guarda y, si falla, regresa al valor anterior y propaga el error para
  /// que la pantalla lo diga — el switch nunca queda en un estado que el
  /// servidor no tiene.
  Future<void> _update({
    bool? isCatalogEnabled,
    String? whatsappNumber,
    String? welcomeMessage,
    double? minOrderAmountMxn,
    double? deliveryFeeMxn,
    bool? deliveryEnabled,
    bool? pickupEnabled,
    String? businessHours,
  }) async {
    final previous = state.value;
    state = const AsyncLoading<CatalogSettings>().copyWithPrevious(state);
    try {
      final updated =
          await ref.read(whatsappCatalogRepositoryProvider).updateSettings(
                isCatalogEnabled: isCatalogEnabled,
                whatsappNumber: whatsappNumber,
                welcomeMessage: welcomeMessage,
                minOrderAmountMxn: minOrderAmountMxn,
                deliveryFeeMxn: deliveryFeeMxn,
                deliveryEnabled: deliveryEnabled,
                pickupEnabled: pickupEnabled,
                businessHours: businessHours,
              );
      state = AsyncData(updated);
    } catch (_) {
      if (previous != null) state = AsyncData(previous);
      rethrow;
    }
  }
}
