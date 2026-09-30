import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/admin_http.dart';
import '../domain/today_models.dart';

/// "Hoy": requiere atención + lo que pasó, y las métricas de la columna.
abstract class TodayRepository {
  /// GET /platform/feed?since&until — el cliente agrupa por día en su zona (S-12).
  Future<FeedPage> feed({required DateTime since, required DateTime until});

  /// GET /platform/metrics
  Future<PlatformMetrics> metrics();
}

class TodayRepositoryImpl implements TodayRepository {
  TodayRepositoryImpl(this._dio);
  final Dio _dio;

  @override
  Future<FeedPage> feed({required DateTime since, required DateTime until}) async {
    try {
      final res = await _dio.get('/feed', queryParameters: {
        'since': since.toUtc().toIso8601String(),
        'until': until.toUtc().toIso8601String(),
      });
      return FeedPage.fromJson(res.data as Map<String, dynamic>);
    } catch (e) {
      throw toAdminError(e, 'No pudimos cargar lo de hoy.');
    }
  }

  @override
  Future<PlatformMetrics> metrics() async {
    try {
      final res = await _dio.get('/metrics');
      return PlatformMetrics.fromJson(res.data as Map<String, dynamic>);
    } catch (e) {
      throw toAdminError(e, 'No pudimos cargar las métricas.');
    }
  }
}

final todayRepositoryProvider = Provider<TodayRepository>((ref) => TodayRepositoryImpl(ref.watch(adminDioProvider)));
