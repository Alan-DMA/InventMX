import 'package:equatable/equatable.dart';

/// Almacén del comercio — espejo de `WarehouseResponse` del backend legacy
/// (`GET /api/v1/inventory/warehouses`), sin `tenant_id` porque el tenant es
/// implícito en la sesión (RLS).
class Warehouse extends Equatable {
  const Warehouse({
    required this.id,
    required this.name,
    required this.isActive,
    required this.createdAt,
  });

  final String id;
  final String name;
  final bool isActive;
  final DateTime createdAt;

  Warehouse copyWith({String? name, bool? isActive}) => Warehouse(
        id: id,
        name: name ?? this.name,
        isActive: isActive ?? this.isActive,
        createdAt: createdAt,
      );

  @override
  List<Object?> get props => [id, name, isActive, createdAt];
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

/// Dos almacenes con el mismo nombre se vuelven indistinguibles en el
/// selector de traslados y en el de almacén operativo.
class DuplicateWarehouseNameException implements Exception {
  const DuplicateWarehouseNameException(this.name);
  final String name;

  String get message => 'Ya tienes un almacén llamado "$name".';

  @override
  String toString() => message;
}
