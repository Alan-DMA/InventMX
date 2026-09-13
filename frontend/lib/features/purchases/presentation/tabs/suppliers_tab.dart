import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import '../purchases_provider.dart';
import '../supplier_detail_modal.dart';
import '../widgets/expandable_search_toggle.dart';
import '../widgets/supplier_list_tile.dart';

/// Tab "Proveedores" del hub — Subtarea 11.2.2.
class SuppliersTab extends ConsumerWidget {
  const SuppliersTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(suppliersProvider);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Directorio de proveedores',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.onSurfaceMuted),
                ),
              ),
              ExpandableSearchToggle(
                hintText: 'Nombre o RFC...',
                onChanged: (q) => ref.read(suppliersProvider.notifier).setSearch(q),
              ),
            ],
          ),
        ),
        if (state.hasError)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _ErrorBanner(error: state.error!, onRetry: () => ref.read(suppliersProvider.notifier).retry()),
          ),
        Expanded(child: _buildBody(state)),
      ],
    );
  }

  Widget _buildBody(SuppliersState state) {
    if (state.isLoading && state.suppliers.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: AppColors.emerald));
    }

    if (state.suppliers.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.local_shipping_outlined, size: 56, color: AppColors.onSurfaceMuted),
              const SizedBox(height: 16),
              Text(
                state.search.isNotEmpty ? 'Sin resultados para "${state.search}"' : 'Aún no tienes proveedores registrados',
                style: const TextStyle(fontSize: 15, color: AppColors.onSurfaceMuted),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return Builder(builder: (context) {
      return ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
        itemCount: state.suppliers.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) {
          final supplier = state.suppliers[i];
          return SupplierListTile(
            supplier: supplier,
            onTap: () => showSupplierDetailModal(context, supplier),
          );
        },
      );
    });
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.error, required this.onRetry});

  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.wifi_off_rounded, size: 18, color: AppColors.error),
          const SizedBox(width: 10),
          const Expanded(child: Text('Error de conexión. Revisa tu red.', style: TextStyle(fontSize: 13, color: AppColors.error))),
          TextButton(onPressed: onRetry, child: const Text('Reintentar')),
        ],
      ),
    );
  }
}
