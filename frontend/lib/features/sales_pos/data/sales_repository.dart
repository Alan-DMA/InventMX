import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../saas_admin/presentation/saas_provider.dart' show clockProvider;
import '../domain/cart_item.dart';
import '../domain/cart_state.dart';
import '../domain/payment_entry.dart';
import '../domain/sale_summary.dart';

// ---------------------------------------------------------------------------
// Tipos del listado (Fase 2 — Kardex de ventas)
// ---------------------------------------------------------------------------

/// Filtros de `GET /sales` (docs/api/sales.yaml). Vacío = sin filtros.
///
/// [cashierName] sustituye al `cashier_id` real mientras no exista la
/// identidad contra `/saas/me` (N-04): el mock sólo conoce nombres.
class SalesQuery {
  const SalesQuery({
    this.dateFrom,
    this.dateTo,
    this.paymentKind,
    this.cashierName,
  });

  final DateTime? dateFrom;
  final DateTime? dateTo;
  final SalePaymentKind? paymentKind;
  final String? cashierName;

  bool get isEmpty =>
      dateFrom == null &&
      dateTo == null &&
      paymentKind == null &&
      cashierName == null;

  SalesQuery copyWith({
    Object? dateFrom = _keep,
    Object? dateTo = _keep,
    Object? paymentKind = _keep,
    Object? cashierName = _keep,
  }) {
    return SalesQuery(
      dateFrom:
          identical(dateFrom, _keep) ? this.dateFrom : dateFrom as DateTime?,
      dateTo: identical(dateTo, _keep) ? this.dateTo : dateTo as DateTime?,
      paymentKind: identical(paymentKind, _keep)
          ? this.paymentKind
          : paymentKind as SalePaymentKind?,
      cashierName: identical(cashierName, _keep)
          ? this.cashierName
          : cashierName as String?,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SalesQuery &&
          other.dateFrom == dateFrom &&
          other.dateTo == dateTo &&
          other.paymentKind == paymentKind &&
          other.cashierName == cashierName);

  @override
  int get hashCode => Object.hash(dateFrom, dateTo, paymentKind, cashierName);
}

const Object _keep = Object();

/// Página de ventas + agregados del recorte completo (no sólo de la página):
/// el dueño que filtra por cajero necesita saber cuántas y cuánto suman.
///
/// `total` viene de `PaginationMeta`; `totalAmountMxn` no está en el
/// contrato actual — se documenta como propuesta para Alan.
class PaginatedSales {
  const PaginatedSales({
    required this.items,
    required this.total,
    required this.totalAmountMxn,
    required this.page,
    required this.pageSize,
    required this.totalPages,
  });

  final List<SaleSummary> items;
  final int total;
  final double totalAmountMxn;
  final int page;
  final int pageSize;
  final int totalPages;
}

class SaleNotFoundException implements Exception {
  const SaleNotFoundException(this.id);
  final String id;

  @override
  String toString() => 'Venta no encontrada: $id';
}

/// Réplica del 422 de `POST /sales/{id}/refund` — una venta admite un solo
/// evento de reembolso (total o parcial), no reembolsos sucesivos.
class SaleAlreadyRefundedException implements Exception {
  const SaleAlreadyRefundedException(this.id);
  final String id;

  @override
  String toString() => 'La venta ya fue reembolsada: $id';
}

// ---------------------------------------------------------------------------
// Contrato
// ---------------------------------------------------------------------------

abstract class SalesRepository {
  /// POST /sales/checkout
  /// Procesa la venta transaccional con uno o más métodos de pago (Tarea 7.2)
  /// y retorna el resultado.
  ///
  /// [cashierName] no viaja en el request real (el backend lo deriva del
  /// JWT) — aquí se pasa solo para que el Mock pueda ecoarlo en el ticket
  /// (Tarea 8.2) mientras Alan no entrega el perfil de usuario autenticado.
  Future<CheckoutResult> checkout({
    required List<CartItem> items,
    required List<PaymentEntry> payments,
    required String cashierName,
  });

  /// GET /sales — listado paginado, más reciente primero.
  Future<PaginatedSales> getSales({
    SalesQuery query = const SalesQuery(),
    int page = 1,
    int pageSize = 20,
  });

  /// GET /sales/{id} — detalle completo (ítems y pagos) para el ticket.
  Future<CheckoutResult> getSaleById(String id);

