import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/dio_client.dart';
import '../../auth/data/auth_repository.dart';
import '../domain/cart_item.dart';
import '../domain/cart_state.dart';
import '../domain/payment_entry.dart';

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
  /// y retorna el resultado.
  Future<CheckoutResult> checkout({
    required List<CartItem> items,
    required List<PaymentEntry> payments,
    required String cashierName,
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
  }) async {
    try {
      final payload = <String, dynamic>{
        'items': items.map((item) {
          final map = <String, dynamic>{
            'name': item.name,
            'quantity': item.quantity,
            'unit_price_usd': item.unitPriceMxn,
            'unit_price_mxn': item.unitPriceMxn,
          };
          if (item.productId != null && item.productId!.isNotEmpty) {
            map['product_id'] = item.productId;
          }
          return map;
        }).toList(),
        'payments': payments.map((p) {
          final map = <String, dynamic>{
            'payment_method': p.method.apiValue,
            'amount_usd': p.amountMxn,
            'amount_mxn': p.amountMxn,
          };
          if (p.referenceCode != null && p.referenceCode!.isNotEmpty) {
            map['reference_number'] = p.referenceCode;
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

      final saleId = data['sale_id']?.toString() ??
          'sale-${DateTime.now().millisecondsSinceEpoch}';
      final folio = data['folio']?.toString() ?? 'NV-SIN-FOLIO';
      final totalMxn =
          (data['total_mxn'] ?? data['total_usd'] as num?)?.toDouble() ??
              items.fold(0.0, (sum, i) => sum + i.subtotalMxn);
      final totalPaidMxn =
          (data['total_paid_mxn'] ?? data['total_paid_usd'] as num?)?.toDouble() ??
              payments.fold(0.0, (sum, p) => sum + p.amountMxn);
      final changeGivenMxn =
          (data['change_given_mxn'] ?? data['change_given_usd'] as num?)?.toDouble() ??
              (totalPaidMxn - totalMxn).clamp(0.0, double.infinity);
      final completedAtStr = data['completed_at']?.toString();
      final completedAt = completedAtStr != null
          ? DateTime.tryParse(completedAtStr) ?? DateTime.now()
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
          return SalesException(data['error']['message'].toString());
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
}

// ---------------------------------------------------------------------------
// Mock — mantenido para tests offline o pruebas de UI
// ---------------------------------------------------------------------------

class SalesRepositoryMock implements SalesRepository {
  static const _fakeDelay = Duration(milliseconds: 800);

  /// Contador de folios para simular consecutivos reales.
  static int _folioCounter = 1547;

  /// Ventas completadas durante la sesión — alimenta el Mock de comisiones
  /// (Tarea 8.2.3) hasta que exista `GET /analytics/commissions` real.
  static final List<CheckoutResult> _todaysSales = [];

  static List<CheckoutResult> get todaysSales => List.unmodifiable(_todaysSales);

  @override
  Future<CheckoutResult> checkout({
    required List<CartItem> items,
    required List<PaymentEntry> payments,
    required String cashierName,
  }) async {
    await Future.delayed(_fakeDelay);

    // Calcula el total
    final total =
        items.fold(0.0, (sum, item) => sum + item.subtotalMxn);

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
      completedAt: DateTime.now(),
    );

    _todaysSales.add(result);
    return result;
  }
}

// ---------------------------------------------------------------------------
// Provider conectado al Repositorio Real de Ventas
// ---------------------------------------------------------------------------

final salesRepositoryProvider = Provider<SalesRepository>(
  (ref) => SalesRepositoryImpl(
    client: ref.watch(dioClientProvider),
  ),
);

