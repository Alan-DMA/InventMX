/// Modelo de dominio — Clonación de catálogo hacia otra tienda (RF-31).
///
/// Anclado a `POST /inventory/clone-catalog` (docs/api/inventory.yaml):
/// se clonan nombres, categorías, precios, SKUs y códigos de barras;
/// NUNCA stock, kardex, imágenes ni costos. Solo Plan Corporativo.
library;

import 'package:equatable/equatable.dart';

// ---------------------------------------------------------------------------
// Tienda destino
// ---------------------------------------------------------------------------

/// Otra tienda de la red Nexus identificada por su código público
/// (`tenant.code`, el mismo que aparece en "Mi cuenta" y como concepto SPEI).
/// El dueño de la tienda destino lo comparte; no se listan tiendas ajenas.
class CloneTarget extends Equatable {
  const CloneTarget({
    required this.tenantId,
    required this.code,
    required this.name,
    this.productCount = 0,
  });

  final String tenantId;
  final String code;
  final String name;

  /// Productos que YA tiene la tienda destino (para avisar duplicados).
  final int productCount;

  factory CloneTarget.fromJson(Map<dynamic, dynamic> json) => CloneTarget(
        tenantId: (json['tenant_id'] ?? json['id'] ?? '').toString(),
        code: (json['code'] ?? '').toString(),
        name: (json['name'] ?? '').toString(),
        productCount: (json['product_count'] as num?)?.toInt() ?? 0,
      );

  @override
  List<Object?> get props => [tenantId, code, name, productCount];
}

// ---------------------------------------------------------------------------
// Petición y resultado
// ---------------------------------------------------------------------------

class CloneCatalogRequest extends Equatable {
  const CloneCatalogRequest({
    required this.targetTenantId,
    this.includePrices = true,
    this.includeCategories = true,
    this.filterCategory,
  });

  final String targetTenantId;

  /// `false` → los precios se clonan en $0.00 (la sucursal pone los suyos).
  final bool includePrices;

  /// `false` → todo cae en la categoría "General".
  final bool includeCategories;

  /// Solo clonar una categoría. Null = catálogo completo.
  final String? filterCategory;

  Map<String, dynamic> toJson() => {
        'target_tenant_id': targetTenantId,
        'include_prices': includePrices,
        'include_categories': includeCategories,
        'filter_category': filterCategory,
      };

  @override
  List<Object?> get props =>
      [targetTenantId, includePrices, includeCategories, filterCategory];
}

class CloneCatalogResult extends Equatable {
  const CloneCatalogResult({
    required this.productsCloned,
    required this.targetTenantId,
    required this.clonedAt,
  });

  final int productsCloned;
  final String targetTenantId;
  final DateTime clonedAt;

  factory CloneCatalogResult.fromJson(Map<dynamic, dynamic> json) =>
      CloneCatalogResult(
        productsCloned: (json['products_cloned'] as num?)?.toInt() ?? 0,
        targetTenantId: (json['target_tenant_id'] ?? '').toString(),
        clonedAt: DateTime.tryParse(json['cloned_at']?.toString() ?? '') ??
            DateTime.now(),
      );

  @override
  List<Object?> get props => [productsCloned, targetTenantId, clonedAt];
}

/// Avance de la duplicación — solo lo emite el mock (el backend real responde
/// en una sola llamada); la UI muestra barra determinada si hay avance y
/// indeterminada si no.
class CloneProgress extends Equatable {
  const CloneProgress({required this.done, required this.total, this.currentName});

  final int done;
  final int total;
  final String? currentName;

  double get fraction => total == 0 ? 0 : done / total;

  @override
  List<Object?> get props => [done, total, currentName];
}

// ---------------------------------------------------------------------------
// Errores
// ---------------------------------------------------------------------------

class CloneCatalogException implements Exception {
  const CloneCatalogException(this.message, {this.code});
  final String message;

  /// `CATALOG_CLONING_NOT_AVAILABLE` (403) · `TENANT_NOT_FOUND` (404).
  final String? code;

  @override
  String toString() => message;
}
