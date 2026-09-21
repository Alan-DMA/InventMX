import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/dio_client.dart';
import '../../auth/data/auth_repository.dart' show dioClientProvider;
import '../domain/cart_item.dart';
import '../domain/cart_state.dart';
import '../domain/payment_entry.dart';
import '../domain/sale_summary.dart';

/// Los montos del backend viajan como `Decimal` de Python — Pydantic los
/// serializa como string ("40.00") para no perder precisión, no como
/// número JSON. Un cast directo a `num?` truena con ese payload real
/// (mismo issue que en `cash_repository.dart`).
double? _toDouble(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}

int _toQuantity(dynamic value) => (_toDouble(value) ?? 0).round();

/// Réplica del `apiValue` de [PaymentMethodMxn] en sentido inverso —
/// el backend nunca manda un método fuera de este catálogo.
PaymentMethodMxn _paymentMethodFromApi(String value) {
  for (final m in PaymentMethodMxn.values) {
    if (m.apiValue == value) return m;
  }
  return PaymentMethodMxn.other;
}

/// El backend no persiste el motivo del reembolso como campo propio — viaja
/// concatenado en `notes` como "... [REEMBOLSO: motivo]" (ver
/// `SalesService.refund_sale`). Se extrae para no perder el dato en el detalle.
String _extractRefundReason(String? notes) {
  if (notes == null) return '';
  final match = RegExp(r'\[REEMBOLSO:\s*(.+?)\]\s*$').firstMatch(notes);
  return match?.group(1)?.trim() ?? '';
}

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
    this.refundedAmountMxn = 0,
    required this.page,
    required this.pageSize,
    required this.totalPages,
  });

  final List<SaleSummary> items;
  final int total;

  /// Suma **neta** (cobrado − devuelto) del recorte.
  final double totalAmountMxn;

  /// Cuánto se devolvió en el recorte; la franja lo muestra para explicar
  /// por qué el neto no coincide con la suma de los renglones.
  final double refundedAmountMxn;
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
// Excepción de dominio para Ventas / POS
// ---------------------------------------------------------------------------

class SalesException implements Exception {
  const SalesException(this.message);
  final String message;

  @override
  String toString() => message;
}

// ---------------------------------------------------------------------------
// Contrato
// ---------------------------------------------------------------------------

