import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
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
              onPeriodTap: () => _showPeriodBlocker(context),
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

  void _showPeriodBlocker(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Filtro por período disponible cuando el backend entregue '
          'GET /analytics/commissions (Tarea 8.1.3)',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
