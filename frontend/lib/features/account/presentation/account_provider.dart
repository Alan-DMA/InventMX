import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../management/domain/tenant_role.dart';
import '../../management/domain/warehouse.dart';
import '../../management/presentation/management_provider.dart';
import '../data/account_repository.dart';
import '../data/operating_warehouse_store.dart';

final operatingWarehouseStoreProvider = Provider<OperatingWarehouseStore>(
  (_) => OperatingWarehouseStoreHive(),
);

final accountRepositoryProvider = Provider<AccountRepository>(
  (_) => AccountRepositoryMock(),
);

/// Almacén donde opera quien usa la app.
///
/// Decisión de D6: `POST /sales/checkout` exige `warehouse_id` y vendrá
/// preseleccionado desde aquí (N-01). Se recalcula si la lista de almacenes
/// cambia — si al que apuntaba se dio de baja, cae al primero activo en vez
/// de quedarse apuntando a un almacén muerto.
class OperatingWarehouseNotifier extends AsyncNotifier<Warehouse?> {
  @override
  Future<Warehouse?> build() async {
    final warehouses = await ref.watch(warehousesProvider.future);
    final active = warehouses.where((w) => w.isActive).toList();
    if (active.isEmpty) return null;

    final savedId = await ref.read(operatingWarehouseStoreProvider).load();
    for (final warehouse in active) {
      if (warehouse.id == savedId) return warehouse;
    }
    return active.first;
  }

  Future<void> select(Warehouse warehouse) async {
    await ref.read(operatingWarehouseStoreProvider).save(warehouse.id);
    state = AsyncData(warehouse);
  }
}

final operatingWarehouseProvider =
    AsyncNotifierProvider<OperatingWarehouseNotifier, Warehouse?>(
  OperatingWarehouseNotifier.new,
);

/// Quién puede ver cuánto paga el negocio.
///
/// Decisión de Eduardo (Sep 16): sólo el Dueño — un cajero no tiene por qué
/// enterarse de la facturación de su patrón. No existe permiso para esto en
/// `seed.py`; se propone `saas.ver_suscripcion` y mientras tanto se resuelve
/// por rol. Falso mientras carga (fail-closed).
final canSeeSubscriptionProvider = Provider<bool>((ref) {
  return ref.watch(myRoleProvider)?.id == TenantRoles.owner;
});
