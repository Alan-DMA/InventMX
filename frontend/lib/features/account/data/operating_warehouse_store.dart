import 'package:hive_flutter/hive_flutter.dart';

/// Recuerda en qué almacén opera este dispositivo.
///
/// Vive local (Hive) porque el backend no tiene dónde guardarlo: no existe
/// `PUT /users/{id}/warehouse` ni campo equivalente en el legacy. Cuando Alan
/// lo entregue, esto pasa a ser la caché y el servidor la fuente de verdad.
abstract interface class OperatingWarehouseStore {
  Future<String?> load();
  Future<void> save(String warehouseId);
}

/// Hive con mapa dinámico, mismo patrón que `ReceiptMappingStoreHive`.
class OperatingWarehouseStoreHive implements OperatingWarehouseStore {
  static const _boxName = 'nexus_profile';
  static const _key = 'operating_warehouse_id';

  Future<Box> get _box async => Hive.isBoxOpen(_boxName)
      ? Hive.box(_boxName)
      : await Hive.openBox(_boxName);

  @override
  Future<String?> load() async => (await _box).get(_key) as String?;

  @override
  Future<void> save(String warehouseId) async =>
      (await _box).put(_key, warehouseId);
}

/// Doble en memoria para tests — Hive necesita un directorio real.
class OperatingWarehouseStoreMemory implements OperatingWarehouseStore {
  OperatingWarehouseStoreMemory([this._warehouseId]);

  String? _warehouseId;

  @override
  Future<String?> load() async => _warehouseId;

  @override
  Future<void> save(String warehouseId) async => _warehouseId = warehouseId;
}
