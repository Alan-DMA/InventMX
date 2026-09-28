import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/data/auth_repository.dart';
import '../../auth/presentation/login_provider.dart'
    show currentUserNameProvider;
import '../../dashboard/presentation/dashboard_provider.dart'
    show dailySnapshotProvider;
import '../../inventory/presentation/inventory_provider.dart'
    show WarehouseOption, inventoryProvider, warehousesProvider;
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

/// Contraseña contra el servidor real (D9). `--dart-define=ACCOUNT_MOCK=true`
/// vuelve al mock (demos sin backend).
const bool kAccountUseMock =
    bool.fromEnvironment('ACCOUNT_MOCK', defaultValue: false);

final accountRepositoryProvider = Provider<AccountRepository>((ref) {
  if (kAccountUseMock) return AccountRepositoryMock();
  return AccountRepositoryImpl(client: ref.watch(dioClientProvider));
});

Warehouse _toWarehouse(WarehouseOption option) => Warehouse(
      id: option.id,
      name: option.name,
      isActive: true,
      isDefault: option.isDefault,
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
    // Es de quien está en sesión: al cambiar de usuario en el mismo teléfono
    // se vuelve a leer su almacén de `/auth/me`. Sin esto el siguiente usuario
    // heredaba el almacén del anterior — leyenda, consultas y cobro incluidos
    // (QA de Eduardo, Sep 26: el Almacenista veía las alertas del Dueño).
    ref.watch(currentUserNameProvider);
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
    // Lo que se ve está acotado a este almacén (aislamiento por almacén):
    // existencias, alertas del Inicio y avisos se vuelven a pedir. Se empuja
    // desde aquí en vez de que cada uno observe este provider, para no
    // arrastrar la carga de almacenes a quien sólo lee el inventario.
    // Sólo lo que ya está en uso: invalidar uno que nadie ha leído lo
    // construiría (y saldría a la red) sin que nadie lo mire.
    for (final ProviderBase<Object?> provider in [
      inventoryProvider,
      // La campana observa este resumen: se recalcula sola.
      dailySnapshotProvider,
    ]) {
      if (ref.exists(provider)) ref.invalidate(provider);
    }
  }
}

final operatingWarehouseProvider =
    AsyncNotifierProvider<OperatingWarehouseNotifier, Warehouse?>(
  OperatingWarehouseNotifier.new,
);

/// Id del almacén donde opero, para acotar consultas (aislamiento por
/// almacén). Lee primero el estado actual: justo después de
/// [OperatingWarehouseNotifier.select] —que es cuando Inventario y el Inicio
/// recargan— `operatingWarehouseProvider.future` todavía resuelve al almacén
/// anterior, y la recarga salía con él (QA de Eduardo, Sep 26). El `future`
/// queda sólo para cuando aún no hay valor.
Future<String?> readOperatingWarehouseId(Ref ref) async {
  final current = ref.read(operatingWarehouseProvider).valueOrNull;
  if (current != null) return current.id;
  return (await ref.read(operatingWarehouseProvider.future))?.id;
}

/// Margen máximo sugerido (%) del comercio — piso del "precio máximo
/// sugerido" por producto mientras no haya suficiente historial de ventas
/// (Sep 2026). Real desde el día uno (`/tenants/me/pricing-settings`),
/// aparte del resto de "Preferencias operativas" que sigue mock (Almacenes,
/// Categorías, Usuarios) — ver `management_provider.dart`.
class MaxMarginPercentNotifier extends AsyncNotifier<double> {
  @override
  Future<double> build() =>
      ref.read(authRepositoryProvider).fetchMaxMarginPercent();

  Future<void> setPercent(double percent) async {
    await ref.read(authRepositoryProvider).setMaxMarginPercent(percent);
    state = AsyncData(percent);
  }
}

final maxMarginPercentProvider =
    AsyncNotifierProvider<MaxMarginPercentNotifier, double>(
  MaxMarginPercentNotifier.new,
);

/// Quién puede ver cuánto paga el negocio.
///
/// Decisión de Eduardo (Sep 16): sólo el Dueño — un cajero no tiene por qué
/// enterarse de la facturación de su patrón. El seed tiene `settings.billing`
/// pero se lo niega incluso al Encargado, así que equivale a "es el Dueño";
/// se resuelve por rol para no depender de que el servidor lo exija. Falso
/// mientras carga (fail-closed).
final canSeeSubscriptionProvider = Provider<bool>((ref) {
  return ref.watch(isOwnerProvider);
});
