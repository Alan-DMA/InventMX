import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../inventory/domain/product.dart';
import '../../inventory/data/inventory_repository.dart' show inventoryRepositoryProvider;

/// Búsqueda del POS **en el servidor** (`GET /inventory/products?q=`).
///
/// QA de Eduardo (Sep 21): "Coco Light" y "Skyrim" existen y el buscador no
/// los mostraba. El panel filtraba sólo la lista en memoria de
/// `inventoryProvider`, que carga 20 productos por página — todo lo que
/// estuviera más allá de la primera página no existía para el POS (ni
/// tecleado ni escaneado). El backend busca por nombre, SKU y código de
/// barras; aquí se le pregunta a él, con un pequeño *debounce* para no
/// disparar una petición por cada letra.
///
/// Los resultados locales siguen sirviendo como respuesta inmediata mientras
/// llega la del servidor (ver `ProductSearchResults`).
final posProductSearchProvider =
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
