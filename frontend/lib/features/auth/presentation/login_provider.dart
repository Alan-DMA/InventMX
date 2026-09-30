import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/auth_repository.dart';
import '../domain/auth_token.dart';

// ---------------------------------------------------------------------------
// Provider de sesión activa — fuente de verdad reactiva para GoRouter
// ---------------------------------------------------------------------------

/// StateProvider<bool> que el LoginNotifier actualiza directamente.
/// GoRouter observa este provider a través de _SessionRefreshListenable
/// y redirige de inmediato al cambiar el estado de sesión.
final sessionProvider = StateProvider<bool>((ref) => false);

/// Nombre/identificador del cajero en sesión — usado para mostrar "atendido
/// por" en el ticket (Tarea 8.2) y en el tablero de comisiones.
///
/// Blocker: Alan aún no entrega el perfil de usuario autenticado (RBAC,
/// Tarea 2.1) — se usa el email de login como placeholder de despliegue.
final currentUserNameProvider = StateProvider<String?>((ref) => null);

/// Entró con un código de un solo uso y aún no pone contraseña nueva (P16).
/// El router manda todo a "Pon una contraseña nueva" mientras sea `true`.
/// Se hidrata en `main` desde el almacén seguro (reabrir la app no se salta
/// el paso) y el interceptor lo enciende ante un 403 `PASSWORD_CHANGE_REQUIRED`.
final mustChangePasswordProvider = StateProvider<bool>((ref) => false);

// ---------------------------------------------------------------------------
// Estado del formulario de login
// ---------------------------------------------------------------------------

enum LoginStatus { idle, loading, success, error }

class LoginState {
  const LoginState({
    this.status = LoginStatus.idle,
    this.token,
    this.errorMessage,
  });

  final LoginStatus status;
  final AuthToken? token;
  final String? errorMessage;

  bool get isLoading => status == LoginStatus.loading;
  bool get hasError => status == LoginStatus.error;

  LoginState copyWith({
    LoginStatus? status,
    AuthToken? token,
    String? errorMessage,
  }) {
    return LoginState(
      status: status ?? this.status,
      token: token ?? this.token,
      errorMessage: errorMessage,
    );
  }
}

// ---------------------------------------------------------------------------
// Notifier
// ---------------------------------------------------------------------------

class LoginNotifier extends Notifier<LoginState> {
  @override
  LoginState build() => const LoginState();

  Future<void> login({
    required String email,
    required String password,
  }) async {
    state = state.copyWith(status: LoginStatus.loading, errorMessage: null);

    try {
      final repo = ref.read(authRepositoryProvider);
      final token = await repo.login(email: email, password: password);
      await _openSession(email, token);
      state = state.copyWith(status: LoginStatus.success, token: token);
    } on AuthException catch (e) {
      state = state.copyWith(
        status: LoginStatus.error,
        errorMessage: e.message,
      );
    } catch (e) {
      state = state.copyWith(
        status: LoginStatus.error,
        errorMessage: 'Error inesperado: $e',
      );
    }
  }

  /// Entra con el código de un solo uso (P16). Errores como [AuthException]
  /// para que la pantalla los muestre junto al campo, no en un SnackBar.
  Future<void> loginWithCode({required String email, required String code}) async {
    final token = await ref.read(authRepositoryProvider).loginWithCode(email: email, code: code);
    await _openSession(email.trim(), token);
  }

  /// Guarda la contraseña nueva y libera la app.
  Future<void> completePasswordChange(String newPassword) async {
    await ref.read(authRepositoryProvider).setNewPassword(newPassword);
    await ref.read(secureStorageProvider).saveMustChangePassword(false);
    ref.read(mustChangePasswordProvider.notifier).state = false;
  }

  Future<void> _openSession(String email, AuthToken token) async {
    final storage = ref.read(secureStorageProvider);
    // Se persiste para que al reabrir la app la identidad siga siendo la
    // misma: la sesión se restauraba, el correo no.
    await storage.saveUserEmail(email);
    // Sólo se escribe si hay cambio pendiente: cerrar sesión y guardar la
    // contraseña nueva ya lo borran, un login normal no tiene nada que guardar.
    if (token.mustChangePassword) await storage.saveMustChangePassword(true);

    // El cambio pendiente va antes que la sesión: el primer redirect ya
    // manda a "Pon una contraseña nueva", sin asomarse al tablero.
    ref.read(mustChangePasswordProvider.notifier).state = token.mustChangePassword;
    ref.read(sessionProvider.notifier).state = true;
    ref.read(currentUserNameProvider.notifier).state = email;
  }

  Future<void> logout() async {
    final storage = ref.read(secureStorageProvider);
    // Sólo la sesión: las preferencias de cada quien llevan su correo en la
    // clave y se conservan para la próxima vez que entre (QA Sep 23).
    await storage.clearSession();
    ref.read(mustChangePasswordProvider.notifier).state = false;
    ref.read(sessionProvider.notifier).state = false;
    ref.read(currentUserNameProvider.notifier).state = null;
    state = const LoginState();
  }

  void resetError() {
    if (state.hasError) {
      state = state.copyWith(status: LoginStatus.idle, errorMessage: null);
    }
  }
}

// ---------------------------------------------------------------------------
// Provider global del estado de login
// ---------------------------------------------------------------------------

final loginProvider = NotifierProvider<LoginNotifier, LoginState>(
  LoginNotifier.new,
);