abstract class SalesRepository {
  /// POST /api/v1/sales/checkout
  /// Procesa la venta transaccional con uno o más métodos de pago (Tarea 7.2)
  /// y retorna el resultado. [warehouseId] es obligatorio en el contrato real
  /// (almacén del que se descuenta el stock) — lo resuelve quien llama desde
  /// `operatingWarehouseProvider` (decisión D6).
  Future<CheckoutResult> checkout({
    required List<CartItem> items,
    required List<PaymentEntry> payments,
    required String cashierName,
    required String warehouseId,
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
// Implementación Real (Conexión Directa a la API FastAPI / PostgreSQL)
// ---------------------------------------------------------------------------

class SalesRepositoryImpl implements SalesRepository {
  SalesRepositoryImpl({required this.client});

  final DioClient client;
  final List<CheckoutResult> _sessionSales = [];

  List<CheckoutResult> get sessionSales => List.unmodifiable(_sessionSales);

  @override
  Future<CheckoutResult> checkout({
    required List<CartItem> items,
    required List<PaymentEntry> payments,
    required String cashierName,
    required String warehouseId,
  }) async {
    try {
      final payload = <String, dynamic>{
        'warehouse_id': warehouseId,
        'items': items.map((item) {
          final map = <String, dynamic>{
            'quantity': item.quantity,
            'unit_price_mxn': item.unitPriceMxn,
          };
          if (item.productId != null && item.productId!.isNotEmpty) {
            map['product_id'] = item.productId;
          } else {
            // Producto al vuelo (Lazy Loading, RF-09) — el backend real no
            // acepta `name` suelto, necesita estos dos campos explícitos.
            map['is_on_the_fly'] = true;
            map['on_the_fly_name'] = item.name;
          }
          return map;
        }).toList(),
        'payments': payments.map((p) {
          final map = <String, dynamic>{
            'payment_method': p.method.apiValue,
            'amount_paid_mxn': p.amountMxn,
          };
          if (p.referenceCode != null && p.referenceCode!.isNotEmpty) {
            map['reference_code'] = p.referenceCode;
          }
          return map;
        }).toList(),
      };

      final response = await client.post(
        '/api/v1/sales/checkout',
        data: payload,
      );

      final dynamic data = response.data;
      if (data == null || data is! Map) {
        throw const SalesException('Respuesta inválida al procesar la venta.');
      }

      final saleId = data['id']?.toString() ??
          'sale-${DateTime.now().millisecondsSinceEpoch}';
      final folio = data['folio']?.toString() ?? 'NV-SIN-FOLIO';
      final totalMxn = _toDouble(data['total_mxn']) ??
          items.fold<double>(0.0, (sum, i) => sum + i.subtotalMxn);
      final totalPaidMxn = _toDouble(data['amount_paid_mxn']) ??
          payments.fold<double>(0.0, (sum, p) => sum + p.amountMxn);
      final changeGivenMxn = _toDouble(data['change_returned_mxn']) ??
          (totalPaidMxn - totalMxn).clamp(0.0, double.infinity);
      final createdAtStr = data['created_at']?.toString();
      final completedAt = createdAtStr != null
          ? DateTime.tryParse(createdAtStr) ?? DateTime.now()
          : DateTime.now();

      final result = CheckoutResult(
        saleId: saleId,
        folio: folio,
        totalMxn: totalMxn,
        totalPaidMxn: totalPaidMxn,
        changeGivenMxn: changeGivenMxn,
        items: List.unmodifiable(items),
        payments: List.unmodifiable(payments),
        cashierName: cashierName,
        completedAt: completedAt,
      );

      _sessionSales.add(result);
      return result;
    } on DioException catch (e) {
      throw _mapDioError(e);
    } catch (e) {
      if (e is SalesException) rethrow;
      throw SalesException('Error inesperado al procesar la venta: $e');
    }
  }

  Exception _mapDioError(DioException e) {
    if (e.response != null) {
      final data = e.response?.data;
      if (data is Map) {
        if (data['detail'] is Map && data['detail']['message'] != null) {
          return SalesException(data['detail']['message'].toString());
        }
        if (data['error'] is Map && data['error']['message'] != null) {
          // Un 422 de Pydantic trae `details: [{loc, msg}]` — sin eso el
          // mensaje "Error de validación en los datos enviados" no dice qué
          // campo falló (QA 20 sep: imposible diagnosticar desde el teléfono).
          final details = data['error']['details'];
          final fields = details is List
              ? details
                  .whereType<Map>()
                  .map((d) {
                    final loc = (d['loc'] as List?)
                            ?.where((l) => l != 'body')
                            .join('.') ??
                        '';
                    return loc.isEmpty ? '${d['msg']}' : '$loc: ${d['msg']}';
                  })
                  .join(' · ')
              : '';
          final message = data['error']['message'].toString();
          return SalesException(
              fields.isEmpty ? message : '$message ($fields)');
        }
        if (data['detail'] != null && data['detail'] is String) {
          return SalesException(data['detail'].toString());
        }
        if (data['message'] != null && data['message'] is String) {
          return SalesException(data['message'].toString());
        }
      }
    }

    switch (e.response?.statusCode) {
      case 400:
        return const SalesException(
            'Error en los datos de la venta o existencias insuficientes.');
      case 401:
        return const SalesException('Sesión expirada. Inicie sesión nuevamente.');
      case 403:
        return const SalesException(
            'No tiene permisos para procesar cobros en el TPV.');
      case 404:
        return const SalesException('Almacén o producto no encontrado.');
      case 409:
        return const SalesException(
            'Conflicto al procesar la venta. Intente de nuevo.');
      case 422:
        return const SalesException(
            'Error de validación en los productos o importes de pago.');
      case 500:
      case 502:
      case 503:
        return const SalesException(
            'Servidor no disponible. Intente más tarde.');
      default:
        if (e.type == DioExceptionType.connectionTimeout ||
            e.type == DioExceptionType.receiveTimeout ||
            e.type == DioExceptionType.connectionError) {
          return const SalesException(
              'Sin conexión con el servidor. Verifique su red.');
        }
        return SalesException('Error de red: ${e.message ?? e.type.name}');
    }
  }

  // ── Listado ───────────────────────────────────────────────────────────

  @override
  Future<PaginatedSales> getSales({
    SalesQuery query = const SalesQuery(),
    int page = 1,
    int pageSize = 20,
  }) async {
    try {
      String? cashierId;
      if (query.cashierName != null) {
        cashierId = await _resolveCashierId(query.cashierName!);
        if (cashierId == null) {
          // El nombre no corresponde a ningún empleado real — no hay nada
          // que listar (evita mostrar el recorte completo sin filtrar).
          return PaginatedSales(
            items: const [],
            total: 0,
            totalAmountMxn: 0,
            page: page,
            pageSize: pageSize,
            totalPages: 1,
          );
        }
      }

      final queryParams = <String, dynamic>{
        'skip': (page - 1) * pageSize,
        'limit': pageSize,
      };
      if (query.dateFrom != null) {
        queryParams['start_date'] = query.dateFrom!.toIso8601String();
      }
      if (query.dateTo != null) {
        final endOfDay = DateTime(query.dateTo!.year, query.dateTo!.month,
            query.dateTo!.day, 23, 59, 59);
        queryParams['end_date'] = endOfDay.toIso8601String();
      }
      if (cashierId != null) {
        queryParams['cashier_id'] = cashierId;
      }

      final response = await client.get<dynamic>(
        '/api/v1/sales',
        queryParameters: queryParams,
      );

      final list = (response.data as List).cast<Map>();
      var items = list.map(_saleSummaryFromSaleJson).toList();

      // El backend no expone un filtro `payment_method` funcional todavía
      // (docs/api/sales.yaml lo documenta, pero el endpoint real no lo
      // implementa) — se filtra en cliente sobre la página recibida. Esto
      // hace que `total`/`totalPages` puedan no cuadrar exactamente con lo
      // mostrado cuando el filtro está activo; documentado como limitación
      // conocida hasta que el backend lo soporte.
      if (query.paymentKind != null) {
        items = items.where((s) => s.paymentKind == query.paymentKind).toList();
      }

      final totalHeader = response.headers.value('x-total-count');
      final total = int.tryParse(totalHeader ?? '') ?? items.length;
      final totalPages = total == 0 ? 1 : (total / pageSize).ceil();

      return PaginatedSales(
        items: items,
        total: total,
        // Sólo de la página actual — el contrato real no expone una suma
        // agregada del recorte completo (ver docs/architecture/integrations.md).
        // Neto de devoluciones: es lo que cuadra con Reportes.
        totalAmountMxn: items.fold<double>(0, (a, s) => a + s.netTotalMxn),
        refundedAmountMxn:
            items.fold<double>(0, (a, s) => a + s.refundedAmountMxn),
        page: page,
        pageSize: pageSize,
        totalPages: totalPages,
      );
    } on DioException catch (e) {
      throw _mapDioError(e);
    }
  }

  @override
  Future<CheckoutResult> getSaleById(String id) async {
    try {
      final response = await client.get<dynamic>('/api/v1/sales/$id');
      return _checkoutResultFromSaleJson(response.data as Map);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) throw SaleNotFoundException(id);
      throw _mapDioError(e);
    }
  }

  @override
  Future<List<String>> getCashiers() async {
    try {
      final response = await client.get<dynamic>('/api/v1/users');
      final list = (response.data as List).cast<Map>();
      final names = <String>{
        for (final u in list)
          if ((u['full_name'] as String?)?.isNotEmpty ?? false) u['full_name'] as String,
      }.toList()
        ..sort();
      return names;
    } on DioException catch (e) {
      throw _mapDioError(e);
    }
  }

  /// Resuelve el nombre de cajero del filtro al `cashier_id` (UUID) real que
  /// espera `GET /sales` — el contrato real filtra por id, el Kardex por
  /// nombre (N-04, sin identidad de usuario resuelta en la UI todavía).
  /// `null` si ningún empleado del comercio tiene ese nombre.
  Future<String?> _resolveCashierId(String cashierName) async {
    final response = await client.get<dynamic>('/api/v1/users');
    final list = (response.data as List).cast<Map>();
    for (final u in list) {
      if (u['full_name'] == cashierName) return u['id']?.toString();
    }
    return null;
  }

  SaleSummary _saleSummaryFromSaleJson(Map json) {
    final createdAtStr = json['created_at']?.toString();
    final completedAt = createdAtStr != null
        ? DateTime.tryParse(createdAtStr) ?? DateTime.now()
        : DateTime.now();
    final itemsJson = (json['items'] as List?) ?? const [];
    final itemCount = itemsJson.fold<int>(
        0, (a, i) => a + _toQuantity((i as Map)['quantity']));
    final paymentsJson = (json['payments'] as List?) ?? const [];
    final payments = paymentsJson
        .map((p) => PaymentEntry(
              id: (p as Map)['id']?.toString() ?? '',
              method: _paymentMethodFromApi(p['payment_method']?.toString() ?? ''),
              amountMxn: _toDouble(p['amount_paid_mxn']) ?? 0,
              referenceCode: p['reference_code']?.toString(),
            ))
        .toList();

    return SaleSummary(
      id: json['id'].toString(),
      folio: json['folio']?.toString() ?? '',
      completedAt: completedAt,
      cashierName: json['cashier_name']?.toString() ?? 'Sin asignar',
      totalMxn: _toDouble(json['total_mxn']) ?? 0,
      itemCount: itemCount,
      paymentKind: SalePaymentKind.fromPayments(payments),
      isRefunded: json['status']?.toString() == 'REFUNDED',
      refundedAmountMxn: _toDouble(json['refunded_amount_mxn']) ?? 0,
      payments: payments,
    );
  }

  CheckoutResult _checkoutResultFromSaleJson(Map json) {
    final createdAtStr = json['created_at']?.toString();
    final completedAt = createdAtStr != null
        ? DateTime.tryParse(createdAtStr) ?? DateTime.now()
        : DateTime.now();

    final itemsJson = (json['items'] as List?) ?? const [];
    final items = itemsJson
        .map((i) => CartItem(
              id: (i as Map)['id'].toString(),
              productId: i['product_id']?.toString(),
              name: i['product_name']?.toString() ?? '',
              unitPriceMxn: _toDouble(i['unit_price_mxn']) ?? 0,
              quantity: _toQuantity(i['quantity']),
              isOnTheFly: i['is_on_the_fly'] == true,
            ))
        .toList();

    final paymentsJson = (json['payments'] as List?) ?? const [];
    final payments = paymentsJson
        .map((p) => PaymentEntry(
              id: (p as Map)['id']?.toString() ?? '',
              method: _paymentMethodFromApi(p['payment_method']?.toString() ?? ''),
              amountMxn: _toDouble(p['amount_paid_mxn']) ?? 0,
              referenceCode: p['reference_code']?.toString(),
            ))
        .toList();

    final status = json['status']?.toString();
    SaleRefund? refund;
    if (status == 'REFUNDED') {
      final updatedAtStr = json['updated_at']?.toString();
      final refundedAt = updatedAtStr != null
          ? DateTime.tryParse(updatedAtStr) ?? completedAt
          : completedAt;
      final lines = <RefundedLine>[
        for (final i in itemsJson)
          if (_toQuantity((i as Map)['refunded_quantity']) > 0)
            RefundedLine(
              cartItemId: i['id'].toString(),
              quantity: _toQuantity(i['refunded_quantity']),
            ),
      ];
      refund = SaleRefund(
        refundedAt: refundedAt,
        reason: _extractRefundReason(json['notes']?.toString()),
        refundAmountMxn: _toDouble(json['refunded_amount_mxn']) ?? 0,
        // No persistido en el backend real (sólo se usa transitoriamente
        // para decidir si se repone el Kardex) — se asume que sí regresó
        // al inventario, el caso más común.
        refundToStock: true,
        lines: lines,
      );
    }

    return CheckoutResult(
      saleId: json['id'].toString(),
      folio: json['folio']?.toString() ?? '',
      totalMxn: _toDouble(json['total_mxn']) ?? 0,
      totalPaidMxn: _toDouble(json['amount_paid_mxn']) ?? 0,
      changeGivenMxn: _toDouble(json['change_returned_mxn']) ?? 0,
      items: items,
      payments: payments,
      cashierName: json['cashier_name']?.toString() ?? 'Sin asignar',
      completedAt: completedAt,
      refund: refund,
    );
  }

  // ── Reembolso ────────────────────────────────────────────────────────────

  @override
  Future<CheckoutResult> refundSale({
    required String saleId,
    required String reason,
    required bool refundToStock,
    List<RefundedLine>? itemsToRefund,
  }) async {
    try {
      final payload = <String, dynamic>{
        'reason': reason,
        'refund_to_stock': refundToStock,
      };
      if (itemsToRefund != null) {
        payload['items'] = itemsToRefund
            .map((l) => {
                  'sale_item_id': l.cartItemId,
                  'quantity': l.quantity,
                })
            .toList();
      }

      final response = await client.post<dynamic>(
        '/api/v1/sales/$saleId/refund',
        data: payload,
      );
      return _checkoutResultFromSaleJson(response.data as Map);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) throw SaleNotFoundException(saleId);
      if (e.response?.statusCode == 422) {
        throw SaleAlreadyRefundedException(saleId);
      }
      throw _mapDioError(e);
    }
  }
}

// ---------------------------------------------------------------------------
// Mock — mantenido para tests offline o pruebas de UI
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
    // El mock no necesita almacén — no hay stock real que descontar.
    String warehouseId = 'wh-mock',
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
      refundedAmountMxn:
          all.fold<double>(0, (a, s) => a + (s.refund?.refundAmountMxn ?? 0)),
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
// Provider conectado al Repositorio Real de Ventas
// ---------------------------------------------------------------------------

// Real desde Sep 2026: los tres consumidores que leían
// `SalesRepositoryMock.todaysSales` estático directo ya se desacoplaron —
// `cash_session_provider.dart` pide `getSales()` real (cacheado por turno,
// ver `_shiftSalesProvider`), `commissions_repository.dart` ya no tiene
// clase Mock (código muerto eliminado, `CommissionsRepositoryImpl` es lo
// único que se usaba), y `analytics_dashboard_repository.dart` sólo toca el
// mock estático dentro de su propio modo mock (`ANALYTICS_MOCK`, aparte).
final salesRepositoryProvider = Provider<SalesRepository>(
  (ref) => SalesRepositoryImpl(client: ref.watch(dioClientProvider)),
);

