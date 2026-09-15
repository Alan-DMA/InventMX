import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/capture_frame_analyzer.dart';
import '../../../core/utils/ocr_helper.dart';
import '../../../core/utils/voice_dictation_helper.dart';
import '../data/purchases_repository.dart';
import '../data/receipt_file_source.dart';
import '../data/receipt_mapping_store.dart';
import '../data/receipt_reader.dart';
import '../domain/account_payable.dart';
import '../domain/purchase_order.dart';
import '../domain/supplier.dart';
import 'receipt_capture_screen.dart';

final purchasesRepositoryProvider = Provider<PurchasesRepository>(
  (_) => PurchasesRepositoryMock(),
);

/// Reconocedor de texto on-device — Tarea 12.2.1.
///
/// Se expone como provider para que los tests inyecten un doble: ML Kit vive
/// detrás de un canal de plataforma y no corre en `flutter test`.
final ocrTextRecognizerProvider = Provider<OcrTextRecognizer>((ref) {
  final recognizer = MlKitOcrTextRecognizer();
  ref.onDispose(recognizer.dispose);
  return recognizer;
});

/// Motor de dictado nativo — Tarea 12.2.3. Mismo motivo para el provider.
final voiceDictationServiceProvider = Provider<VoiceDictationService>((ref) {
  final service = NativeVoiceDictationService();
  ref.onDispose(service.dispose);
  return service;
});

/// Analizador de cuadros en vivo para la revisión previa de la toma —
/// Tarea 12.2.1. Mismo motivo para el provider que los dos de arriba.
final captureFrameAnalyzerProvider = Provider<CaptureFrameAnalyzer>((ref) {
  final analyzer = MlKitCaptureFrameAnalyzer();
  ref.onDispose(analyzer.dispose);
  return analyzer;
});

/// Origen de la foto de la factura — la pantalla de cámara en vivo.
final receiptPhotoSourceProvider =
    Provider<ReceiptPhotoSource>((_) => const CameraReceiptPhotoSource());

/// Origen de la factura como archivo (PDF o imagen) — Tarea 12.2, Q-03.
final receiptFileSourceProvider = Provider<ReceiptFileSource>(
  (_) => const FilePickerReceiptFileSource(),
);

/// Foto o páginas → líneas del OCR recortadas al marco y apiladas — Tarea
/// 12.2, Q-01 + Q-03. Depende del reconocedor inyectable de arriba.
final receiptReaderProvider = Provider<ReceiptReader>(
  (ref) => ReceiptReader(recognizer: ref.watch(ocrTextRecognizerProvider)),
);

/// Mapeo de columnas recordado por proveedor — Tarea 12.2 (QA OCR). Provider
/// para que los tests inyecten un doble en memoria en vez de Hive.
final receiptMappingStoreProvider =
    Provider<ReceiptMappingStore>((_) => ReceiptMappingStoreHive());

/// Sentinel para distinguir "no se pasó el argumento" de "se pasó null" en
/// los `copyWith` — mismo patrón que `InventoryState`.
const Object _keep = Object();

// ---------------------------------------------------------------------------
// Compras — Subtarea 11.2.1
// ---------------------------------------------------------------------------

/// Chip de estado del hub de Compras (Figma: Todas / Pendientes / Recibidas).
enum PurchaseChipFilter { all, pending, received }

class PurchaseOrdersState {
  const PurchaseOrdersState({
    this.orders = const [],
    this.chipFilter = PurchaseChipFilter.all,
    this.search = '',
    this.dateFrom,
    this.dateTo,
    this.isLoading = false,
    this.error,
  });

  /// Órdenes ya filtradas por búsqueda/rango de fecha (llamada al repo) —
  /// el chip de estado se aplica localmente en [visibleOrders] para que
  /// cambiar de chip sea instantáneo, sin volver a golpear el repositorio.
  final List<PurchaseOrder> orders;
  final PurchaseChipFilter chipFilter;
  final String search;
  final DateTime? dateFrom;
  final DateTime? dateTo;
  final bool isLoading;
  final String? error;

  bool get hasError => error != null;

  List<PurchaseOrder> get visibleOrders => switch (chipFilter) {
        PurchaseChipFilter.all => orders,
        PurchaseChipFilter.pending =>
          orders.where((o) => o.status.isPending).toList(),
        PurchaseChipFilter.received => orders
            .where((o) => o.status == PurchaseOrderStatus.received)
            .toList(),
      };

  int get allCount => orders.length;
  int get pendingCount => orders.where((o) => o.status.isPending).length;
  int get receivedCount =>
      orders.where((o) => o.status == PurchaseOrderStatus.received).length;

