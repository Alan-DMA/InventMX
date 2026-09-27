import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../saas_admin/presentation/saas_provider.dart';
import '../data/analytics_dashboard_repository.dart';
import '../domain/analytics_dashboard.dart';
import '../../account/presentation/data_scope_provider.dart';

/// Período seleccionado en el dashboard (chips Hoy / Semana / Mes).
final dashboardPeriodProvider =
    StateProvider<DashboardPeriod>((_) => DashboardPeriod.month);

/// Dashboard del período activo. Comparte `clockProvider` con el resto de la
/// app para que "hoy" sea el mismo en pantalla, mock y tests.
final analyticsDashboardProvider =
    FutureProvider.autoDispose<AnalyticsDashboard>((ref) {
  final period = ref.watch(dashboardPeriodProvider);
  // Cifras del alcance elegido en la leyenda (Fase 2): al cambiarlo, se recalcula.
  ref.watch(dataScopeProvider);
  final now = ref.watch(clockProvider)();
  return ref.watch(analyticsDashboardRepositoryProvider).getDashboard(
        period: period,
        now: now,
      );
});
