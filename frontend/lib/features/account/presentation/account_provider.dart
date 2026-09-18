import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/data/auth_repository.dart';
import '../../inventory/presentation/inventory_provider.dart'
    show WarehouseOption, warehousesProvider;
import '../../management/domain/tenant_role.dart';
import '../../management/domain/warehouse.dart';
import '../../management/presentation/management_provider.dart'
    hide warehousesProvider;
import '../data/account_repository.dart';
import '../data/operating_warehouse_store.dart';

/// Ya no lo usa `operatingWarehouseProvider` (ver abajo) — el almacén
/// operativo pasó a persistirse en el backend (`/auth/me`), no local, para
/// que sea el mismo en cualquier dispositivo donde el usuario inicie sesión.
/// Se deja el provider vivo porque varios tests lo sobreescriben para evitar
/// tocar Hive real; nadie más lo lee.
final operatingWarehouseStoreProvider = Provider<OperatingWarehouseStore>(
  (_) => OperatingWarehouseStoreHive(),
);

final accountRepositoryProvider = Provider<AccountRepository>(
  (_) => AccountRepositoryMock(),
);

Warehouse _toWarehouse(WarehouseOption option) => Warehouse(
      id: option.id,
      name: option.name,
      isActive: true,
      createdAt: DateTime.now(),
    );

/// Almacenes reales del comercio, para el selector de "Dónde opero" —
/// `GET /inventory/warehouses` (real), no el mock de Gestión.
final operatingWarehouseOptionsProvider =
    FutureProvider<List<Warehouse>>((ref) async {
  final options = await ref.watch(warehousesProvider.future);
  return options.map(_toWarehouse).toList();
});

/// Almacén donde opera quien usa la app.
///
/// Decisión de D6: `POST /sales/checkout` exige `warehouse_id` y vendrá
/// preseleccionado desde aquí (N-01). La lista sale de
/// `GET /inventory/warehouses` (real); la selección persiste en el backend
/// vía `/auth/me` (real) — no en Hive local, porque el usuario puede cambiar
/// su almacén operativo desde su perfil y debe verse igual en cualquier
/// dispositivo donde inicie sesión.
class OperatingWarehouseNotifier extends AsyncNotifier<Warehouse?> {
  @override
  Future<Warehouse?> build() async {
    final options = await ref.watch(warehousesProvider.future);
    if (options.isEmpty) return null;

    final savedId =
        await ref.read(authRepositoryProvider).fetchDefaultWarehouseId();
    for (final option in options) {
      if (option.id == savedId) return _toWarehouse(option);
    }

    // Sin asignación todavía (o el backend no reconoce el id guardado) —
    // cae al que el backend marca como almacén por defecto del comercio.
    final fallback = options.firstWhere(
      (o) => o.isDefault,
      orElse: () => options.first,
    );
    return _toWarehouse(fallback);
  }

  Future<void> select(Warehouse warehouse) async {
    await ref.read(authRepositoryProvider).setDefaultWarehouseId(warehouse.id);
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
