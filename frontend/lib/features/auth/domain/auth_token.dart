import 'package:equatable/equatable.dart';

/// Modelo de dominio para el par de tokens JWT de Nexus.
/// Access Token: 15 min — Refresh Token: 7 días
/// Constitución Art. IX (Sección 9.1: JWT con Access + Refresh Token)
class AuthToken extends Equatable {
  const AuthToken({
    required this.accessToken,
    required this.refreshToken,
  });

  final String accessToken;
  final String refreshToken;

  /// Construye desde el JSON que retorna `POST /api/v1/auth/login`
  factory AuthToken.fromJson(Map<dynamic, dynamic> json) {
    final dynamic rawTokens = json['tokens'];
    final Map<dynamic, dynamic> tokensMap =
        rawTokens is Map ? rawTokens : json;
    return AuthToken(
      accessToken: (tokensMap['access_token'] ?? json['access_token'] ?? '').toString(),
      refreshToken: (tokensMap['refresh_token'] ?? json['refresh_token'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'access_token': accessToken,
        'refresh_token': refreshToken,
      };

  /// Retorna true si el access token tiene contenido (no valida expiración aquí,
  /// eso lo hace el interceptor cuando el backend devuelve 401).
  bool get isValid => accessToken.isNotEmpty && refreshToken.isNotEmpty;

  @override
  List<Object?> get props => [accessToken, refreshToken];
}
