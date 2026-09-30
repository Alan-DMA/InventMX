import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/admin_http.dart';
import '../../session/admin_session.dart';
import '../domain/access_models.dart';

/// Acceso del operador: contraseña → código de Authenticator (o código de
/// recuperación). Los errores salen como [AdminApiException].
abstract class AccessRepository {
  /// POST /platform/auth/login
  Future<LoginChallenge> login(String email, String password);

  /// POST /platform/auth/verify — vincula (primer acceso) o verifica.
  Future<SessionGrant> verify(String challengeToken, String code);

  /// POST /platform/auth/recover
  Future<SessionGrant> recover(String challengeToken, String recoveryCode);
}

class AccessRepositoryImpl implements AccessRepository {
  AccessRepositoryImpl(this._dio, this._now);
  final Dio _dio;
  final DateTime Function() _now;

  @override
  Future<LoginChallenge> login(String email, String password) async {
    try {
      final res = await _dio.post('/auth/login', data: {'email': email.trim(), 'password': password});
      return LoginChallenge.fromJson(res.data as Map<String, dynamic>, _now());
    } catch (e) {
      throw toAdminError(e, 'No pudimos iniciar el acceso.');
    }
  }

  @override
  Future<SessionGrant> verify(String challengeToken, String code) =>
      _session('/auth/verify', {'challenge_token': challengeToken, 'code': code});

  @override
  Future<SessionGrant> recover(String challengeToken, String recoveryCode) =>
      _session('/auth/recover', {'challenge_token': challengeToken, 'recovery_code': recoveryCode.trim()});

  Future<SessionGrant> _session(String path, Map<String, dynamic> body) async {
    try {
      final res = await _dio.post(path, data: body);
      return SessionGrant.fromJson(res.data as Map<String, dynamic>);
    } catch (e) {
      throw toAdminError(e, 'No pudimos abrir la sesión.');
    }
  }
}

final accessRepositoryProvider = Provider<AccessRepository>(
  (ref) => AccessRepositoryImpl(ref.watch(adminDioProvider), ref.watch(adminClockProvider)),
);
