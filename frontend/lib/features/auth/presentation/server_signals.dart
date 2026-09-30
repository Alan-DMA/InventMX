import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/auth_interceptor.dart';
import '../../saas_admin/domain/subscription.dart';
import '../../saas_admin/presentation/saas_provider.dart';
import '../data/auth_repository.dart';
import 'login_provider.dart';

/// Atiende las señales del servidor que detecta el interceptor (Centro de
/// soporte, etapa 2b). Se instala en `main` sustituyendo
/// [serverSignalHandlerProvider].
///
/// - `PASSWORD_CHANGE_REQUIRED` (403): entró con un código y el servidor aún
///   no le deja usar la app → "Pon una contraseña nueva". Cubre el caso en que
///   la bandera local se perdió (otro teléfono, datos borrados).
/// - `TENANT_HARD_LOCK` (402): la tienda se suspendió con la app abierta →
///   se relee la suscripción y el router lleva a la pantalla de suspensión en
///   vez de dejar que cada pantalla falle por su cuenta.
void handleServerSignal(Ref ref, String code) {
  switch (code) {
    case AuthInterceptor.passwordChangeRequired:
      if (!ref.read(mustChangePasswordProvider)) {
        ref.read(mustChangePasswordProvider.notifier).state = true;
        ref.read(secureStorageProvider).saveMustChangePassword(true);
      }
    case AuthInterceptor.tenantHardLock:
      if (ref.read(subscriptionStatusProvider) != SubscriptionStatus.hardLock) {
        ref.read(subscriptionProvider.notifier).refresh();
      }
  }
}
