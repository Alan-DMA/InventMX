import 'package:dio/dio.dart';
import '../../../core/network/dio_client.dart';
import '../domain/account_payable.dart';
import '../domain/purchase_order.dart';
import '../domain/receipt_scan.dart';
import '../domain/supplier.dart';
import 'receipt_line_parser.dart';

/// Los montos del backend viajan como `Decimal` de Python — Pydantic los
/// serializa como string ("40.00"), no como número JSON (mismo patrón que
/// `sales_repository.dart`/`cash_repository.dart`).
double _toDouble(dynamic value, [double fallback = 0]) {
  if (value == null) return fallback;
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? fallback;
  return fallback;
}

int _toInt(dynamic value, [int fallback = 0]) => _toDouble(value, fallback.toDouble()).round();

DateTime? _toDateTime(dynamic value) {
  if (value == null) return null;
  return DateTime.tryParse(value.toString());
}

/// Excepción de dominio para errores de red/validación de este módulo — no
/// confundir con [SupplierHasActiveOrdersException] (422 específico).
class PurchasesException implements Exception {
  const PurchasesException(this.message);
  final String message;

  @override
  String toString() => message;
}

// ---------------------------------------------------------------------------
// Modelo auxiliar de respuesta — espejo de `data` en
// `GET /accounts-payable` (docs/api/purchases.yaml)
// ---------------------------------------------------------------------------

class AccountsPayableResult {
  const AccountsPayableResult({required this.items, required this.summary});

  final List<AccountPayable> items;
  final AccountsPayableSummary summary;
}

// ---------------------------------------------------------------------------
// Contrato — alineado con docs/api/purchases.yaml
// ---------------------------------------------------------------------------

/// 422 de `DELETE /suppliers/{id}`: no se puede dar de baja un proveedor con
/// órdenes activas. El mensaje ya viene listo para mostrarse.
class SupplierHasActiveOrdersException implements Exception {
  const SupplierHasActiveOrdersException(this.activeOrders);
  final int activeOrders;

  String get message =>
      'Este proveedor tiene $activeOrders ${activeOrders == 1 ? 'orden activa' : 'órdenes activas'}. '
      'Recíbelas o cancélalas antes de darlo de baja.';

  @override
  String toString() => message;
}

abstract class PurchasesRepository {
  /// GET /suppliers
  Future<List<Supplier>> listSuppliers({String? search});

  /// POST /suppliers
  Future<Supplier> createSupplier({
    required String name,
    String? phone,
    String? email,
    String? rfc,
    String? address,
    int? creditDays,
    double? creditLimitMxn,
    String? notes,
  });

  /// PUT /suppliers/{id} — U-07 (C-01). Solo cambian los campos enviados.
  Future<Supplier> updateSupplier({
    required String id,
    String? name,
    String? phone,
    String? email,
    String? rfc,
    String? address,
    int? creditDays,
    double? creditLimitMxn,
    String? notes,
  });

  /// DELETE /suppliers/{id} — desactivación (soft delete). El backend responde
  /// 422 si el proveedor tiene órdenes activas (SENT / PARTIAL_RECEIVED);
  /// aquí se lanza [SupplierHasActiveOrdersException].
  Future<void> deactivateSupplier(String id);

  /// GET /purchase-orders
  /// Retorna únicamente órdenes SENT/PARTIAL_RECEIVED/RECEIVED — DRAFT y
  /// CANCELLED quedan fuera del alcance de 11.2 (ver plan aprobado).
  /// El agrupamiento "Todas/Pendientes/Recibidas" de los chips se resuelve
  /// en el provider, no aquí.
  Future<List<PurchaseOrder>> listPurchaseOrders({
    String? search,
    DateTime? dateFrom,
    DateTime? dateTo,
  });

  /// POST /purchase-orders
  Future<PurchaseOrder> createPurchaseOrder({
    required String supplierId,
    required List<PurchaseOrderItem> items,
    String? warehouseId,
    DateTime? expectedDeliveryDate,
    String? notes,
  });

  /// PUT /purchase-orders/{id}
  /// Sólo se permite mientras la orden no haya recibido mercancía; el backend
  /// responde 422 en cuanto entró la primera pieza (el stock y la CxP ya
  /// existen). Los [items] sustituyen por completo a los anteriores.
  Future<PurchaseOrder> updatePurchaseOrder({
    required String purchaseOrderId,
    String? supplierId,
    List<PurchaseOrderItem>? items,
    DateTime? expectedDeliveryDate,
    String? notes,
  });

  /// POST /purchase-orders/{id}/cancel
  /// Deja la orden en `CANCELLED` sin borrarla. Mismo 422 que la edición si
  /// ya recibió mercancía.
  Future<PurchaseOrder> cancelPurchaseOrder({
    required String purchaseOrderId,
    String? reason,
  });

  /// POST /purchase-orders/{id}/receive
  /// [updatedItems] trae la lista completa de líneas con `quantityReceived`
  /// ya actualizado — el mock recalcula el estado de la orden a partir de
  /// ellas (RECEIVED si todas están completas, PARTIAL_RECEIVED si alguna
  /// quedó incompleta).
  Future<PurchaseOrder> receivePurchaseOrder({
    required String purchaseOrderId,
    required List<PurchaseOrderItem> updatedItems,
    String? invoiceReference,
    String? notes,
  });

  /// GET /accounts-payable
  Future<AccountsPayableResult> listAccountsPayable({bool overdueOnly = false});

