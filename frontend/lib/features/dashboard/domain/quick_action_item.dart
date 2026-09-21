import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

/// Identificadores de las acciones operativas disponibles en el catálogo de Nexus.
enum QuickActionId {
  sell,
  adjustStock,
  newPurchase,
  addProduct,
  gondola,
  webCatalog,
  importExcel,
  purchasesHub,
}

/// Definición de una acción rápida operable desde el Centro de Mando.
class QuickActionDefinition {
  const QuickActionDefinition({
    required this.id,
    required this.title,
    required this.icon,
    required this.accentColor,
    required this.description,
  });

  final QuickActionId id;
  final String title;
  final IconData icon;
  final Color accentColor;
  final String description;

  /// Catálogo completo de acciones rápidas disponibles en el sistema.
  static const List<QuickActionDefinition> catalog = [
    QuickActionDefinition(
      id: QuickActionId.sell,
      title: 'Nueva Venta',
      icon: Icons.point_of_sale_rounded,
      accentColor: AppColors.emerald,
      description: 'Abrir terminal POS y cobrar ticket',
    ),
    QuickActionDefinition(
      id: QuickActionId.adjustStock,
      title: 'Ajustar Stock',
      icon: Icons.tune_rounded,
      accentColor: AppColors.skyBlue,
      description: 'Ajuste rápido de existencias en mostrador',
    ),
    QuickActionDefinition(
      id: QuickActionId.newPurchase,
      title: 'OC Nueva',
      icon: Icons.shopping_cart_checkout_rounded,
      accentColor: Color(0xFFF59E0B), // Warm amber
      description: 'Emitir orden de compra a proveedor',
    ),
    QuickActionDefinition(
      id: QuickActionId.addProduct,
      title: 'Agregar Producto',
      icon: Icons.add_box_outlined,
      accentColor: AppColors.emerald,
      description: 'Registrar un nuevo producto en catálogo',
    ),
    QuickActionDefinition(
      id: QuickActionId.gondola,
      title: 'Modo Góndola',
      icon: Icons.qr_code_scanner_rounded,
      accentColor: AppColors.skyBlue,
      description: 'Auditoría continua de precios y códigos',
    ),
    QuickActionDefinition(
      id: QuickActionId.webCatalog,
      title: 'Vitrina Web',
      icon: Icons.storefront_rounded,
      accentColor: Color(0xFF8B5CF6), // Purple
      description: 'Compartir catálogo WhatsApp y revisar pedidos',
    ),
    QuickActionDefinition(
      id: QuickActionId.importExcel,
      title: 'Importar Excel',
      icon: Icons.file_upload_outlined,
      accentColor: Color(0xFF10B981),
      description: 'Cargar lista masiva de productos',
    ),
    QuickActionDefinition(
      id: QuickActionId.purchasesHub,
      title: 'Ver Compras',
      icon: Icons.local_shipping_outlined,
      accentColor: Color(0xFF3B82F6),
      description: 'Consultar cuentas por pagar y pedidos',
    ),
  ];

  /// Acciones por defecto al abrir la aplicación (Vender, Agregar producto, Ajustar stock).
  static const List<QuickActionId> defaultSelection = [
    QuickActionId.sell,
    QuickActionId.addProduct,
    QuickActionId.adjustStock,
  ];

  static QuickActionDefinition fromId(QuickActionId id) {
    return catalog.firstWhere(
      (def) => def.id == id,
      orElse: () => catalog.first,
    );
  }
}
