import '../domain/account_payable.dart';
import '../domain/purchase_order.dart';
import '../domain/receipt_scan.dart';
import '../domain/supplier.dart';
import 'receipt_line_parser.dart';

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
    String? contactName,
    String? phone,
    String? email,
    String? rfc,
    String? notes,
  });

  /// PUT /suppliers/{id} — U-07 (C-01). Solo cambian los campos enviados.
  Future<Supplier> updateSupplier({
    required String id,
    String? name,
    String? contactName,
    String? phone,
    String? email,
    String? rfc,
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
// Mock — activo hasta que Alan complete Tarea 11.1 (backend de compras)
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
    String? contactName,
    String? phone,
    String? email,
    String? rfc,
    String? notes,
  }) async {
    await Future.delayed(_fakeDelay);

    final supplier = Supplier(
      id: 'sup-${(++_supplierCounter).toString().padLeft(3, '0')}-new',
      name: name,
      contactName: contactName,
      phone: phone,
      email: email,
      rfc: rfc,
      balanceDueMxn: 0,
      createdAt: DateTime.now(),
    );
    _suppliers.insert(0, supplier);
    return supplier;
  }

  @override
  Future<Supplier> updateSupplier({
    required String id,
    String? name,
    String? contactName,
    String? phone,
    String? email,
    String? rfc,
  }) async {
    await Future.delayed(_fakeDelay);
    final index = _suppliers.indexWhere((s) => s.id == id);
    if (index < 0) throw Exception('Proveedor no encontrado: $id');
    final current = _suppliers[index];
    final updated = Supplier(
      id: current.id,
      name: name ?? current.name,
      contactName: contactName ?? current.contactName,
      phone: phone ?? current.phone,
      email: email ?? current.email,
      rfc: rfc ?? current.rfc,
      balanceDueMxn: current.balanceDueMxn,
      createdAt: current.createdAt,
    );
    _suppliers[index] = updated;
    return updated;
  }

  @override
  Future<void> deactivateSupplier(String id) async {
    await Future.delayed(_fakeDelay);
    final active = _orders
        .where((o) =>
            o.supplierId == id &&
            (o.status == PurchaseOrderStatus.sent ||
                o.status == PurchaseOrderStatus.partialReceived))
        .length;
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

    final order = PurchaseOrder(
      id: 'po-${(++_orderCounter).toString().padLeft(3, '0')}-new',
      folio: 'OC-2026-${(100 + _orderCounter).toString().padLeft(6, '0')}',
      supplierId: supplier.id,
      supplierName: supplier.name,
      warehouseId: warehouseId,
      status: PurchaseOrderStatus.sent,
      items: items,
      isCredit: true,
      expectedDeliveryDate: expectedDeliveryDate,
      notes: notes,
      createdAt: DateTime.now(),
    );
    _orders.insert(0, order);
    return order;
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
              ? PurchaseOrderStatus.partialReceived
              : original.status),
      receivedAt: allReceived ? DateTime.now() : original.receivedAt,
    );
    _orders[index] = updated;

    // Genera cuenta por pagar si procede (orden a crédito sin CxP previa) —
    // simplificación del mock: plazo fijo de 30 días desde la recepción,
    // ya que `Supplier` no trae `credit_days` en el schema de respuesta.
    if (updated.isCredit &&
        anyReceived &&
        !_payables.any((p) => p.purchaseOrderId == updated.id)) {
      _payables.add(AccountPayable(
        id: 'ap-${updated.id}',
        supplierId: updated.supplierId,
        supplierName: updated.supplierName,
        purchaseOrderId: updated.id,
        originalAmountMxn: updated.totalMxn,
        paidAmountMxn: 0,
        dueDate: DateTime.now().add(const Duration(days: 30)),
        createdAt: DateTime.now(),
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
    final overdueItems =
        items.where((p) => p.urgency == PayableUrgency.overdue);
    final overdueAmount =
        overdueItems.fold<double>(0, (sum, p) => sum + p.balanceMxn);

    return AccountsPayableResult(
      items: items,
      summary: AccountsPayableSummary(
        totalPendingMxn: totalPending,
        overdueAmountMxn: overdueAmount,
        overdueCount: overdueItems.length,
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

    final updated = _payables[index].copyWith(
      paidAmountMxn: _payables[index].paidAmountMxn + amountPaidMxn,
    );
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
        contactName: 'Roberto Sánchez',
        phone: '+525512345678',
        email: 'ventas@bimbonorte.mx',
        rfc: 'DBN120615AB1',
        balanceDueMxn: 0,
        createdAt: now.subtract(const Duration(days: 180)),
      ),
      Supplier(
        id: 'sup-002',
        name: 'Coca-Cola FEMSA Regional',
        contactName: 'Laura Martínez',
        phone: '+525598765432',
        email: 'pedidos@femsaregional.mx',
        rfc: 'CFR140322XY2',
        balanceDueMxn: 0,
        createdAt: now.subtract(const Duration(days: 220)),
      ),
      Supplier(
        id: 'sup-003',
        name: 'Sabritas / PepsiCo Norte',
        contactName: 'Jorge Ramírez',
        phone: '+525533221100',
        email: null,
        rfc: null,
        balanceDueMxn: 0,
        createdAt: now.subtract(const Duration(days: 90)),
      ),
    ];
  }

  List<PurchaseOrder> _seedOrders() {
    final now = DateTime.now();
    return [
      PurchaseOrder(
        id: 'po-001',
        folio: 'OC-2026-000012',
        supplierId: 'sup-001',
        supplierName: 'Distribuidora Bimbo Norte',
        warehouseId: 'wh-001',
        status: PurchaseOrderStatus.sent,
        isCredit: true,
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
      PurchaseOrder(
        id: 'po-002',
        folio: 'OC-2026-000013',
        supplierId: 'sup-002',
        supplierName: 'Coca-Cola FEMSA Regional',
        warehouseId: 'wh-001',
        status: PurchaseOrderStatus.received,
        isCredit: false,
        createdAt: now.subtract(const Duration(days: 10)),
        receivedAt: now.subtract(const Duration(days: 9)),
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
      PurchaseOrder(
        id: 'po-003',
        folio: 'OC-2026-000014',
        supplierId: 'sup-003',
        supplierName: 'Sabritas / PepsiCo Norte',
        warehouseId: 'wh-001',
        status: PurchaseOrderStatus.partialReceived,
        isCredit: true,
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
      PurchaseOrder(
        id: 'po-004',
        folio: 'OC-2026-000009',
        supplierId: 'sup-001',
        supplierName: 'Distribuidora Bimbo Norte',
        warehouseId: 'wh-001',
        status: PurchaseOrderStatus.received,
        isCredit: true,
        createdAt: now.subtract(const Duration(days: 20)),
        receivedAt: now.subtract(const Duration(days: 19)),
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
      // Recibida hace poco, a crédito y aún lejos de su vencimiento — semilla
      // del semáforo verde en el tablero de CxP (a diferencia de po-001, que
      // sigue SENT y por lo tanto todavía no genera cuenta por pagar).
      PurchaseOrder(
        id: 'po-005',
        folio: 'OC-2026-000010',
        supplierId: 'sup-002',
        supplierName: 'Coca-Cola FEMSA Regional',
        warehouseId: 'wh-001',
        status: PurchaseOrderStatus.received,
        isCredit: true,
        createdAt: now.subtract(const Duration(days: 3)),
        receivedAt: now.subtract(const Duration(days: 2)),
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
      // po-005 — ya recibida, a crédito y lejos de vencer → semáforo verde.
      // (po-001 sigue SENT — sin recepción aún no genera cuenta por pagar,
      // ver `receivePurchaseOrder`).
      AccountPayable(
        id: 'ap-po-005',
        supplierId: 'sup-002',
        supplierName: 'Coca-Cola FEMSA Regional',
        purchaseOrderId: 'po-005',
        originalAmountMxn: 920,
        paidAmountMxn: 0,
        dueDate: now.add(const Duration(days: 25)),
        createdAt: now.subtract(const Duration(days: 3)),
      ),
      // po-003 — recepción parcial, vence en 3 días → semáforo amarillo.
      AccountPayable(
        id: 'ap-po-003',
        supplierId: 'sup-003',
        supplierName: 'Sabritas / PepsiCo Norte',
        purchaseOrderId: 'po-003',
        originalAmountMxn: 2600,
        paidAmountMxn: 0,
        dueDate: now.add(const Duration(days: 3)),
        createdAt: now.subtract(const Duration(days: 7)),
      ),
      // po-004 — ya recibida, vencida y con un abono parcial → semáforo rojo.
      AccountPayable(
        id: 'ap-po-004',
        supplierId: 'sup-001',
        supplierName: 'Distribuidora Bimbo Norte',
        purchaseOrderId: 'po-004',
        originalAmountMxn: 3195,
        paidAmountMxn: 1000,
        dueDate: now.subtract(const Duration(days: 5)),
        createdAt: now.subtract(const Duration(days: 20)),
      ),
    ];
  }
}