  /// POST /accounts-payable/{id}/pay
  /// La validación de "no exceder el saldo pendiente" vive en el provider
  /// (mismo criterio que `CashMovementsNotifier` con los retiros de caja) —
  /// el repositorio solo persiste.
  /// POST /purchases/parse-receipt
  ///
  /// Recibe las filas de texto que el OCR ya extrajo **en el dispositivo**
  /// (Constitución Art. IV: nada de visión cloud de pago) y devuelve los
  /// productos detectados. Mientras la Tarea 12.1 de Alan siga pendiente, el
  /// mock resuelve con `ReceiptLineParser` en local.
  Future<ReceiptParseResult> parseReceiptRows(List<String> rows);

  Future<AccountPayable> payAccountPayable({
    required String accountPayableId,
    required double amountPaidMxn,
    required SupplierPaymentMethod paymentMethod,
    String? reference,
    String? notes,
  });
}

// ---------------------------------------------------------------------------
// Implementación real — backend `purchasing_suppliers` (Sep 2026)
// ---------------------------------------------------------------------------

class PurchasesRepositoryImpl implements PurchasesRepository {
  PurchasesRepositoryImpl({required this.client});

  final DioClient client;

  Supplier _supplierFromJson(Map<String, dynamic> json) => Supplier(
        id: json['id'].toString(),
        tenantId: json['tenant_id']?.toString(),
        name: json['name']?.toString() ?? '',
        rfc: json['rfc']?.toString(),
        phone: json['phone']?.toString(),
        email: json['email']?.toString(),
        address: json['address']?.toString(),
        creditDays: _toInt(json['credit_days']),
        creditLimitMxn: _toDouble(json['credit_limit_mxn']),
        status: SupplierStatus.fromApi(json['status']?.toString() ?? 'ACTIVE'),
        notes: json['notes']?.toString(),
        createdAt: _toDateTime(json['created_at']) ?? DateTime.now(),
        updatedAt: _toDateTime(json['updated_at']) ?? DateTime.now(),
      );

  PurchaseOrderItem _orderItemFromJson(Map<String, dynamic> json) => PurchaseOrderItem(
        id: json['id']?.toString(),
        productId: json['product_id'].toString(),
        productName: json['product_name']?.toString() ?? 'Producto',
        productSku: json['product_sku']?.toString(),
        quantity: _toInt(json['quantity_ordered']),
        unitCostMxn: _toDouble(json['unit_cost_mxn']),
        quantityReceived: _toInt(json['quantity_received']),
        lotNumber: json['lot_number']?.toString(),
        expiryDate: _toDateTime(json['expiry_date']),
      );

  PurchaseOrder _orderFromJson(Map<String, dynamic> json) => PurchaseOrder(
        id: json['id'].toString(),
        folio: json['folio']?.toString() ?? '',
        supplierId: json['supplier_id'].toString(),
        supplierName: json['supplier_name']?.toString() ?? '',
        supplierRfc: json['supplier_rfc']?.toString(),
        warehouseId: json['warehouse_id']?.toString(),
        warehouseName: json['warehouse_name']?.toString(),
        status: PurchaseOrderStatus.fromApi(json['status']?.toString() ?? 'CONFIRMED'),
        items: ((json['items'] as List?) ?? const [])
            .map((i) => _orderItemFromJson(i as Map<String, dynamic>))
            .toList(),
        subtotalMxn: _toDouble(json['subtotal_mxn']),
        taxMxn: _toDouble(json['tax_mxn']),
        totalMxn: _toDouble(json['total_mxn']),
        expectedDeliveryDate: _toDateTime(json['expected_delivery_date']),
        receivedDate: _toDateTime(json['received_date']),
        invoiceReference: json['invoice_reference']?.toString(),
        notes: json['notes']?.toString(),
        createdByUserId: json['created_by_user_id']?.toString(),
        createdAt: _toDateTime(json['created_at']) ?? DateTime.now(),
      );

  AccountPayable _payableFromJson(Map<String, dynamic> json) => AccountPayable(
        id: json['id'].toString(),
        supplierId: json['supplier_id'].toString(),
        supplierName: json['supplier_name']?.toString() ?? '',
        purchaseOrderId: json['purchase_order_id']?.toString(),
        folio: json['folio']?.toString(),
        originalAmountMxn: _toDouble(json['total_mxn']),
        paidAmountMxn: _toDouble(json['amount_paid_mxn']),
        status: AccountPayableStatus.fromApi(json['status']?.toString() ?? 'PENDING'),
        invoiceReference: json['invoice_reference']?.toString(),
        notes: json['notes']?.toString(),
        dueDate: _toDateTime(json['due_date']) ?? DateTime.now(),
        createdAt: _toDateTime(json['created_at']) ?? DateTime.now(),
        updatedAt: _toDateTime(json['updated_at']) ?? DateTime.now(),
      );

  Exception _mapDioError(DioException e) {
    final data = e.response?.data;
    if (data is Map && data['detail'] != null) {
      return PurchasesException(data['detail'].toString());
    }
    return PurchasesException('Error de conexión con el servidor: ${e.message}');
  }

  // ── Proveedores ──────────────────────────────────────────────────────────

  @override
  Future<List<Supplier>> listSuppliers({String? search}) async {
    try {
      final response = await client.get<dynamic>(
        '/api/v1/suppliers',
        queryParameters: {if (search != null && search.isNotEmpty) 'search': search},
      );
      final data = response.data;
      if (data is! List) return const [];
      return data.map((j) => _supplierFromJson(j as Map<String, dynamic>)).toList();
    } on DioException catch (e) {
      throw _mapDioError(e);
    }
  }

  @override
  Future<Supplier> createSupplier({
    required String name,
    String? phone,
    String? email,
    String? rfc,
    String? address,
    int? creditDays,
    double? creditLimitMxn,
    String? notes,
  }) async {
    try {
      final response = await client.post<dynamic>(
        '/api/v1/suppliers',
        data: {
          'name': name,
          if (phone != null) 'phone': phone,
          if (email != null) 'email': email,
          if (rfc != null) 'rfc': rfc,
          if (address != null) 'address': address,
          if (creditDays != null) 'credit_days': creditDays,
          if (creditLimitMxn != null) 'credit_limit_mxn': creditLimitMxn,
          if (notes != null) 'notes': notes,
        },
      );
      return _supplierFromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw _mapDioError(e);
    }
  }

