import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/login_provider.dart' show currentUserNameProvider;

/// Alcance de datos de quien puede ver todos los almacenes (aislamiento por
/// almacén, D26–D28): un almacén concreto o todos (`null`).
///
/// Arranca en "Todos los almacenes" (D27) y se cambia desde la leyenda del
/// encabezado (D28). Hoy lo usa Compras (QA de Eduardo, Sep 27); en la
/// Fase 2 lo leerán Ventas, Inicio, Reportes y Caja. A quien no puede ver
/// todos no le aplica: el servidor le fija su almacén.
class DataScopeNotifier extends Notifier<String?> {
  @override
  String? build() {
    // Cada sesión arranca en "Todos": no se hereda el filtro de otra persona.
    ref.watch(currentUserNameProvider);
    return null;
  }

  void select(String? warehouseId) => state = warehouseId;
}

final dataScopeProvider =
    NotifierProvider<DataScopeNotifier, String?>(DataScopeNotifier.new);
