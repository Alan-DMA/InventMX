import 'package:dio/dio.dart';

import '../../../core/network/dio_client.dart';
import '../domain/catalog_settings.dart';
import '../domain/public_catalog.dart';
import '../domain/whatsapp_order.dart';
import 'whatsapp_catalog_repository.dart';

/// Catálogo digital contra el backend real (`whatsapp_catalog`, Tarea 13.1).
///
/// Rutas, tal como están en `backend/app/modules/whatsapp_catalog/api/endpoints.py`:
///
/// | Método del contrato    | Endpoint                                              | Sesión |
/// |------------------------|-------------------------------------------------------|--------|
/// | `fetchPublicCatalog`   | `GET  /public/catalog/{slug}?search=&category_id=`    | no     |
/// | `buildWhatsAppOrder`   | `POST /public/catalog/{slug}/build-whatsapp-order`    | no     |
/// | `submitOrder`          | `POST /public/catalog/{slug}/orders` → 201 + folio    | no     |
/// | `fetchOrder`           | `GET  /public/catalog/{slug}/orders/{folio}`          | no     |
/// | `getSettings`          | `GET  /catalog-settings`                              | sí     |
/// | `updateSettings`       | `PUT  /catalog-settings`                              | sí     |
///
/// Las rutas públicas se llaman sin `Authorization` (el `AuthInterceptor`
/// sólo adjunta el Bearer si hay token guardado), así la vitrina funciona en
/// una pestaña sin sesión, que es como la abre el cliente desde el enlace.
class WhatsappCatalogRepositoryImpl implements WhatsappCatalogRepository {
  WhatsappCatalogRepositoryImpl({required this.client});

  final DioClient client;

  static const _base = '/api/v1';

  // ---------------------------------------------------------------------------
  // Vitrina pública
  // ---------------------------------------------------------------------------

  @override
  Future<PublicCatalog> fetchPublicCatalog(
    String slug, {
    String? search,
    String? categoryId,
  }) async {
    try {
      final response = await client.get<dynamic>(
        '$_base/public/catalog/$slug',
        queryParameters: {
          if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
          if (categoryId != null && categoryId.isNotEmpty)
            'category_id': categoryId,
        },
      );
      final data = _asMap(response.data);
      return PublicCatalog(
        store: _storeFromJson(_asMap(data['store'])),
        categories: [
          for (final c in data['categories'] as List? ?? const [])
            PublicCategory(
              id: (c as Map)['id'].toString(),
              name: c['name'].toString(),
              productCount: _int(c['product_count']),
            ),
        ],
        products: [
          for (final p in data['products'] as List? ?? const [])
            _productFromJson(_asMap(p)),
        ],
        totalProducts: _int(data['total_products']),
      );
    } on DioException catch (e) {
      throw _catalogFailure(e, slug);
    }
  }

  @override
  Future<WhatsAppOrderBuild> buildWhatsAppOrder(
    String slug,
    WhatsAppOrderDraft draft,
  ) async {
    try {
      final response = await client.post<dynamic>(
        '$_base/public/catalog/$slug/build-whatsapp-order',
        data: _draftToJson(draft),
      );
      return _buildFromJson(_asMap(response.data));
    } on DioException catch (e) {
      throw _orderFailure(e, slug);
    }
  }

  @override
  Future<SavedOrder> submitOrder(String slug, WhatsAppOrderDraft draft) async {
    try {
      final response = await client.post<dynamic>(
        '$_base/public/catalog/$slug/orders',
        data: _draftToJson(draft),
      );
      return savedOrderFromJson(_asMap(response.data));
    } on DioException catch (e) {
      throw _orderFailure(e, slug);
    }
  }

