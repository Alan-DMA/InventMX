import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../saas_admin/presentation/saas_provider.dart';
import '../data/commissions_repository.dart' show monthLabel;
import 'employee_performance_provider.dart';
import 'widgets/employee_performance_tab.dart';

/// Pantalla "Mis Comisiones" — Tarea 8.2.3.
///
/// Disposición inspirada en la referencia de Figma (node 68:115); la
/// identidad visual (colores, tipografía) es la de Nexus, no la del diseño
/// original (ver `EmployeePerformanceTab`).
///
/// Trazabilidad: Doc. Maestro RF-10 (Sección 5.2), Sección 6 (SR-05)
///              Constitución Art. VII (7.2) · HU-14 / CU-16
class EmployeePerformanceScreen extends ConsumerWidget {
  const EmployeePerformanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final performanceAsync = ref.watch(employeePerformanceProvider);

    return Scaffold(
      backgroundColor: AppColors.darkSlate,
      appBar: AppBar(
        backgroundColor: AppColors.darkSlate,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.onSurface),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text(
          'Mis Comisiones',
          style: TextStyle(
            color: AppColors.onSurface,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: SafeArea(
        child: performanceAsync.when(
          data: (performance) => SingleChildScrollView(
            child: EmployeePerformanceTab(
              performance: performance,
              onPeriodTap: () => _pickMonth(context, ref),
              selectedMonth: ref.watch(commissionsMonthProvider),
              onMonthTap: (m) =>
                  ref.read(commissionsMonthProvider.notifier).state = m,
            ),
          ),
          loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.emerald),
          ),
          error: (error, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'No se pudo cargar el tablero de comisiones.\n$error',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.onSurfaceMuted),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Hoja con los últimos 12 meses (el actual primero). Cambiar el mes
  /// invalida el tablero vía `commissionsMonthProvider`.
  Future<void> _pickMonth(BuildContext context, WidgetRef ref) async {
    final now = ref.read(clockProvider)();
    final selected = ref.read(commissionsMonthProvider);
    final months = [
      for (var i = 0; i < 12; i++) DateTime(now.year, now.month - i),
    ];
    final picked = await showModalBottomSheet<DateTime>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 12, 20, 8),
              child: Text(
                'Período',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.onSurfaceMuted,
                  letterSpacing: 0.6,
                ),
              ),
            ),
            for (final m in months)
              ListTile(
                key: Key('month-${m.year}-${m.month}'),
                title: Text(
                  monthLabel(m),
                  style: TextStyle(
                    color: AppColors.onSurface,
                    fontWeight: m.year == selected.year && m.month == selected.month
                        ? FontWeight.w700
                        : FontWeight.w400,
                  ),
                ),
                trailing: m.year == selected.year && m.month == selected.month
                    ? const Icon(Icons.check_rounded, color: AppColors.emerald)
                    : null,
                onTap: () => Navigator.of(context).pop(m),
              ),
          ],
        ),
      ),
    );
    if (picked != null) {
      ref.read(commissionsMonthProvider.notifier).state = picked;
    }
  }
}
