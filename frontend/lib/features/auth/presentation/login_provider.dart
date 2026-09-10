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

      // Actualiza el sessionProvider → GoRouter redirige a /dashboard
      ref.read(sessionProvider.notifier).state = true;
      ref.read(currentUserNameProvider.notifier).state = email;

      state = state.copyWith(status: LoginStatus.success, token: token);
    } on AuthException catch (e) {
      state = state.copyWith(
        status: LoginStatus.error,
        errorMessage: e.message,
      );
    } catch (_) {
      state = state.copyWith(
        status: LoginStatus.error,
        errorMessage: 'Error inesperado. Intenta de nuevo.',
      );
    }
  }

  Future<void> logout() async {
    final storage = ref.read(secureStorageProvider);
    await storage.clearAll();
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
