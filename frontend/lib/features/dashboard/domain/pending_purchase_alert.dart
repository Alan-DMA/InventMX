import 'package:equatable/equatable.dart';

/// Alerta de orden de compra pendiente de entrega o vencida para el Centro de Mando.
///
/// Refleja órdenes en estado DRAFT, SENT, CONFIRMED o PARTIALLY_RECEIVED emitidas
/// a proveedores que aún no han sido completadas en almacén.
class PendingPurchaseAlert extends Equatable {
  const PendingPurchaseAlert({
    required this.id,
    required this.folio,
    required this.supplierName,
    required this.totalMxn,
    required this.daysPending,
    required this.isOverdue,
  });

  /// Identificador único UUID de la orden de compra
  final String id;

  /// Folio legible (ej. OC-00012)
  final String folio;

  /// Razón social o nombre comercial del proveedor
  final String supplierName;

  /// Importe total comprometido en Pesos Mexicanos
  final double totalMxn;

  /// Días transcurridos desde que se emitió la orden
  final int daysPending;

  /// Verdadero si ya superó la fecha prometida de entrega
  final bool isOverdue;

  /// Construye la entidad a partir del payload JSON de la API
  factory PendingPurchaseAlert.fromJson(Map<String, dynamic> json) {
    return PendingPurchaseAlert(
      id: json['id'] as String? ?? '',
      folio: json['folio'] as String? ?? '',
      supplierName: json['supplier_name'] as String? ?? 'Proveedor',
      totalMxn: _toDouble(json['total_mxn']),
      daysPending: _toInt(json['days_pending']),
      isOverdue: json['is_overdue'] as bool? ?? false,
    );
  }

  @override
  List<Object?> get props => [
        id,
        folio,
        supplierName,
        totalMxn,
        daysPending,
        isOverdue,
      ];
}

double _toDouble(dynamic v, {double defaultValue = 0.0}) {
  if (v == null) return defaultValue;
  if (v is num) return v.toDouble();
  final s = v.toString().trim();
  return double.tryParse(s) ?? defaultValue;
}

int _toInt(dynamic v, {int defaultValue = 0}) {
  if (v == null) return defaultValue;
  if (v is num) return v.toInt();
  final s = v.toString().trim();
  return int.tryParse(s) ?? double.tryParse(s)?.toInt() ?? defaultValue;
}