  @override
  Future<SavedOrder> fetchOrder(String slug, String folio, {String? accessKey}) async {
    try {
      final response = await client.get<dynamic>(
        '$_base/public/catalog/$slug/orders/${Uri.encodeComponent(folio)}',
        queryParameters: {if (accessKey != null) 'k': accessKey},
      );
      return savedOrderFromJson(_asMap(response.data));
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        // Mismo código para "no existe la tienda" y "no existe el folio";
        // el detalle del backend los distingue.
        final detail = _detail(e).toLowerCase();
        if (detail.contains('pedido')) throw OrderNotFound(folio);
        throw StoreNotFound(slug);
      }
      throw _catalogFailure(e, slug);
    }
  }

  // ---------------------------------------------------------------------------
  // Panel del tendero (autenticado)
  // ---------------------------------------------------------------------------

  @override
  Future<CatalogSettings> getSettings() async {
    try {
      final response = await client.get<dynamic>('$_base/catalog-settings');
      return _settingsFromJson(_asMap(response.data));
    } on DioException catch (e) {
      throw _settingsFailure(e);
    }
  }

  @override
  Future<CatalogSettings> updateSettings({
    bool? isCatalogEnabled,
    String? whatsappNumber,
    String? welcomeMessage,
    double? minOrderAmountMxn,
    double? deliveryFeeMxn,
    bool? deliveryEnabled,
    bool? pickupEnabled,
    String? businessHours,
  }) async {
    // Sólo viajan los campos que se quieren cambiar (`exclude_unset` del
    // lado del servidor). Un texto vacío borra el campo — el backend lo
    // guarda como NULL.
    final body = <String, dynamic>{
      if (isCatalogEnabled != null) 'is_catalog_enabled': isCatalogEnabled,
      if (whatsappNumber != null) 'whatsapp_number': whatsappNumber,
      if (welcomeMessage != null) 'welcome_message': welcomeMessage,
      if (minOrderAmountMxn != null) 'min_order_amount_mxn': minOrderAmountMxn,
      if (deliveryFeeMxn != null) 'delivery_fee_mxn': deliveryFeeMxn,
      if (deliveryEnabled != null) 'delivery_enabled': deliveryEnabled,
      if (pickupEnabled != null) 'pickup_enabled': pickupEnabled,
      if (businessHours != null) 'business_hours': businessHours,
    };
    try {
      final response =
          await client.put<dynamic>('$_base/catalog-settings', data: body);
      return _settingsFromJson(_asMap(response.data));
    } on DioException catch (e) {
      throw _settingsFailure(e);
    }
  }

  // ---------------------------------------------------------------------------
  // Serialización
  // ---------------------------------------------------------------------------

  static Map<String, dynamic> _draftToJson(WhatsAppOrderDraft draft) => {
        'customer_name': draft.customerName.trim(),
        if (draft.customerPhone != null &&
            draft.customerPhone!.trim().isNotEmpty)
          'customer_phone': draft.customerPhone!.trim(),
        'delivery_method': draft.deliveryMethod.apiValue,
        if (draft.deliveryAddress != null &&
            draft.deliveryAddress!.trim().isNotEmpty)
          'delivery_address': draft.deliveryAddress!.trim(),
        'payment_method': draft.paymentMethod.apiValue,
        if (draft.cashTenderedMxn != null)
          'cash_tendered_mxn': draft.cashTenderedMxn,
        'items': [
          for (final line in draft.lines)
            {
              'product_id': line.product.id,
              'quantity': line.quantity,
              if (line.notes != null && line.notes!.trim().isNotEmpty)
                'notes': line.notes!.trim(),
            },
        ],
        if (draft.orderNotes != null && draft.orderNotes!.trim().isNotEmpty)
          'order_notes': draft.orderNotes!.trim(),
      };

  static PublicStoreInfo _storeFromJson(Map<String, dynamic> j) =>
      PublicStoreInfo(
        name: j['name'].toString(),
        slug: j['slug'].toString(),
        whatsappNumber: _text(j['whatsapp_number']),
        welcomeMessage: _text(j['welcome_message']),
        businessHours: _text(j['business_hours']),
        minOrderAmountMxn: _double(j['min_order_amount_mxn']),
        deliveryFeeMxn: _double(j['delivery_fee_mxn']),
        deliveryEnabled: j['delivery_enabled'] != false,
        pickupEnabled: j['pickup_enabled'] != false,
        isCatalogEnabled: j['is_catalog_enabled'] != false,
      );

  static PublicCatalogProduct _productFromJson(Map<String, dynamic> j) =>
      PublicCatalogProduct(
        id: j['id'].toString(),
        name: j['name'].toString(),
        sku: (j['sku'] ?? '').toString(),
        categoryId: _text(j['category_id']),
        categoryName: _text(j['category_name']),
        priceMxn: _double(j['price_mxn']),
        imageUrl: _text(j['image_url']),
        inStock: j['in_stock'] != false,
        availableStock: _double(j['available_stock']),
      );

  static WhatsAppOrderBuild _buildFromJson(Map<String, dynamic> j) =>
      WhatsAppOrderBuild(
        waLink: Uri.parse(j['wa_link'].toString()),
        formattedText: j['formatted_text'].toString(),
        subtotalMxn: _double(j['subtotal_mxn']),
        deliveryFeeMxn: _double(j['delivery_fee_mxn']),
        totalMxn: _double(j['total_mxn']),
        changeMxn: j['change_mxn'] == null ? null : _double(j['change_mxn']),
        itemCount: _int(j['item_count']),
      );

  /// `CatalogOrderResponse` → `SavedOrder`. Los renglones vienen como
  /// instantánea (nombre y precio al momento de pedir), no como producto
  /// vivo: por eso `inStock`/`availableStock` se rellenan con la cantidad.
  /// Pública porque `StoreOrdersRepositoryImpl` arma el mismo ticket.
  static SavedOrder savedOrderFromJson(Map<String, dynamic> j) {
    final lines = <CartLine>[
      for (final raw in j['items'] as List? ?? const [])
        lineFromJson(_asMap(raw)),
    ];
    final draft = WhatsAppOrderDraft(
      customerName: j['customer_name'].toString(),
      customerPhone: _text(j['customer_phone']),
      deliveryMethod: DeliveryMethod.values.firstWhere(
        (m) => m.apiValue == j['delivery_method'],
        orElse: () => DeliveryMethod.pickup,
      ),
      deliveryAddress: _text(j['delivery_address']),
      paymentMethod: PaymentMethodPreview.values.firstWhere(
        (m) => m.apiValue == j['payment_method'],
        orElse: () => PaymentMethodPreview.cash,
      ),
      cashTenderedMxn:
          j['cash_tendered_mxn'] == null ? null : _double(j['cash_tendered_mxn']),
      orderNotes: _text(j['order_notes']),
      lines: lines,
    );
    return SavedOrder(
      folio: j['folio'].toString(),
      slug: j['store_slug'].toString(),
      issuedAt: DateTime.parse(j['created_at'].toString()).toLocal(),
      draft: draft,
      totals: _buildFromJson(j),
      status: OrderStatus.fromApi(j['status']?.toString()),
      statusChangedAt: _date(j['status_changed_at']),
      cancelReason: CancelReason.fromApi(_text(j['cancel_reason'])),
      storeEditedAt: _date(j['store_edited_at']),
      updatedAt: _date(j['updated_at']),
      accessKey: _text(j['access_key']),
    );
  }

  static DateTime? _date(dynamic v) =>
      v == null ? null : DateTime.tryParse(v.toString())?.toLocal();

  static CartLine lineFromJson(Map<String, dynamic> j) {
    final quantity = _double(j['quantity']).round();
    return CartLine(
      product: PublicCatalogProduct(
        id: j['product_id'].toString(),
        name: j['name'].toString(),
        sku: (j['sku'] ?? '').toString(),
        categoryId: _text(j['category_id']),
        categoryName: _text(j['category_name']),
        priceMxn: _double(j['price_mxn']),
        imageUrl: _text(j['image_url']),
        inStock: true,
        availableStock: quantity.toDouble(),
      ),
      quantity: quantity,
      notes: _text(j['notes']),
    );
  }

  static CatalogSettings _settingsFromJson(Map<String, dynamic> j) =>
      CatalogSettings(
        slug: j['store_slug'].toString(),
        storeName: j['store_name'].toString(),
        isCatalogEnabled: j['is_catalog_enabled'] != false,
        whatsappNumber: _text(j['whatsapp_number']),
        welcomeMessage: _text(j['welcome_message']),
        minOrderAmountMxn: _double(j['min_order_amount_mxn']),
        deliveryFeeMxn: _double(j['delivery_fee_mxn']),
        deliveryEnabled: j['delivery_enabled'] != false,
        pickupEnabled: j['pickup_enabled'] != false,
        businessHours: _text(j['business_hours']),
      );

  // ---------------------------------------------------------------------------
  // Errores
  // ---------------------------------------------------------------------------

  /// 404 → tienda inexistente; 403 → catálogo apagado; lo demás → sin servicio.
  static PublicCatalogFailure _catalogFailure(DioException e, String slug) {
    switch (e.response?.statusCode) {
      case 404:
        return StoreNotFound(slug);
      case 403:
        // El 403 no trae el nombre de la tienda; se humaniza el slug para
        // el mensaje ("abarrotes-don-pepe" → "Abarrotes Don Pepe").
        return CatalogDisabled(_titleFromSlug(slug));
      default:
        return const CatalogUnavailable();
    }
  }

  /// Las reglas de la tienda (400/422) llegan con el texto listo para
  /// mostrar; 404/403 se tratan como en la vitrina; el resto es "sin red".
  static Exception _orderFailure(DioException e, String slug) {
    final status = e.response?.statusCode;
    if (status == 400 || status == 422) {
      return OrderRejected(_detail(e));
    }
    return _catalogFailure(e, slug);
  }

  static Exception _settingsFailure(DioException e) {
    final detail = _detail(e);
    return CatalogSettingsException(
      detail.isEmpty ? 'No se pudo guardar la configuración del catálogo.' : detail,
    );
  }

  /// `detail` del backend, ya sea texto (HTTPException) o la lista de
  /// errores de validación de Pydantic.
  static String _detail(DioException e) {
    final data = e.response?.data;
    if (data is Map) {
      final detail = data['detail'];
      if (detail is String) return detail;
      if (detail is List) {
        return detail
            .map((d) => d is Map ? (d['msg'] ?? d).toString() : d.toString())
            .join('. ');
      }
      final error = data['error'];
      if (error is Map && error['message'] != null) {
        return error['message'].toString();
      }
    }
    return '';
  }

  static String _titleFromSlug(String slug) => slug
      .split('-')
      .where((w) => w.isNotEmpty)
      .map((w) => w[0].toUpperCase() + w.substring(1))
      .join(' ');

  // ---------------------------------------------------------------------------
  // Utilidades
  // ---------------------------------------------------------------------------

  static Map<String, dynamic> asMap(dynamic v) => _asMap(v);

  static Map<String, dynamic> _asMap(dynamic v) =>
      v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

  static String? _text(dynamic v) {
    if (v == null) return null;
    final s = v.toString().trim();
    return s.isEmpty ? null : s;
  }

  static double _double(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0;
  }

  static int _int(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.round();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }
}

/// El panel "Mi catálogo" no pudo leer o guardar la configuración.
class CatalogSettingsException implements Exception {
  const CatalogSettingsException(this.message);

  final String message;

  @override
  String toString() => message;
}
