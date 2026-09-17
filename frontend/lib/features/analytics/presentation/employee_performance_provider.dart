import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/dio_client.dart';
import '../../auth/data/auth_repository.dart';
import '../../auth/presentation/login_provider.dart';
import '../data/commissions_repository.dart';
import '../domain/employee_performance.dart';

final commissionsRepositoryProvider = Provider<CommissionsRepository>(
  (ref) => CommissionsRepositoryImpl(
    client: ref.watch(dioClientProvider),
  ),
);

/// `autoDispose` a propósito: se recalcula cada vez que se abre el tablero
/// (CA-06 — las cifras deben reflejar los cobros hechos durante la sesión)
/// en vez de quedar cacheado con el primer valor leído.
final employeePerformanceProvider =
    FutureProvider.autoDispose<EmployeePerformance>((ref) {
  final cashierName = ref.watch(currentUserNameProvider) ?? 'Cajero';
  return ref.read(commissionsRepositoryProvider).getPerformance(
        cashierName: cashierName,
      );
});