  @override
  Future<Supplier> updateSupplier({
    required String id,
    String? name,
    String? phone,
    String? email,
    String? rfc,
    String? address,
    int? creditDays,
    double? creditLimitMxn,
    String? notes,
  }) async {
    try {
      final response = await client.put<dynamic>(
        '/api/v1/suppliers/$id',
        data: {
          if (name != null) 'name': name,
          if (phone != null) 'phone': phone,
          if (email != null) 'email': email,
          if (rfc != null) 'rfc': rfc,
          if (address != null) 'address': address,
          if (creditDays != null) 'credit_days': creditDays,
          if (creditLimitMxn != null) 'credit_limit_mxn': creditLimitMxn,
          if (notes != null) 'notes': notes,
        },
      );
      return _supplierFromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw _mapDioError(e);
    }
  }

  @override
  Future<void> deactivateSupplier(String id) async {
    try {
      await client.delete<dynamic>('/api/v1/suppliers/$id');
    } on DioException catch (e) {
      if (e.response?.statusCode == 422) {
        final data = e.response?.data;
        final detail = data is Map ? data['detail']?.toString() ?? '' : '';
        // El backend no siempre expone el conteo exacto de órdenes activas
        // en un campo estructurado — se extrae del mensaje si viene, o se
        // usa 1 como mínimo garantizado (el 422 no se dispara con 0).
        final match = RegExp(r'(\d+)').firstMatch(detail);
        final count = match != null ? int.tryParse(match.group(1)!) ?? 1 : 1;
        throw SupplierHasActiveOrdersException(count);
      }
      throw _mapDioError(e);
    }
  }

  // ── Órdenes de compra ────────────────────────────────────────────────────

  @override
  Future<List<PurchaseOrder>> listPurchaseOrders({
    String? search,
    DateTime? dateFrom,
    DateTime? dateTo,
  }) async {
    try {
      final response = await client.get<dynamic>('/api/v1/purchase-orders', queryParameters: {
        'limit': 200,
      });
      final data = response.data;
      if (data is! List) return const [];
      var orders = data.map((j) => _orderFromJson(j as Map<String, dynamic>)).toList();

      // El backend no expone `search` de texto libre para órdenes — se
      // filtra en cliente, igual que ya hacía el mock.
      if (search != null && search.isNotEmpty) {
        final q = search.toLowerCase();
        orders = orders
            .where((o) =>
                o.folio.toLowerCase().contains(q) ||
                o.supplierName.toLowerCase().contains(q) ||
                o.id.toLowerCase().contains(q))
            .toList();
      }
      if (dateFrom != null) {
        final from = DateTime(dateFrom.year, dateFrom.month, dateFrom.day);
        orders = orders.where((o) => !o.createdAt.isBefore(from)).toList();
      }
      if (dateTo != null) {
        final to = DateTime(dateTo.year, dateTo.month, dateTo.day, 23, 59, 59);
        orders = orders.where((o) => !o.createdAt.isAfter(to)).toList();
      }
      orders.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return orders;
    } on DioException catch (e) {
      throw _mapDioError(e);
    }
  }

  @override
  Future<PurchaseOrder> createPurchaseOrder({
    required String supplierId,
    required List<PurchaseOrderItem> items,
    String? warehouseId,
    DateTime? expectedDeliveryDate,
    String? notes,
  }) async {
    try {
      final response = await client.post<dynamic>(
        '/api/v1/purchase-orders',
        data: {
          'supplier_id': supplierId,
          if (warehouseId != null) 'warehouse_id': warehouseId,
          'items': items
              .map((i) => {
                    'product_id': i.productId,
                    'quantity_ordered': i.quantity,
                    'unit_cost_mxn': i.unitCostMxn,
                  })
              .toList(),
          if (expectedDeliveryDate != null)
            'expected_delivery_date': expectedDeliveryDate.toIso8601String().split('T').first,
          if (notes != null) 'notes': notes,
        },
      );
      return _orderFromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw _mapDioError(e);
    }
  }

  @override
  Future<PurchaseOrder> updatePurchaseOrder({
    required String purchaseOrderId,
    String? supplierId,
    List<PurchaseOrderItem>? items,
    DateTime? expectedDeliveryDate,
    String? notes,
  }) async {
    try {
      final response = await client.put<dynamic>(
        '/api/v1/purchase-orders/$purchaseOrderId',
        data: {
          if (supplierId != null) 'supplier_id': supplierId,
          if (items != null)
            'items': items
                .map((i) => {
                      'product_id': i.productId,
                      'quantity_ordered': i.quantity,
                      'unit_cost_mxn': i.unitCostMxn,
                    })
                .toList(),
          if (expectedDeliveryDate != null)
            'expected_delivery_date':
                expectedDeliveryDate.toIso8601String().split('T').first,
          if (notes != null) 'notes': notes,
        },
      );
      return _orderFromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw _mapOrderLockedError(e, 'editar');
    }
  }

  @override
  Future<PurchaseOrder> cancelPurchaseOrder({
    required String purchaseOrderId,
    String? reason,
  }) async {
    try {
      final response = await client.post<dynamic>(
        '/api/v1/purchase-orders/$purchaseOrderId/cancel',
        data: {if (reason != null) 'reason': reason},
      );
      return _orderFromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw _mapOrderLockedError(e, 'cancelar');
    }
  }

