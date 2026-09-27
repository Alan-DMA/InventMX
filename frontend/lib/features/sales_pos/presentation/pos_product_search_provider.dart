import '../../inventory/presentation/product_server_search_provider.dart';

/// Búsqueda del POS en el servidor — es la búsqueda compartida de productos
/// (`productServerSearchProvider`), que nació aquí (QA de Eduardo, Sep 21) y
/// pasó a Inventario cuando Compras la necesitó (Sep 27). Se conserva el
/// nombre para el POS y sus tests.
final posProductSearchProvider = productServerSearchProvider;