  PurchaseOrdersState copyWith({
    List<PurchaseOrder>? orders,
    PurchaseChipFilter? chipFilter,
    String? search,
    Object? dateFrom = _keep,
    Object? dateTo = _keep,
    bool? isLoading,
    Object? error = _keep,
  }) {
    return PurchaseOrdersState(
      orders: orders ?? this.orders,
      chipFilter: chipFilter ?? this.chipFilter,
      search: search ?? this.search,
      dateFrom: identical(dateFrom, _keep) ? this.dateFrom : dateFrom as DateTime?,
      dateTo: identical(dateTo, _keep) ? this.dateTo : dateTo as DateTime?,
      isLoading: isLoading ?? this.isLoading,
      error: identical(error, _keep) ? this.error : error as String?,
    );
  }
}

class PurchaseOrdersNotifier extends Notifier<PurchaseOrdersState> {
  @override
  PurchaseOrdersState build() {
    Future.microtask(_load);
    return const PurchaseOrdersState(isLoading: true);
  }

  PurchasesRepository get _repo => ref.read(purchasesRepositoryProvider);
  Timer? _debounce;

  Future<void> _load() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final orders = await _repo.listPurchaseOrders(
        search: state.search.isEmpty ? null : state.search,
        dateFrom: state.dateFrom,
        dateTo: state.dateTo,
      );
      state = state.copyWith(orders: orders, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  /// Cambia el chip Todas/Pendientes/Recibidas — filtro local, sin recarga.
  void setChipFilter(PurchaseChipFilter filter) {
    state = state.copyWith(chipFilter: filter);
  }

  /// Búsqueda por folio, proveedor o ID (ícono expandible junto al filtro).
  void setSearch(String value) {
    _debounce?.cancel();
    state = state.copyWith(search: value);
    _debounce = Timer(const Duration(milliseconds: 300), _load);
  }

  /// Rango de fechas del sheet de filtros (icono ▤ del Figma).
  void setDateRange({DateTime? from, DateTime? to}) {
    state = state.copyWith(dateFrom: from, dateTo: to);
    _load();
  }

  void clearDateRange() {
    state = state.copyWith(dateFrom: null, dateTo: null);
    _load();
  }

  Future<void> retry() => _load();

  /// Crea una orden de compra (`PurchaseCreateScreen`, 11.2.1) y la inserta
  /// al inicio de la lista sin recargar todo el hub.
  Future<PurchaseOrder> createOrder({
    required String supplierId,
    required List<PurchaseOrderItem> items,
    String? warehouseId,
    DateTime? expectedDeliveryDate,
    String? notes,
  }) async {
    final order = await _repo.createPurchaseOrder(
      supplierId: supplierId,
      items: items,
      warehouseId: warehouseId,
      expectedDeliveryDate: expectedDeliveryDate,
      notes: notes,
    );
    state = state.copyWith(orders: [order, ...state.orders]);
    return order;
  }

  /// Registra la recepción de mercancía (total o parcial) de una orden.
  Future<PurchaseOrder> receiveOrder({
    required String purchaseOrderId,
    required List<PurchaseOrderItem> updatedItems,
    String? invoiceReference,
    String? notes,
  }) async {
    final updated = await _repo.receivePurchaseOrder(
      purchaseOrderId: purchaseOrderId,
      updatedItems: updatedItems,
      invoiceReference: invoiceReference,
      notes: notes,
    );
    state = state.copyWith(
      orders:
          state.orders.map((o) => o.id == updated.id ? updated : o).toList(),
    );
    // La recepción puede generar una cuenta por pagar nueva (orden a
    // crédito) — refresca el tablero de CxP para que aparezca sin que el
    // usuario tenga que cambiar de tab y volver.
    ref.invalidate(accountsPayableProvider);
    return updated;
  }

  void cancelDebounce() => _debounce?.cancel();
}

final purchaseOrdersProvider =
    NotifierProvider<PurchaseOrdersNotifier, PurchaseOrdersState>(
  PurchaseOrdersNotifier.new,
);

// ---------------------------------------------------------------------------
// Proveedores — Subtarea 11.2.2
// ---------------------------------------------------------------------------

class SuppliersState {
  const SuppliersState({
    this.suppliers = const [],
    this.search = '',
    this.isLoading = false,
    this.error,
  });

  final List<Supplier> suppliers;
  final String search;
  final bool isLoading;
  final String? error;

  bool get hasError => error != null;

