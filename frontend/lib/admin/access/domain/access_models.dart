import 'dart:convert';

/// Respuesta del paso 1 (contraseña): un reto de 5 min para el código. En el
/// primer acceso trae además el QR y la clave para vincular Authenticator.
class LoginChallenge {
  const LoginChallenge({
    required this.token,
    required this.expiresAt,
    this.otpauthUri,
    this.manualSecret,
  });

  final String token;
  final DateTime expiresAt;
  final String? otpauthUri;
  final String? manualSecret;

  bool get needsEnrollment => otpauthUri != null;

  factory LoginChallenge.fromJson(Map<String, dynamic> json, DateTime now) {
    final token = json['challenge_token'] as String;
    return LoginChallenge(
      token: token,
      expiresAt: jwtExpiry(token) ?? now.add(const Duration(minutes: 5)),
      otpauthUri: json['status'] == 'ENROLLMENT_REQUIRED' ? json['otpauth_uri'] as String? : null,
      manualSecret: json['manual_secret'] as String?,
    );
  }
}

/// Sesión abierta por el servidor (2 h, sin refresh). `recoveryCodes` sólo
/// llega al vincular Authenticator por primera vez: se muestra una vez.
class SessionGrant {
  const SessionGrant({
    required this.token,
    required this.expiresIn,
    required this.operatorName,
    required this.operatorEmail,
    required this.recoveryCodesRemaining,
    this.recoveryCodes,
  });

  final String token;
  final Duration expiresIn;
  final String operatorName;
  final String operatorEmail;
  final int recoveryCodesRemaining;
  final List<String>? recoveryCodes;

  factory SessionGrant.fromJson(Map<String, dynamic> json) {
    final operator = json['operator'] as Map<String, dynamic>;
    return SessionGrant(
      token: json['access_token'] as String,
      expiresIn: Duration(seconds: (json['expires_in'] as num).toInt()),
      operatorName: (operator['full_name'] ?? '').toString(),
      operatorEmail: (operator['email'] ?? '').toString(),
      recoveryCodesRemaining: (json['recovery_codes_remaining'] as num?)?.toInt() ?? 0,
      recoveryCodes: (json['recovery_codes'] as List?)?.map((e) => e.toString()).toList(),
    );
  }
}

/// Vencimiento que el propio token declara (`exp`). Se lee sin verificar la
/// firma: sólo sirve para decirle al operador "pasaron los 5 minutos" en vez
/// de un "código incorrecto" engañoso — el servidor sigue siendo quien decide.
DateTime? jwtExpiry(String token) {
  final parts = token.split('.');
  if (parts.length != 3) return null;
  try {
    final payload = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))));
    final exp = payload is Map ? payload['exp'] : null;
    if (exp is! num) return null;
    return DateTime.fromMillisecondsSinceEpoch(exp.toInt() * 1000, isUtc: true);
  } catch (_) {
    return null;
  }
}

/// El 423 dice "hasta las 14:35 UTC"; el operador lo lee en la hora de su
/// equipo. Si el formato cambiara, se muestra el texto del servidor tal cual.
String lockedMessage(String serverMessage, DateTime nowLocal) {
  final match = RegExp(r'(\d{1,2}):(\d{2})\s*UTC').firstMatch(serverMessage);
  if (match == null) return serverMessage;
  final nowUtc = nowLocal.toUtc();
  var until = DateTime.utc(nowUtc.year, nowUtc.month, nowUtc.day, int.parse(match[1]!), int.parse(match[2]!));
  // Un bloqueo de 15 min que cruza la medianoche UTC cae "antes" de ahora
  if (until.isBefore(nowUtc.subtract(const Duration(hours: 1)))) until = until.add(const Duration(days: 1));
  final local = until.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return 'Demasiados intentos fallidos. Podrás volver a intentar a las ${two(local.hour)}:${two(local.minute)} '
      '(hora de tu equipo).';
}
