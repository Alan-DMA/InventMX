import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/inventory_repository.dart' show inventoryRepositoryProvider;
import '../domain/product.dart';

/// Búsqueda de productos **en el servidor** (`GET /inventory/products?q=`).
///
/// La lista de `inventoryProvider` sólo tiene las páginas que Inventario haya
/// cargado (20 por página): filtrarla en memoria deja fuera todo lo demás.
/// Pasó en el POS (QA de Eduardo, Sep 21: "Coco Light", "Skyrim") y en el
/// formulario de Compras (QA Sep 27). El backend busca por nombre, SKU y
/// código de barras, acotado al almacén donde opero; aquí se le pregunta a
/// él con un pequeño *debounce* para no disparar una petición por letra.
final productServerSearchProvider =
    FutureProvider.autoDispose.family<List<Product>, String>((ref, query) async {
  final q = query.trim();
  if (q.isEmpty) return const [];

  // Debounce: si el usuario sigue tecleando, este provider se desecha antes
  // de que venza el temporizador y nunca pega al backend. Es un `Timer`
  // cancelable (no `Future.delayed`) para no dejar nada pendiente al
  // desmontar el panel.
  final gate = Completer<bool>();
  final timer = Timer(const Duration(milliseconds: 250), () {
    if (!gate.isCompleted) gate.complete(true);
  });
  ref.onDispose(() {
    timer.cancel();
    if (!gate.isCompleted) gate.complete(false);
  });
  if (!await gate.future) return const [];

  final page = await ref.read(inventoryRepositoryProvider).getProducts(
        query: q,
        page: 1,
        pageSize: 20,
      );
  return page.items;
});
