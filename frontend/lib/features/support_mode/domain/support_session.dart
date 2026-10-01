/// Sesión de soporte de sólo lectura vista desde la pestaña (Centro de
/// soporte, etapa 4, P37–P42). El tiempo es el del servidor: `expiresAt`
/// manda; el reloj del navegador sólo cuenta hacia esa hora.
class SupportSessionStatus {
  const SupportSessionStatus({
    required this.sessionId,
    required this.tenantName,
    required this.operatorName,
    required this.reason,
    required this.openedAt,
    required this.expiresAt,
    required this.grantExpiresAt,
    this.extensions = 0,
    this.canExtend = false,
  });

  final String sessionId;
  final String tenantName;
  final String operatorName;
  final String reason;
  final DateTime openedAt;
  final DateTime expiresAt;
  final DateTime grantExpiresAt;
  final int extensions;
  final bool canExtend;

  /// Se ofrece "Seguir 30 min más" con 10 min o menos y si el permiso del dueño da para más.
  static const extendWindow = Duration(minutes: 10);

  /// La franja pasa a ámbar.
  static const warnWindow = Duration(minutes: 5);

  factory SupportSessionStatus.fromJson(Map<dynamic, dynamic> json) {
    DateTime at(String key) => DateTime.tryParse('${json[key]}')?.toLocal() ?? DateTime.now();
    return SupportSessionStatus(
      sessionId: '${json['session_id'] ?? ''}',
      tenantName: '${json['tenant_name'] ?? 'Tienda'}',
      operatorName: '${json['operator_name'] ?? 'Soporte'}',
      reason: '${json['reason'] ?? ''}',
      openedAt: at('opened_at'),
      expiresAt: at('expires_at'),
      grantExpiresAt: at('grant_expires_at'),
      extensions: (json['extensions'] as num?)?.toInt() ?? 0,
      canExtend: json['can_extend'] == true,
    );
  }

  /// Puede extender ahora, según el reloj local (el servidor vuelve a decidir).
  bool extendableAt(DateTime now) =>
      expiresAt.difference(now) <= extendWindow && grantExpiresAt.isAfter(expiresAt);
}

/// Por qué terminó la sesión, en palabras del operador.
enum SupportEnd {
  operator('Terminaste la sesión.'),
  signedOut('Saliste del panel y la sesión terminó con él.'),
  expired('Se acabó el tiempo de la sesión.'),
  grantEnded('Terminó el permiso del dueño.'),
  grantRevoked('El dueño retiró el permiso.'),
  grantExpired('El permiso del dueño venció.'),
  notOpened('El enlace venció antes de abrirse.'),
  operatorInactive('La sesión terminó por seguridad.'),
  unknown('La sesión de soporte terminó.');

  const SupportEnd(this.message);
  final String message;

  static SupportEnd fromCode(String? code) => switch (code) {
        'OPERATOR' => SupportEnd.operator,
        'SIGNED_OUT' => SupportEnd.signedOut,
        'EXPIRED' => SupportEnd.expired,
        'GRANT_ENDED' => SupportEnd.grantEnded,
        'NOT_OPENED' => SupportEnd.notOpened,
        'OPERATOR_INACTIVE' => SupportEnd.operatorInactive,
        _ => SupportEnd.unknown,
      };
}

/// El enlace no abrió nada: se dice por qué y qué hacer.
class SupportLinkProblem implements Exception {
  const SupportLinkProblem(this.message);
  final String message;

  @override
  String toString() => message;
}

/// La sesión ya no vale (vino un 401 `SUPPORT_ACCESS_ENDED`).
class SupportSessionEnded implements Exception {
  const SupportSessionEnded(this.end);
  final SupportEnd end;
}
