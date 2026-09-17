import 'dart:math' show max;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../domain/purchase_order.dart';
import '../domain/supplier.dart';
import '../data/purchases_repository.dart' show SupplierHasActiveOrdersException;
import 'purchases_provider.dart';
import 'widgets/add_supplier_modal.dart';
import 'widgets/phone_launcher.dart';
import 'package:url_launcher/url_launcher.dart';

/// Detalle de proveedor — Subtarea 11.2.2: catálogo de productos que surte.
///
/// Decisión de alcance (plan aprobado): se implementa como bottom sheet, no
/// como pantalla completa, para no exceder las 6h estimadas de la tarea con
/// un flujo de detalle/edición propio.
///
/// El catálogo se deriva de las líneas de las órdenes de compra ya
/// registradas a este proveedor — la API no expone un endpoint de
/// "catálogo por proveedor" (ver `docs/api/purchases.yaml`), así que el
/// mock reconstruye la última referencia de costo conocida por producto.
///
/// Ajuste de QA de Eduardo: se retiró `DraggableScrollableSheet` — su gesto
/// de arrastre propio competía con el cierre estándar del modal (botón
/// atrás/tap fuera) y no tenía una "X" explícita. Ahora sigue el mismo
/// patrón de contenedor + `SingleChildScrollView` que `AddProductModal` /
/// `AddSupplierModal`.
Future<void> showSupplierDetailModal(BuildContext context, Supplier supplier) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    isDismissible: true,
    enableDrag: true,
    backgroundColor: Colors.transparent,
    builder: (_) => SupplierDetailModal(supplier: supplier),
  );
}

class SupplierDetailModal extends ConsumerWidget {
  const SupplierDetailModal({super.key, required this.supplier});

  /// Instantánea con la que se abrió; el `build` prefiere la versión viva del
  /// provider para reflejar una edición sin cerrar la hoja (U-07).
  final Supplier supplier;

  // ── U-07: editar y dar de baja ────────────────────────────────────────────

  Future<void> _edit(BuildContext context, Supplier current) async {
    await showAddSupplierModal(context, initial: current);
  }

  Future<void> _deactivate(
    BuildContext context,
    WidgetRef ref,
    Supplier current,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('¿Dar de baja a ${current.name}?',
            style: const TextStyle(color: AppColors.onSurface, fontSize: 17)),
        content: const Text(
          'Dejará de aparecer en tu directorio. Las compras y cuentas por '
          'pagar anteriores se conservan.',
          style: TextStyle(color: AppColors.onSurfaceMuted, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            key: const Key('confirmDeactivateSupplier'),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Dar de baja'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await ref.read(suppliersProvider.notifier).deactivateSupplier(current.id);
      navigator.pop();
      messenger.showSnackBar(SnackBar(
        content: Text('${current.name} dado de baja.'),
        behavior: SnackBarBehavior.floating,
      ));
    } on SupplierHasActiveOrdersException catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text(e.message),
        behavior: SnackBarBehavior.floating,
      ));
    } catch (_) {
      messenger.showSnackBar(const SnackBar(
        content: Text('No se pudo dar de baja al proveedor. Intenta de nuevo.'),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  List<PurchaseOrderItem> _catalogFor(WidgetRef ref) {
    final orders = ref
        .watch(purchaseOrdersProvider)
        .orders
        .where((o) => o.supplierId == supplier.id);

    final byProduct = <String, PurchaseOrderItem>{};
    for (final order in orders) {
      for (final item in order.items) {
        byProduct[item.productId] = item;
      }
    }
    return byProduct.values.toList();
  }

  Future<void> _launch(WidgetRef ref, BuildContext context, Uri uri) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await ref.read(urlLauncherProvider)(uri,
        mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      messenger.showSnackBar(
          const SnackBar(content: Text('No se pudo abrir la aplicación.')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = _catalogFor(ref);
    final supplier = ref
            .watch(suppliersProvider)
            .suppliers
            .where((s) => s.id == this.supplier.id)
            .firstOrNull ??
        this.supplier;
    final phone = supplier.phone;
    final mq = MediaQuery.of(context);
    final bottomInset = max(mq.viewInsets.bottom, mq.padding.bottom);

    return Container(
      constraints: BoxConstraints(maxHeight: mq.size.height * 0.85),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(24, 12, 24, 24 + bottomInset),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        supplier.name,
                        style: const TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w800,
                            color: AppColors.onSurface),
                      ),
                      if (supplier.contactName != null) ...[
                        const SizedBox(height: 2),
                        Text(supplier.contactName!,
                            style: const TextStyle(
                                fontSize: 13, color: AppColors.onSurfaceMuted)),
                      ],
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded,
                      size: 22, color: AppColors.onSurfaceMuted),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  tooltip: 'Cerrar',
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (phone != null)
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _launch(ref, context, callUri(phone)),
                      icon: const Icon(Icons.call_rounded, size: 18),
                      label: const Text('Llamar'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () =>
                          _launch(ref, context, whatsAppUri(phone)),
                      icon: const Icon(Icons.chat_rounded, size: 18),
                      label: const Text('WhatsApp'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            AppColors.success.withValues(alpha: 0.15),
                        foregroundColor: AppColors.success,
                        elevation: 0,
                      ),
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 20),
            const Text(
              'Productos que surte',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.onSurface),
            ),
            const SizedBox(height: 10),
            if (catalog.isEmpty)
              const Text(
                'Aún no hay compras registradas a este proveedor.',
                style: TextStyle(fontSize: 13, color: AppColors.onSurfaceMuted),
              )
            else
              ...catalog.map((item) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        const Icon(Icons.inventory_2_outlined,
                            size: 16, color: AppColors.onSurfaceMuted),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(item.productName,
                              style: const TextStyle(
                                  fontSize: 14, color: AppColors.onSurface)),
                        ),
                        Text(
                          '\$${item.unitCostMxn.toStringAsFixed(2)}',
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.skyBlue),
                        ),
                      ],
                    ),
                  )),

            // ── U-07: acciones sobre el proveedor ──────────────────────────
            const SizedBox(height: 20),
            const Divider(height: 1, color: AppColors.border),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    key: const Key('editSupplierButton'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.onSurface,
                      side: const BorderSide(color: AppColors.border),
                      minimumSize: const Size(0, 44),
                    ),
                    onPressed: () => _edit(context, supplier),
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('Editar'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextButton.icon(
                    key: const Key('deactivateSupplierButton'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.error,
                      minimumSize: const Size(0, 44),
                    ),
                    onPressed: () => _deactivate(context, ref, supplier),
                    icon: const Icon(Icons.person_off_outlined, size: 18),
                    label: const Text('Dar de baja'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
