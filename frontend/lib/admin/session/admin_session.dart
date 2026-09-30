import 'dart:convert';

import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../access/domain/access_models.dart';
import '../core/browser/session_store.dart';

/// Reloj sustituible (tests del vencimiento de la sesión).
final adminClockProvider = Provider<DateTime Function()>((_) => DateTime.now);

/// La sesión del operador: 2 h sin refresh, guardada en la pestaña (P30).
class AdminSession extends Equatable {
  const AdminSession({
    required this.token,
    required this.expiresAt,
    required this.operatorName,
    required this.operatorEmail,
    required this.recoveryCodesRemaining,
    this.enteredWithRecoveryCode = false,
    this.operatorId,
  });

  /// Nulo en sesiones guardadas antes de la etapa 3d: el servidor decide.
  final String? operatorId;

  final String token;
  final DateTime expiresAt;
  final String operatorName;
  final String operatorEmail;
  final int recoveryCodesRemaining;

  /// Entró con un código de recuperación: el panel le dice cuántos le quedan
  /// hasta que cierre el aviso.
  final bool enteredWithRecoveryCode;

  Duration remaining(DateTime now) => expiresAt.difference(now);

  /// Primer nombre para la franja ("Eduardo"); el correo si no hay nombre.
  String get shortName {
    final first = operatorName.trim().split(RegExp(r'\s+')).first;
    return first.isEmpty ? operatorEmail : first;
  }

  AdminSession withoutRecoveryNotice() => AdminSession(
        token: token,
        expiresAt: expiresAt,
        operatorName: operatorName,
        operatorEmail: operatorEmail,
        recoveryCodesRemaining: recoveryCodesRemaining,
        operatorId: operatorId,
      );

  Map<String, dynamic> toJson() => {
        'token': token,
        'expires_at': expiresAt.toUtc().toIso8601String(),
        'name': operatorName,
        'email': operatorEmail,
        'recovery_remaining': recoveryCodesRemaining,
        'via_recovery': enteredWithRecoveryCode,
        'operator_id': operatorId,
      };

  factory AdminSession.fromJson(Map<String, dynamic> json) => AdminSession(
        token: json['token'] as String,
        expiresAt: DateTime.parse(json['expires_at'] as String),
        operatorName: (json['name'] ?? '').toString(),
        operatorEmail: (json['email'] ?? '').toString(),
        recoveryCodesRemaining: (json['recovery_remaining'] as num?)?.toInt() ?? 0,
        enteredWithRecoveryCode: json['via_recovery'] == true,
        operatorId: json['operator_id'] as String?,
      );

  @override
  List<Object?> get props => [token, expiresAt, recoveryCodesRemaining, enteredWithRecoveryCode];
}

class AdminSessionState extends Equatable {
  const AdminSessionState({this.session, this.expired = false});

  final AdminSession? session;

  /// La sesión terminó sola (2 h o el servidor ya no la acepta), no porque el
  /// operador saliera: el acceso lo dice y regresa a donde estaba.
  final bool expired;

  bool get signedIn => session != null;

  @override
  List<Object?> get props => [session, expired];
}

class AdminSessionNotifier extends Notifier<AdminSessionState> {
  static const storageKey = 'nexus.admin.session';

  SessionStore get _store => ref.read(sessionStoreProvider);

  @override
  AdminSessionState build() {
    final raw = ref.watch(sessionStoreProvider).read(storageKey);
    if (raw == null) return const AdminSessionState();
    try {
      final session = AdminSession.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      if (session.remaining(ref.read(adminClockProvider)()) > Duration.zero) {
        return AdminSessionState(session: session);
      }
    } catch (_) {}
    ref.read(sessionStoreProvider).remove(storageKey);
    return const AdminSessionState(expired: true);
  }

  void start(SessionGrant grant, {bool viaRecoveryCode = false}) {
    final session = AdminSession(
      token: grant.token,
      expiresAt: ref.read(adminClockProvider)().add(grant.expiresIn),
      operatorName: grant.operatorName,
      operatorEmail: grant.operatorEmail,
      recoveryCodesRemaining: grant.recoveryCodesRemaining,
      enteredWithRecoveryCode: viaRecoveryCode,
      operatorId: grant.operatorId,
    );
    _store.write(storageKey, jsonEncode(session.toJson()));
    state = AdminSessionState(session: session);
  }

  /// Vencida por tiempo o rechazada por el servidor. Los borradores se quedan
  /// en la pestaña para cuando vuelva a entrar.
  void expire() {
    if (state.session == null) return;
    _store.remove(storageKey);
    state = const AdminSessionState(expired: true);
  }

  void signOut() {
    _store.remove(storageKey);
    state = const AdminSessionState();
  }

  void dismissRecoveryNotice() {
    final session = state.session;
    if (session == null || !session.enteredWithRecoveryCode) return;
    final updated = session.withoutRecoveryNotice();
    _store.write(storageKey, jsonEncode(updated.toJson()));
    state = AdminSessionState(session: updated);
  }
}

final adminSessionProvider = NotifierProvider<AdminSessionNotifier, AdminSessionState>(AdminSessionNotifier.new);
