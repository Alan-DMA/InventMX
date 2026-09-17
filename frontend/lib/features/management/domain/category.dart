import 'package:equatable/equatable.dart';

/// Categoría de productos del comercio (PD-03 / N-03).
///
/// Hoy los chips de categoría del inventario salen de los propios productos
/// (`createProduct` resuelve `category_id` por nombre). Esto les da entidad
/// propia para poder crearlas, renombrarlas y darlas de baja.
class Category extends Equatable {
  const Category({
    required this.id,
    required this.name,
    required this.productCount,
  });

  final String id;
  final String name;

  /// Cuántos productos la usan — decide si se puede eliminar y es lo que el
  /// tendero necesita ver antes de tocarla.
  final int productCount;

  Category copyWith({String? name}) => Category(
        id: id,
        name: name ?? this.name,
        productCount: productCount,
      );

  @override
  List<Object?> get props => [id, name, productCount];
}

/// No se puede eliminar una categoría que tiene productos: quedarían sueltos
/// y el tendero no sabría dónde buscarlos.
class CategoryInUseException implements Exception {
  const CategoryInUseException(this.productCount);
  final int productCount;

  String get message =>
      'Esta categoría tiene $productCount ${productCount == 1 ? 'producto' : 'productos'}. '
      'Muévelos a otra categoría antes de eliminarla.';

  @override
  String toString() => message;
}

class DuplicateCategoryNameException implements Exception {
  const DuplicateCategoryNameException(this.name);
  final String name;

  String get message => 'Ya tienes una categoría llamada "$name".';

  @override
  String toString() => message;
}