  /// El 422 de "la orden ya recibió mercancía" trae un mensaje listo para
  /// mostrarse; se respeta en vez de inventar uno propio en la UI.
  Exception _mapOrderLockedError(DioException e, String action) {
    if (e.response?.statusCode == 422) {
      final data = e.response?.data;
      final detail = data is Map ? data['detail']?.toString() : null;
      return PurchasesException(
        detail ?? 'Esta orden ya no se puede $action.',
      );
    }
    return _mapDioError(e);
  }

  /// A diferencia del mock (que recibe la lista completa con cantidades ya
  /// acumuladas), el backend real espera sólo el **delta** recepcionado por
  /// renglón (`items_received`, referenciando `purchase_order_item_id`). Se
  /// pide la orden actual primero para calcular ese delta contra la verdad
  /// del servidor, no contra lo que traía [updatedItems] al entrar aquí.
  @override
  Future<PurchaseOrder> receivePurchaseOrder({
    required String purchaseOrderId,
    required List<PurchaseOrderItem> updatedItems,
    String? invoiceReference,
    String? notes,
  }) async {
    try {
      final currentResponse = await client.get<dynamic>('/api/v1/purchase-orders/$purchaseOrderId');
      final current = _orderFromJson(currentResponse.data as Map<String, dynamic>);
      final currentById = {for (final i in current.items) i.id: i};

      final itemsReceived = <Map<String, dynamic>>[];
      for (final updated in updatedItems) {
        final before = currentById[updated.id];
        if (before == null) continue;
        final delta = updated.quantityReceived - before.quantityReceived;
        if (delta <= 0) continue;
        itemsReceived.add({
          'purchase_order_item_id': updated.id,
          'quantity_received': delta,
        });
      }

      if (itemsReceived.isEmpty) {
        throw const PurchasesException('No hay unidades nuevas por recepcionar.');
      }

      final response = await client.post<dynamic>(
        '/api/v1/purchase-orders/$purchaseOrderId/receive',
        data: {
          'items_received': itemsReceived,
          if (invoiceReference != null) 'invoice_reference': invoiceReference,
          if (notes != null) 'notes': notes,
        },
      );
      final data = response.data as Map<String, dynamic>;
      return _orderFromJson(data['purchase_order'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw _mapDioError(e);
    }
  }

  // ── Cuentas por pagar ────────────────────────────────────────────────────

  @override
  Future<AccountsPayableResult> listAccountsPayable({bool overdueOnly = false}) async {
    try {
      final results = await Future.wait([
        client.get<dynamic>('/api/v1/accounts-payable', queryParameters: {
          'limit': 200,
          if (overdueOnly) 'overdue_only': true,
        }),
        client.get<dynamic>('/api/v1/accounts-payable/summary'),
      ]);

      final itemsData = results[0].data;
      final items = itemsData is List
          ? itemsData.map((j) => _payableFromJson(j as Map<String, dynamic>)).toList()
          : <AccountPayable>[];
      items.sort((a, b) => a.dueDate.compareTo(b.dueDate));

      final summaryData = results[1].data as Map<String, dynamic>;
      final summary = AccountsPayableSummary(
        totalPendingMxn: _toDouble(summaryData['total_pending_mxn']),
        totalPaidMxn: _toDouble(summaryData['total_paid_mxn']),
        overdueAmountMxn: _toDouble(summaryData['overdue_amount_mxn']),
        overdueCount: _toInt(summaryData['overdue_count']),
        pendingCount: _toInt(summaryData['pending_count']),
      );

      return AccountsPayableResult(items: items, summary: summary);
    } on DioException catch (e) {
      throw _mapDioError(e);
    }
  }

  @override
  Future<AccountPayable> payAccountPayable({
    required String accountPayableId,
    required double amountPaidMxn,
    required SupplierPaymentMethod paymentMethod,
    String? reference,
    String? notes,
  }) async {
    try {
      await client.post<dynamic>(
        '/api/v1/accounts-payable/$accountPayableId/pay',
        data: {
          'amount_paid_mxn': amountPaidMxn,
          'payment_method': paymentMethod.apiValue,
          if (reference != null) 'reference_code': reference,
          if (notes != null) 'notes': notes,
        },
      );
      // El endpoint de pago retorna `SupplierPaymentResponse` (el abono), no
      // la cuenta por pagar completa — se vuelve a pedir para tener el
      // objeto consistente con el resto del repositorio.
      final response = await client.get<dynamic>('/api/v1/accounts-payable/$accountPayableId');
      return _payableFromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw _mapDioError(e);
    }
  }

  // ── OCR de facturas ──────────────────────────────────────────────────────

  /// Se mantiene 100% local con `ReceiptLineParser` — decisión explícita de
  /// alcance (Sep 2026): el backend real (`POST /purchases/parse-receipt`)
  /// espera `raw_text` en un formato distinto (un solo string, no filas ya
  /// tabuladas) y hace emparejamiento contra catálogo, lo que además choca
  /// con el problema abierto de "Nueva orden de compra" (sección de arriba:
  /// los renglones necesitan un `product_id` real del catálogo, no sólo un
  /// nombre libre). Conectar OCR/dictado al backend queda para cuando eso
  /// se resuelva.
  @override
  Future<ReceiptParseResult> parseReceiptRows(List<String> rows) async {
    return const ReceiptLineParser().parseRows(rows);
  }
}

// ---------------------------------------------------------------------------
// Mock — usado en tests y mientras se resuelve la selección de producto real
// en "Nueva orden de compra" (ver nota de alcance arriba)
// ---------------------------------------------------------------------------

class PurchasesRepositoryMock implements PurchasesRepository {
  static const _fakeDelay = Duration(milliseconds: 500);

  static int _supplierCounter = 0;
  static int _orderCounter = 0;

  /// Semilla en memoria — generada una sola vez por instancia del mock,
  /// igual que `CashRepositoryMock._movementsBySession`.
  late final List<Supplier> _suppliers = _seedSuppliers();
  late final List<PurchaseOrder> _orders = _seedOrders();
  late final List<AccountPayable> _payables = _seedPayables();

  // ── Proveedores ──────────────────────────────────────────────────────────

  @override
  Future<List<Supplier>> listSuppliers({String? search}) async {
    await Future.delayed(_fakeDelay);
    if (search == null || search.isEmpty) return List.unmodifiable(_suppliers);

    final q = search.toLowerCase();
    return _suppliers
        .where((s) =>
            s.name.toLowerCase().contains(q) ||
            (s.rfc?.toLowerCase().contains(q) ?? false) ||
            s.id.toLowerCase().contains(q))
        .toList();
  }

  @override
  Future<Supplier> createSupplier({
    required String name,
    String? phone,
    String? email,
    String? rfc,
    String? address,
    int? creditDays,
    double? creditLimitMxn,
    String? notes,
  }) async {
    await Future.delayed(_fakeDelay);

    final now = DateTime.now();
    final supplier = Supplier(
      id: 'sup-${(++_supplierCounter).toString().padLeft(3, '0')}-new',
      name: name,
      phone: phone,
      email: email,
      rfc: rfc,
      address: address,
      creditDays: creditDays ?? 0,
      creditLimitMxn: creditLimitMxn ?? 0,
      status: SupplierStatus.active,
      notes: notes,
      createdAt: now,
      updatedAt: now,
    );
    _suppliers.insert(0, supplier);
    return supplier;
  }

  @override
  Future<Supplier> updateSupplier({
    required String id,
    String? name,
    String? phone,
    String? email,
    String? rfc,
    String? address,
    int? creditDays,
    double? creditLimitMxn,
    String? notes,
  }) async {
    await Future.delayed(_fakeDelay);
    final index = _suppliers.indexWhere((s) => s.id == id);
    if (index < 0) throw Exception('Proveedor no encontrado: $id');
    final current = _suppliers[index];
    final updated = current.copyWith(
      name: name,
      phone: phone,
      email: email,
      rfc: rfc,
      address: address,
      creditDays: creditDays,
      creditLimitMxn: creditLimitMxn,
      notes: notes,
    );
    _suppliers[index] = updated;
    return updated;
  }

  @override
  Future<void> deactivateSupplier(String id) async {
    await Future.delayed(_fakeDelay);
    final active = _orders.where((o) => o.supplierId == id && o.status.isPending).length;
    if (active > 0) throw SupplierHasActiveOrdersException(active);
    _suppliers.removeWhere((s) => s.id == id);
  }

  // ── Órdenes de compra ────────────────────────────────────────────────────

  @override
  Future<List<PurchaseOrder>> listPurchaseOrders({
    String? search,
    DateTime? dateFrom,
    DateTime? dateTo,
  }) async {
    await Future.delayed(_fakeDelay);

    var filtered = _orders
        .where((o) =>
            o.status != PurchaseOrderStatus.draft &&
            o.status != PurchaseOrderStatus.cancelled)
        .toList();

    if (search != null && search.isNotEmpty) {
      final q = search.toLowerCase();
      filtered = filtered
          .where((o) =>
              o.folio.toLowerCase().contains(q) ||
              o.supplierName.toLowerCase().contains(q) ||
              o.id.toLowerCase().contains(q))
          .toList();
    }

    if (dateFrom != null) {
      filtered = filtered
          .where((o) => !o.createdAt.isBefore(
                DateTime(dateFrom.year, dateFrom.month, dateFrom.day),
              ))
          .toList();
    }
    if (dateTo != null) {
      final endOfDay =
          DateTime(dateTo.year, dateTo.month, dateTo.day, 23, 59, 59);
      filtered = filtered.where((o) => !o.createdAt.isAfter(endOfDay)).toList();
    }

    filtered.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return filtered;
  }

  @override
  Future<PurchaseOrder> createPurchaseOrder({
    required String supplierId,
    required List<PurchaseOrderItem> items,
    String? warehouseId,
    DateTime? expectedDeliveryDate,
    String? notes,
  }) async {
    await Future.delayed(_fakeDelay);

    final supplier = _suppliers.firstWhere(
      (s) => s.id == supplierId,
      orElse: () => throw Exception('Proveedor no encontrado: $supplierId'),
    );

    // El backend real asigna un `id` de renglón al crear — el mock hace lo
    // mismo para que `receivePurchaseOrder` pueda referenciarlos.
    final itemsWithIds = [
      for (final item in items) item.copyWith(id: 'poi-${item.productId}'),
    ];
    final subtotal = itemsWithIds.fold<double>(0, (sum, i) => sum + i.subtotalMxn);

    final order = PurchaseOrder(
      id: 'po-${(++_orderCounter).toString().padLeft(3, '0')}-new',
      folio: 'OC-2026-${(100 + _orderCounter).toString().padLeft(6, '0')}',
      supplierId: supplier.id,
      supplierName: supplier.name,
      warehouseId: warehouseId,
      // El backend real crea toda orden nueva ya en CONFIRMED (RF-15).
      status: PurchaseOrderStatus.confirmed,
      items: itemsWithIds,
      subtotalMxn: subtotal,
      taxMxn: 0,
      totalMxn: subtotal,
      expectedDeliveryDate: expectedDeliveryDate,
      notes: notes,
      createdAt: DateTime.now(),
    );
    _orders.insert(0, order);
    return order;
  }

  /// Espeja la guarda del backend real: una orden que ya recibió mercancía no
  /// se edita ni se cancela, porque el stock y la CxP ya existen.
  PurchaseOrder _orderOpenForChanges(String id, String action) {
    final index = _orders.indexWhere((o) => o.id == id);
    if (index < 0) throw PurchasesException('Orden no encontrada: $id');
    final order = _orders[index];
    if (order.status == PurchaseOrderStatus.cancelled) {
      throw const PurchasesException('La orden ya está cancelada.');
    }
    final received = order.items.fold<int>(0, (s, i) => s + i.quantityReceived);
    if (received > 0 ||
        order.status == PurchaseOrderStatus.received ||
        order.status == PurchaseOrderStatus.partiallyReceived) {
      throw PurchasesException(
        'Esta orden ya recibió mercancía, así que no se puede $action. '
        'El stock y la cuenta por pagar ya existen.',
      );
    }
    return order;
  }

  @override
  Future<PurchaseOrder> updatePurchaseOrder({
    required String purchaseOrderId,
    String? supplierId,
    List<PurchaseOrderItem>? items,
    DateTime? expectedDeliveryDate,
    String? notes,
  }) async {
    await Future.delayed(_fakeDelay);
    final current = _orderOpenForChanges(purchaseOrderId, 'editar');

    final supplier = supplierId == null
        ? null
        : _suppliers.firstWhere(
            (s) => s.id == supplierId,
            orElse: () => throw PurchasesException(
                'Proveedor no encontrado: $supplierId'),
          );

    final newItems = items == null
        ? current.items
        : [for (final i in items) i.copyWith(id: 'poi-${i.productId}')];
    final subtotal = newItems.fold<double>(0, (sum, i) => sum + i.subtotalMxn);

    final updated = PurchaseOrder(
      id: current.id,
      folio: current.folio,
      supplierId: supplier?.id ?? current.supplierId,
      supplierName: supplier?.name ?? current.supplierName,
      supplierRfc: current.supplierRfc,
      warehouseId: current.warehouseId,
      warehouseName: current.warehouseName,
      status: current.status,
      items: newItems,
      subtotalMxn: subtotal,
      taxMxn: 0,
      totalMxn: subtotal,
      expectedDeliveryDate: expectedDeliveryDate ?? current.expectedDeliveryDate,
      receivedDate: current.receivedDate,
      invoiceReference: current.invoiceReference,
      notes: notes ?? current.notes,
      createdByUserId: current.createdByUserId,
      createdAt: current.createdAt,
    );
    _orders[_orders.indexWhere((o) => o.id == purchaseOrderId)] = updated;
    return updated;
  }

  @override
  Future<PurchaseOrder> cancelPurchaseOrder({
    required String purchaseOrderId,
    String? reason,
  }) async {
    await Future.delayed(_fakeDelay);
    final current = _orderOpenForChanges(purchaseOrderId, 'cancelar');

    final motive = reason == null ? null : 'Cancelada: $reason';
    final cancelled = PurchaseOrder(
      id: current.id,
      folio: current.folio,
      supplierId: current.supplierId,
      supplierName: current.supplierName,
      supplierRfc: current.supplierRfc,
      warehouseId: current.warehouseId,
      warehouseName: current.warehouseName,
      status: PurchaseOrderStatus.cancelled,
      items: current.items,
      subtotalMxn: current.subtotalMxn,
      taxMxn: current.taxMxn,
      totalMxn: current.totalMxn,
      expectedDeliveryDate: current.expectedDeliveryDate,
      receivedDate: current.receivedDate,
      invoiceReference: current.invoiceReference,
      notes: [current.notes, motive].whereType<String>().join(' | '),
      createdByUserId: current.createdByUserId,
      createdAt: current.createdAt,
    );
    _orders[_orders.indexWhere((o) => o.id == purchaseOrderId)] = cancelled;
    return cancelled;
  }

  @override
  Future<PurchaseOrder> receivePurchaseOrder({
    required String purchaseOrderId,
    required List<PurchaseOrderItem> updatedItems,
    String? invoiceReference,
    String? notes,
  }) async {
    await Future.delayed(_fakeDelay);

    final index = _orders.indexWhere((o) => o.id == purchaseOrderId);
    if (index == -1) {
      throw Exception('Orden de compra no encontrada: $purchaseOrderId');
    }

    final original = _orders[index];
    final allReceived = updatedItems.every((i) => i.isFullyReceived);
    final anyReceived = updatedItems.any((i) => i.quantityReceived > 0);

    final updated = original.copyWith(
      items: updatedItems,
      status: allReceived
          ? PurchaseOrderStatus.received
          : (anyReceived
              ? PurchaseOrderStatus.partiallyReceived
              : original.status),
      receivedDate: allReceived ? DateTime.now() : original.receivedDate,
    );
    _orders[index] = updated;

    // Genera cuenta por pagar si procede (toda recepción real genera una,
    // aunque el proveedor no dé crédito — ver `receive_purchase_order` del
    // backend: `due_date = received_date + credit_days`, y `credit_days` 0
    // simplemente vence el mismo día).
    if (anyReceived && !_payables.any((p) => p.purchaseOrderId == updated.id)) {
      final supplier = _suppliers.firstWhere(
        (s) => s.id == updated.supplierId,
        orElse: () => throw Exception('Proveedor no encontrado: ${updated.supplierId}'),
      );
      final now = DateTime.now();
      _payables.add(AccountPayable(
        id: 'ap-${updated.id}',
        supplierId: updated.supplierId,
        supplierName: updated.supplierName,
        purchaseOrderId: updated.id,
        folio: 'CXP-${updated.folio}',
        originalAmountMxn: updated.totalMxn,
        paidAmountMxn: 0,
        status: AccountPayableStatus.pending,
        dueDate: now.add(Duration(days: supplier.creditDays)),
        createdAt: now,
        updatedAt: now,
      ));
    }

    return updated;
  }

  // ── Cuentas por pagar ────────────────────────────────────────────────────

  @override
  Future<AccountsPayableResult> listAccountsPayable({
    bool overdueOnly = false,
  }) async {
    await Future.delayed(_fakeDelay);

    var items = List<AccountPayable>.from(_payables)
      ..removeWhere((p) => p.status == AccountPayableStatus.paid);

    if (overdueOnly) {
      items = items.where((p) => p.urgency == PayableUrgency.overdue).toList();
    }

    items.sort((a, b) => a.dueDate.compareTo(b.dueDate));

    final totalPending =
        items.fold<double>(0, (sum, p) => sum + p.balanceMxn);
    final totalPaid =
        _payables.fold<double>(0, (sum, p) => sum + p.paidAmountMxn);
    final overdueItems =
        items.where((p) => p.urgency == PayableUrgency.overdue);
    final overdueAmount =
        overdueItems.fold<double>(0, (sum, p) => sum + p.balanceMxn);

    return AccountsPayableResult(
      items: items,
      summary: AccountsPayableSummary(
        totalPendingMxn: totalPending,
        totalPaidMxn: totalPaid,
        overdueAmountMxn: overdueAmount,
        overdueCount: overdueItems.length,
        pendingCount: items.length,
      ),
    );
  }

  @override
  Future<AccountPayable> payAccountPayable({
    required String accountPayableId,
    required double amountPaidMxn,
    required SupplierPaymentMethod paymentMethod,
    String? reference,
    String? notes,
  }) async {
    await Future.delayed(_fakeDelay);

    final index = _payables.indexWhere((p) => p.id == accountPayableId);
    if (index == -1) {
      throw Exception('Cuenta por pagar no encontrada: $accountPayableId');
    }

    final current = _payables[index];
    final newPaid = current.paidAmountMxn + amountPaidMxn;
    final newStatus = newPaid >= current.originalAmountMxn - 0.005
        ? AccountPayableStatus.paid
        : (DateTime.now().isAfter(current.dueDate)
            ? AccountPayableStatus.overdue
            : AccountPayableStatus.partiallyPaid);

    final updated = current.copyWith(paidAmountMxn: newPaid, status: newStatus);
    _payables[index] = updated;
    return updated;
  }

  // ── OCR de facturas (Tarea 12.2) ──────────────────────────────────────────

  /// Resuelve en local con `ReceiptLineParser` mientras la Tarea 12.1 de
  /// Alan (`POST /purchases/parse-receipt`) siga `⏳ Pendiente`. Cuando el
  /// endpoint exista, solo esta implementación cambia: la UI ya consume
  /// `ReceiptParseResult`, que refleja el schema `items_detected` del YAML.
  @override
  Future<ReceiptParseResult> parseReceiptRows(List<String> rows) async {
    // Sin `_fakeDelay`: el parseo es local y la pantalla de revisión debe
    // abrir de inmediato después del OCR, no simular latencia de red.
    return const ReceiptLineParser().parseRows(rows);
  }

  // ── Semilla de datos ─────────────────────────────────────────────────────

  List<Supplier> _seedSuppliers() {
    final now = DateTime.now();
    return [
      Supplier(
        id: 'sup-001',
        name: 'Distribuidora Bimbo Norte',
        phone: '+525512345678',
        email: 'ventas@bimbonorte.mx',
        rfc: 'DBN120615AB1',
        creditDays: 30,
        status: SupplierStatus.active,
        createdAt: now.subtract(const Duration(days: 180)),
        updatedAt: now.subtract(const Duration(days: 180)),
      ),
      Supplier(
        id: 'sup-002',
        name: 'Coca-Cola FEMSA Regional',
        phone: '+525598765432',
        email: 'pedidos@femsaregional.mx',
        rfc: 'CFR140322XY2',
        creditDays: 30,
        status: SupplierStatus.active,
        createdAt: now.subtract(const Duration(days: 220)),
        updatedAt: now.subtract(const Duration(days: 220)),
      ),
      Supplier(
        id: 'sup-003',
        name: 'Sabritas / PepsiCo Norte',
        phone: '+525533221100',
        email: null,
        rfc: null,
        creditDays: 30,
        status: SupplierStatus.active,
        createdAt: now.subtract(const Duration(days: 90)),
        updatedAt: now.subtract(const Duration(days: 90)),
      ),
    ];
  }

  List<PurchaseOrder> _seedOrders() {
    final now = DateTime.now();
    PurchaseOrder order({
      required String id,
      required String folio,
      required String supplierId,
      required String supplierName,
      required PurchaseOrderStatus status,
      required List<PurchaseOrderItem> items,
      required DateTime createdAt,
      DateTime? receivedDate,
    }) {
      final subtotal = items.fold<double>(0, (sum, i) => sum + i.subtotalMxn);
      return PurchaseOrder(
        id: id,
        folio: folio,
        supplierId: supplierId,
        supplierName: supplierName,
        warehouseId: 'wh-001',
        status: status,
        items: [for (final i in items) i.copyWith(id: 'poi-$id-${i.productId}')],
        subtotalMxn: subtotal,
        taxMxn: 0,
        totalMxn: subtotal,
        createdAt: createdAt,
        receivedDate: receivedDate,
      );
    }

    return [
      order(
        id: 'po-001',
        folio: 'OC-2026-000012',
        supplierId: 'sup-001',
        supplierName: 'Distribuidora Bimbo Norte',
        status: PurchaseOrderStatus.sent,
        createdAt: now.subtract(const Duration(days: 5)),
        items: const [
          PurchaseOrderItem(
            productId: 'prod-bread-01',
            productName: 'Pan Blanco Grande',
            quantity: 40,
            unitCostMxn: 32.5,
          ),
          PurchaseOrderItem(
            productId: 'prod-bread-02',
            productName: 'Panqué Marmoleado',
            quantity: 20,
            unitCostMxn: 38,
          ),
          PurchaseOrderItem(
            productId: 'prod-bread-03',
            productName: 'Donas Glaseadas',
            quantity: 30,
            unitCostMxn: 24,
          ),
        ],
      ),
      order(
        id: 'po-002',
        folio: 'OC-2026-000013',
        supplierId: 'sup-002',
        supplierName: 'Coca-Cola FEMSA Regional',
        status: PurchaseOrderStatus.received,
        createdAt: now.subtract(const Duration(days: 10)),
        receivedDate: now.subtract(const Duration(days: 9)),
        items: const [
          PurchaseOrderItem(
            productId: 'prod-001',
            productName: 'Coca-Cola 600ml',
            quantity: 100,
            unitCostMxn: 11.5,
            quantityReceived: 100,
          ),
          PurchaseOrderItem(
            productId: 'prod-coke-2l',
            productName: 'Coca-Cola 2L',
            quantity: 50,
            unitCostMxn: 22,
            quantityReceived: 50,
          ),
        ],
      ),
      order(
        id: 'po-003',
        folio: 'OC-2026-000014',
        supplierId: 'sup-003',
        supplierName: 'Sabritas / PepsiCo Norte',
        status: PurchaseOrderStatus.partiallyReceived,
        createdAt: now.subtract(const Duration(days: 7)),
        items: const [
          PurchaseOrderItem(
            productId: 'prod-sabritas-45',
            productName: 'Sabritas Original 45g',
            quantity: 200,
            unitCostMxn: 8.5,
            quantityReceived: 150,
          ),
          PurchaseOrderItem(
            productId: 'prod-cheetos-60',
            productName: 'Cheetos 60g',
            quantity: 100,
            unitCostMxn: 9,
            quantityReceived: 50,
          ),
        ],
      ),
      order(
        id: 'po-004',
        folio: 'OC-2026-000009',
        supplierId: 'sup-001',
        supplierName: 'Distribuidora Bimbo Norte',
        status: PurchaseOrderStatus.received,
        createdAt: now.subtract(const Duration(days: 20)),
        receivedDate: now.subtract(const Duration(days: 19)),
        items: const [
          PurchaseOrderItem(
            productId: 'prod-bread-01',
            productName: 'Pan Blanco Grande',
            quantity: 60,
            unitCostMxn: 32.5,
            quantityReceived: 60,
          ),
          PurchaseOrderItem(
            productId: 'prod-bread-04',
            productName: 'Bísquets',
            quantity: 30,
            unitCostMxn: 41,
            quantityReceived: 30,
          ),
        ],
      ),
      // Recibida hace poco y aún lejos de su vencimiento — semilla del
      // semáforo verde en el tablero de CxP (a diferencia de po-001, que
      // sigue SENT y por lo tanto todavía no genera cuenta por pagar).
      order(
        id: 'po-005',
        folio: 'OC-2026-000010',
        supplierId: 'sup-002',
        supplierName: 'Coca-Cola FEMSA Regional',
        status: PurchaseOrderStatus.received,
        createdAt: now.subtract(const Duration(days: 3)),
        receivedDate: now.subtract(const Duration(days: 2)),
        items: const [
          PurchaseOrderItem(
            productId: 'prod-001',
            productName: 'Coca-Cola 600ml',
            quantity: 80,
            unitCostMxn: 11.5,
            quantityReceived: 80,
          ),
        ],
      ),
    ];
  }

  List<AccountPayable> _seedPayables() {
    final now = DateTime.now();
    return [
      // po-005 — ya recibida y lejos de vencer → semáforo verde.
      // (po-001 sigue SENT — sin recepción aún no genera cuenta por pagar,
      // ver `receivePurchaseOrder`).
      AccountPayable(
        id: 'ap-po-005',
        supplierId: 'sup-002',
        supplierName: 'Coca-Cola FEMSA Regional',
        purchaseOrderId: 'po-005',
        folio: 'CXP-OC-2026-000010',
        originalAmountMxn: 920,
        paidAmountMxn: 0,
        status: AccountPayableStatus.pending,
        dueDate: now.add(const Duration(days: 25)),
        createdAt: now.subtract(const Duration(days: 3)),
        updatedAt: now.subtract(const Duration(days: 3)),
      ),
      // po-003 — recepción parcial, vence en 3 días → semáforo amarillo.
      AccountPayable(
        id: 'ap-po-003',
        supplierId: 'sup-003',
        supplierName: 'Sabritas / PepsiCo Norte',
        purchaseOrderId: 'po-003',
        folio: 'CXP-OC-2026-000014',
        originalAmountMxn: 2600,
        paidAmountMxn: 0,
        status: AccountPayableStatus.pending,
        dueDate: now.add(const Duration(days: 3)),
        createdAt: now.subtract(const Duration(days: 7)),
        updatedAt: now.subtract(const Duration(days: 7)),
      ),
      // po-004 — ya recibida, vencida y con un abono parcial → semáforo rojo.
      AccountPayable(
        id: 'ap-po-004',
        supplierId: 'sup-001',
        supplierName: 'Distribuidora Bimbo Norte',
        purchaseOrderId: 'po-004',
        folio: 'CXP-OC-2026-000009',
        originalAmountMxn: 3180,
        paidAmountMxn: 1000,
        status: AccountPayableStatus.overdue,
        dueDate: now.subtract(const Duration(days: 5)),
        createdAt: now.subtract(const Duration(days: 20)),
        updatedAt: now.subtract(const Duration(days: 5)),
      ),
    ];
  }
}