  SuppliersState copyWith({
    List<Supplier>? suppliers,
    String? search,
    bool? isLoading,
    Object? error = _keep,
  }) {
    return SuppliersState(
      suppliers: suppliers ?? this.suppliers,
      search: search ?? this.search,
      isLoading: isLoading ?? this.isLoading,
      error: identical(error, _keep) ? this.error : error as String?,
    );
  }
}

class SuppliersNotifier extends Notifier<SuppliersState> {
  @override
  SuppliersState build() {
    Future.microtask(_load);
    return const SuppliersState(isLoading: true);
  }

  PurchasesRepository get _repo => ref.read(purchasesRepositoryProvider);
  Timer? _debounce;

  Future<void> _load() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final suppliers =
          await _repo.listSuppliers(search: state.search.isEmpty ? null : state.search);
      state = state.copyWith(suppliers: suppliers, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  void setSearch(String value) {
    _debounce?.cancel();
    state = state.copyWith(search: value);
    _debounce = Timer(const Duration(milliseconds: 300), _load);
  }

  Future<void> retry() => _load();

  Future<Supplier> createSupplier({
    required String name,
    String? contactName,
    String? phone,
    String? email,
    String? rfc,
    String? notes,
  }) async {
    final supplier = await _repo.createSupplier(
      name: name,
      contactName: contactName,
      phone: phone,
      email: email,
      rfc: rfc,
      notes: notes,
    );
    state = state.copyWith(suppliers: [supplier, ...state.suppliers]);
    return supplier;
  }

  void cancelDebounce() => _debounce?.cancel();
}

final suppliersProvider = NotifierProvider<SuppliersNotifier, SuppliersState>(
  SuppliersNotifier.new,
);

// ---------------------------------------------------------------------------
// Cuentas por pagar — Subtarea 11.2.3
// ---------------------------------------------------------------------------

class AccountsPayableState {
  const AccountsPayableState({
    this.items = const [],
    this.summary,
    this.isLoading = false,
    this.error,
  });

  final List<AccountPayable> items;
  final AccountsPayableSummary? summary;
  final bool isLoading;
  final String? error;

  bool get hasError => error != null;

  AccountsPayableState copyWith({
    List<AccountPayable>? items,
    AccountsPayableSummary? summary,
    bool? isLoading,
    Object? error = _keep,
  }) {
    return AccountsPayableState(
      items: items ?? this.items,
      summary: summary ?? this.summary,
      isLoading: isLoading ?? this.isLoading,
      error: identical(error, _keep) ? this.error : error as String?,
    );
  }
}

class AccountsPayableNotifier extends Notifier<AccountsPayableState> {
  @override
  AccountsPayableState build() {
    Future.microtask(_load);
    return const AccountsPayableState(isLoading: true);
  }

  PurchasesRepository get _repo => ref.read(purchasesRepositoryProvider);

  Future<void> _load() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final result = await _repo.listAccountsPayable();
      state = state.copyWith(
        items: result.items,
        summary: result.summary,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> retry() => _load();

  /// Registra un abono — rechaza montos que excedan el saldo pendiente antes
  /// de llamar al repositorio (mismo criterio que el retiro de caja menor en
  /// `CashMovementsNotifier.addMovement`).
  Future<void> registerPayment({
    required String accountPayableId,
    required double amountPaidMxn,
    required SupplierPaymentMethod paymentMethod,
    String? reference,
    String? notes,
  }) async {
    final current = state.items.firstWhere(
      (p) => p.id == accountPayableId,
      orElse: () => throw Exception('Cuenta por pagar no encontrada.'),
    );

    if (amountPaidMxn > current.balanceMxn + 0.005) {
      throw Exception(
        'El abono de \$${amountPaidMxn.toStringAsFixed(2)} MXN excede el '
        'saldo pendiente (\$${current.balanceMxn.toStringAsFixed(2)} MXN).',
      );
    }

    final updated = await _repo.payAccountPayable(
      accountPayableId: accountPayableId,
      amountPaidMxn: amountPaidMxn,
      paymentMethod: paymentMethod,
      reference: reference,
      notes: notes,
    );

    // Una cuenta saldada por completo sale del tablero (la API solo lista
    // pendientes/parciales/vencidas — ver docs/api/purchases.yaml).
    final items = updated.status == AccountPayableStatus.paid
        ? state.items.where((p) => p.id != updated.id).toList()
        : state.items.map((p) => p.id == updated.id ? updated : p).toList();

    state = state.copyWith(items: items);
  }
}

final accountsPayableProvider =
    NotifierProvider<AccountsPayableNotifier, AccountsPayableState>(
  AccountsPayableNotifier.new,
);
