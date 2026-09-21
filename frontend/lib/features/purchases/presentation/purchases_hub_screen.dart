import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../saas_admin/presentation/subscription_lock_banner.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import 'purchases_provider.dart';
import 'tabs/accounts_payable_tab.dart';
import 'tabs/purchase_orders_tab.dart';
import 'tabs/suppliers_tab.dart';
import 'widgets/add_supplier_modal.dart';

/// Hub de Compras — Tarea 11.2 (Figma nodo `1:2`): tabs "Compras /
/// Proveedores / Por pagar" con badges de conteo, igual patrón de pantalla
/// combinada ya aprobado en la Tarea 10.2 (`CashSessionSummaryScreen`).
class PurchasesHubScreen extends ConsumerStatefulWidget {
  const PurchasesHubScreen({super.key});

  @override
  ConsumerState<PurchasesHubScreen> createState() => _PurchasesHubScreenState();
}

class _PurchasesHubScreenState extends ConsumerState<PurchasesHubScreen>
    with SingleTickerProviderStateMixin {
  late final _tabController = TabController(length: 3, vsync: this);

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _openCreateScreen(BuildContext context) async {
    // Solo lectura por morosidad (Tarea 14.2.3, D5).
    if (!await requireWriteAccess(context, ref)) return;
    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final created = await context.push<bool>(AppRoutes.purchaseCreate);
    if (created == true && mounted) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('✓ Orden de compra creada'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.surface,
        ),
      );
    }
  }

  Future<void> _openAddSupplierModal(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final created = await showAddSupplierModal(context);
    if (created != null && mounted) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('✓ "$created" agregado a proveedores'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.surface,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final purchaseCount = ref.watch(purchaseOrdersProvider).allCount;
    final payableCount = ref.watch(accountsPayableProvider).items.length;

    return Scaffold(
      backgroundColor: AppColors.darkSlate,
      appBar: AppBar(
        backgroundColor: AppColors.darkSlate,
        title: const Text('Compras'),
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColors.skyBlue,
          unselectedLabelColor: AppColors.onSurfaceMuted,
          indicatorColor: AppColors.skyBlue,
          tabs: [
            _tab('Compras', purchaseCount),
            const Tab(text: 'Proveedores'),
            _tab('Por pagar', payableCount),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          PurchaseOrdersTab(),
          SuppliersTab(),
          AccountsPayableTab(),
        ],
      ),
      // Mismo FAB "+" del tab Compras — en Proveedores agrega un proveedor
      // en vez de una orden (ajuste de QA de Eduardo); en Por pagar no hay
      // acción de alta, se oculta.
      floatingActionButton: AnimatedBuilder(
        animation: _tabController,
        builder: (_, __) {
          return switch (_tabController.index) {
            0 => FloatingActionButton(
                heroTag: 'fab-purchase-new',
                onPressed: () => _openCreateScreen(context),
                backgroundColor: AppColors.emerald,
                foregroundColor: AppColors.darkSlate,
                tooltip: 'Nueva orden de compra',
                child: const Icon(Icons.add_rounded, size: 28),
              ),
            1 => FloatingActionButton(
                heroTag: 'fab-supplier-add',
                onPressed: () => _openAddSupplierModal(context),
                backgroundColor: AppColors.emerald,
                foregroundColor: AppColors.darkSlate,
                tooltip: 'Nuevo proveedor',
                child: const Icon(Icons.add_rounded, size: 28),
              ),
            _ => const SizedBox.shrink(),
          };
        },
      ),
    );
  }

  Widget _tab(String label, int count) {
    return Tab(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
          if (count > 0) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: AppColors.skyBlue.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '$count',
                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.skyBlue),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
