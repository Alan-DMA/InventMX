import 'package:equatable/equatable.dart';

/// Almacén del comercio — espejo de `WarehouseResponse`
/// (`GET /api/v1/inventory/warehouses`), sin `tenant_id` porque el tenant es
/// implícito en la sesión (RLS).
class Warehouse extends Equatable {
  const Warehouse({
    required this.id,
    required this.name,
    required this.isActive,
    required this.createdAt,
    this.isDefault = false,
  });

  final String id;
  final String name;
  final bool isActive;
  final DateTime createdAt;

  /// El principal recibe los productos nuevos y a quien no tiene almacén
  /// asignado (D7b). Siempre hay exactamente uno, y no se da de baja.
  final bool isDefault;

  Warehouse copyWith({String? name, bool? isActive, bool? isDefault}) =>
      Warehouse(
        id: id,
        name: name ?? this.name,
        isActive: isActive ?? this.isActive,
        createdAt: createdAt,
        isDefault: isDefault ?? this.isDefault,
      );

  @override
  List<Object?> get props => [id, name, isActive, createdAt, isDefault];
}

/// El comercio no puede quedarse sin ningún almacén activo: el POS y los
/// traslados necesitan al menos uno al que cargar existencias.
class LastWarehouseException implements Exception {
  const LastWarehouseException();

  String get message =>
      'Es el único almacén activo. Crea otro antes de dar este de baja.';

  @override
  String toString() => message;
}

/// El principal no se da de baja hasta elegir otro (D7b): nada cambia en
/// silencio para los productos nuevos ni para quien no tiene almacén.
class DefaultWarehouseException implements Exception {
  const DefaultWarehouseException();

  String get message =>
      'Es tu almacén principal. Marca otro como principal antes de darlo de baja.';

  @override
  String toString() => message;
}

/// Dos almacenes con el mismo nombre se vuelven indistinguibles en el
/// selector de traslados y en el de almacén operativo.
class DuplicateWarehouseNameException implements Exception {
  const DuplicateWarehouseNameException(this.name);
  final String name;

  String get message => 'Ya tienes un almacén llamado "$name".';

  @override
  String toString() => message;
}
