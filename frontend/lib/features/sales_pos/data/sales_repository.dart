import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/cart_item.dart';
import '../domain/cart_state.dart';
import '../domain/payment_entry.dart';

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
}

// ---------------------------------------------------------------------------
// Mock — activo hasta que Alan complete Tarea 6.1 (backend POS)
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
// Provider
// ---------------------------------------------------------------------------

final salesRepositoryProvider = Provider<SalesRepository>(
  (_) => SalesRepositoryMock(),
);