  /// Nombres de quienes han cobrado, para el filtro por cajero.
  /// Real: `GET /users` acotado por RLS (N-04).
  Future<List<String>> getCashiers();

  /// POST /sales/{id}/refund — reembolsa una venta `COMPLETED`, total o
  /// parcial. [itemsToRefund] nulo = se reembolsa toda la venta; si se pasa,
  /// cada línea no puede exceder la cantidad original de ese ítem.
  ///
  /// Lanza [SaleNotFoundException] si el id no existe y
  /// [SaleAlreadyRefundedException] si la venta ya tiene un reembolso —
  /// réplica del 422 del contrato ("La venta no puede reembolsarse").
  Future<CheckoutResult> refundSale({
    required String saleId,
    required String reason,
    required bool refundToStock,
    List<RefundedLine>? itemsToRefund,
  });
}

// ---------------------------------------------------------------------------
// Mock — activo hasta que Alan complete Tarea 6.1 (backend POS)
// ---------------------------------------------------------------------------

class SalesRepositoryMock implements SalesRepository {
  SalesRepositoryMock({DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  static const _fakeDelay = Duration(milliseconds: 800);
  static const _listDelay = Duration(milliseconds: 400);

  final DateTime Function() _clock;

  /// Contador de folios para simular consecutivos reales.
  static int _folioCounter = 1547;

  /// Ventas completadas durante la sesión — alimenta el Mock de comisiones
  /// (Tarea 8.2.3) hasta que exista `GET /analytics/commissions` real.
  static final List<CheckoutResult> _todaysSales = [];

  static List<CheckoutResult> get todaysSales =>
      List.unmodifiable(_todaysSales);

  /// Historial semilla (los últimos 7 días), generado una vez por instancia
  /// y relativo al reloj para que en el teléfono no se vea "de hace meses".
  List<CheckoutResult>? _seed;

  @override
  Future<CheckoutResult> checkout({
    required List<CartItem> items,
    required List<PaymentEntry> payments,
    required String cashierName,
  }) async {
    await Future.delayed(_fakeDelay);

    // Calcula el total
    final total = items.fold(0.0, (sum, item) => sum + item.subtotalMxn);

    final paid = payments.fold(0.0, (sum, p) => sum + p.amountMxn);
    final change = (paid - total).clamp(0.0, double.infinity);

    _folioCounter++;
    final folio = 'NV-2026-${_folioCounter.toString().padLeft(6, '0')}';

    final result = CheckoutResult(
      saleId: 'sale-${DateTime.now().millisecondsSinceEpoch}',
      folio: folio,
      totalMxn: total,
      totalPaidMxn: paid,
      changeGivenMxn: change,
      items: items,
      payments: payments,
      cashierName: cashierName,
      completedAt: _clock(),
    );

    _todaysSales.add(result);
    return result;
  }

  // ── Listado ───────────────────────────────────────────────────────────

  @override
  Future<PaginatedSales> getSales({
    SalesQuery query = const SalesQuery(),
    int page = 1,
    int pageSize = 20,
  }) async {
    await Future.delayed(_listDelay);

    final all = _allSales().where((s) => _matches(s, query)).toList()
      ..sort((a, b) => b.completedAt.compareTo(a.completedAt));

    final total = all.length;
    final totalPages = total == 0 ? 1 : (total / pageSize).ceil();
    final start = (page - 1) * pageSize;
    final items = start >= total
        ? const <CheckoutResult>[]
        : all.sublist(start, min(start + pageSize, total));

    return PaginatedSales(
      items: items.map(SaleSummary.fromCheckout).toList(),
      total: total,
      // Neto (decisión de Eduardo, Fase 2 · reembolsos): una venta
      // reembolsada sigue en la lista, pero no infla "cuánto entró".
      totalAmountMxn: all.fold<double>(0, (a, s) => a + s.netTotalMxn),
      page: page,
      pageSize: pageSize,
      totalPages: totalPages,
    );
  }

  @override
  Future<CheckoutResult> getSaleById(String id) async {
    await Future.delayed(_listDelay);
    for (final s in _allSales()) {
      if (s.saleId == id) return s;
    }
    throw SaleNotFoundException(id);
  }

  @override
  Future<List<String>> getCashiers() async {
    final names = <String>{
      for (final s in _allSales()) s.cashierName,
    }.toList()
      ..sort();
    return names;
  }

  // ── Reembolso ────────────────────────────────────────────────────────────

  @override
  Future<CheckoutResult> refundSale({
    required String saleId,
    required String reason,
    required bool refundToStock,
    List<RefundedLine>? itemsToRefund,
  }) async {
    await Future.delayed(_fakeDelay);

    CheckoutResult? sale;
    for (final s in _allSales()) {
      if (s.saleId == saleId) {
        sale = s;
        break;
      }
    }
    if (sale == null) throw SaleNotFoundException(saleId);
    if (sale.isRefunded) throw SaleAlreadyRefundedException(saleId);

    // Sin líneas explícitas: se reembolsa toda la venta, ítem por ítem.
    final lines = itemsToRefund ??
        sale.items
            .map((i) => RefundedLine(cartItemId: i.id, quantity: i.quantity))
            .toList();

    var amount = 0.0;
    for (final line in lines) {
      final item = sale.items.firstWhere(
        (i) => i.id == line.cartItemId,
        orElse: () => throw ArgumentError(
          'El ítem ${line.cartItemId} no pertenece a la venta $saleId',
        ),
      );
      if (line.quantity <= 0 || line.quantity > item.quantity) {
        throw ArgumentError(
          'Cantidad a reembolsar inválida para "${item.name}": '
          '${line.quantity} (máximo ${item.quantity})',
        );
      }
      amount += item.unitPriceMxn * line.quantity;
    }

    final updated = sale.copyWith(
      refund: SaleRefund(
        refundedAt: _clock(),
        reason: reason,
        refundAmountMxn: amount,
        refundToStock: refundToStock,
        lines: lines,
      ),
    );
    _replaceSale(updated);
    return updated;
  }

  /// Escribe la venta actualizada de vuelta en la lista donde vive
  /// (`_seed` o `_todaysSales`) — `_allSales()` devuelve una lista nueva en
  /// cada llamada, así que reemplazar ahí no persistiría el cambio.
  void _replaceSale(CheckoutResult updated) {
    final seed = _seed;
    if (seed != null) {
      final seedIdx = seed.indexWhere((s) => s.saleId == updated.saleId);
      if (seedIdx >= 0) {
        seed[seedIdx] = updated;
        return;
      }
    }
    final todayIdx = _todaysSales.indexWhere((s) => s.saleId == updated.saleId);
    if (todayIdx >= 0) {
      _todaysSales[todayIdx] = updated;
      return;
    }
    throw SaleNotFoundException(updated.saleId);
  }

  List<CheckoutResult> _allSales() =>
      [..._seed ??= _buildSeed(), ..._todaysSales];

  bool _matches(CheckoutResult s, SalesQuery q) {
    if (q.dateFrom != null) {
      final from =
          DateTime(q.dateFrom!.year, q.dateFrom!.month, q.dateFrom!.day);
      if (s.completedAt.isBefore(from)) return false;
    }
    if (q.dateTo != null) {
      final to =
          DateTime(q.dateTo!.year, q.dateTo!.month, q.dateTo!.day, 23, 59, 59);
      if (s.completedAt.isAfter(to)) return false;
    }
    if (q.paymentKind != null &&
        SalePaymentKind.fromPayments(s.payments) != q.paymentKind) {
      return false;
    }
    if (q.cashierName != null && s.cashierName != q.cashierName) return false;
    return true;
  }

  // ── Semilla ───────────────────────────────────────────────────────────

  static const _cashiers = [
    'María Hernández',
    'José Luis Ramírez',
    'Ana Torres'
  ];

  static const _catalog = <(String, double)>[
    ('Coca-Cola 600 ml', 18.0),
    ('Sabritas Original 45 g', 17.0),
    ('Pan Bimbo Blanco Grande', 42.0),
    ('Leche Lala Entera 1 L', 27.5),
    ('Gansito Marinela', 19.0),
    ('Jabón Zote Rosa 400 g', 15.0),
    ('Huevo San Juan 12 pzas', 48.0),
    ('Tortillas 1 kg', 24.0),
    ('Agua Bonafont 1.5 L', 16.0),
    ('Papel Fabuloso 1 L', 32.0),
    ('Cigarros Marlboro 20', 78.0),
    ('Boing Mango 500 ml', 14.0),
  ];

  /// 7 días hacia atrás desde el reloj, ~6 ventas por día, folios por
  /// debajo del contador para que las de la sesión sigan siendo las últimas.
  List<CheckoutResult> _buildSeed() {
    final now = _clock();
    final rng = Random(42);
    final today = DateTime(now.year, now.month, now.day);
    final sales = <CheckoutResult>[];

    // Del día más antiguo al más reciente para que los folios crezcan con
    // el tiempo, como en un consecutivo real.
    final stamps = <DateTime>[];
    for (var back = 6; back >= 0; back--) {
      final day = today.subtract(Duration(days: back));
      final count = 5 + rng.nextInt(3);
      for (var i = 0; i < count; i++) {
        final at = day.add(Duration(
          hours: 8 + rng.nextInt(13),
          minutes: rng.nextInt(60),
        ));
        // Hoy: sólo lo que ya pasó.
        if (back == 0 && !at.isBefore(now)) continue;
        stamps.add(at);
      }
    }
    stamps.sort();

    var folio = _folioCounter - stamps.length;
    for (final at in stamps) {
      folio++;
      final lines = 1 + rng.nextInt(4);
      final items = <CartItem>[];
      for (var l = 0; l < lines; l++) {
        final (name, price) = _catalog[rng.nextInt(_catalog.length)];
        items.add(CartItem(
          id: 'ci-$folio-$l',
          productId: 'prod-${name.hashCode}',
          name: name,
          unitPriceMxn: price,
          quantity: 1 + rng.nextInt(3),
        ));
      }
      final total = items.fold<double>(0, (a, i) => a + i.subtotalMxn);
      final payments = _seedPayments(rng, folio, total);
      final paid = payments.fold<double>(0, (a, p) => a + p.amountMxn);

      sales.add(CheckoutResult(
        saleId: 'sale-seed-$folio',
        folio: 'NV-2026-${folio.toString().padLeft(6, '0')}',
        totalMxn: total,
        totalPaidMxn: paid,
        changeGivenMxn: (paid - total).clamp(0.0, double.infinity),
        items: items,
        payments: payments,
        cashierName: _cashiers[rng.nextInt(_cashiers.length)],
        completedAt: at,
      ));
    }
    return sales;
  }

  /// 65 % efectivo · 20 % tarjeta · 5 % SPEI · 5 % CoDi · 5 % mixto.
  static List<PaymentEntry> _seedPayments(Random rng, int folio, double total) {
    final roll = rng.nextInt(100);
    if (roll < 65) {
      // Paga con billete redondo y recibe cambio.
      final bill = total <= 50
          ? 50.0
          : total <= 100
              ? 100.0
              : total <= 200
                  ? 200.0
                  : (total / 100).ceil() * 100.0;
      return [
        PaymentEntry(
            id: 'pe-$folio-0',
            method: PaymentMethodMxn.cashMxn,
            amountMxn: bill),
      ];
    }
    if (roll < 85) {
      return [
        PaymentEntry(
          id: 'pe-$folio-0',
          method: PaymentMethodMxn.cardTpv,
          amountMxn: total,
          referenceCode: 'AUT-${100000 + rng.nextInt(900000)}',
        ),
      ];
    }
    if (roll < 90) {
      return [
        PaymentEntry(
          id: 'pe-$folio-0',
          method: PaymentMethodMxn.spei,
          amountMxn: total,
          referenceCode: '${1000000 + rng.nextInt(9000000)}',
        ),
      ];
    }
    if (roll < 95) {
      return [
        PaymentEntry(
          id: 'pe-$folio-0',
          method: PaymentMethodMxn.codi,
          amountMxn: total,
          referenceCode: 'CODI-${10000 + rng.nextInt(90000)}',
        ),
      ];
    }
    final card = (total / 2).floorToDouble();
    return [
      PaymentEntry(
        id: 'pe-$folio-0',
        method: PaymentMethodMxn.cardTpv,
        amountMxn: card,
        referenceCode: 'AUT-${100000 + rng.nextInt(900000)}',
      ),
      PaymentEntry(
        id: 'pe-$folio-1',
        method: PaymentMethodMxn.cashMxn,
        amountMxn: total - card,
      ),
    ];
  }
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

final salesRepositoryProvider = Provider<SalesRepository>(
  (ref) => SalesRepositoryMock(clock: ref.watch(clockProvider)),
);
