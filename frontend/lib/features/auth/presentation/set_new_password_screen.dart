import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../data/auth_repository.dart';
import 'login_provider.dart';
import 'widgets/auth_layout.dart';

/// "Pon una contraseña nueva" (Centro de soporte, P16).
///
/// Entró con un código de un solo uso: hasta guardar una contraseña el
/// servidor no le deja usar la app (403 `PASSWORD_CHANGE_REQUIRED`) y el
/// router lo trae aquí desde cualquier ruta, también al reabrir la app. No hay
/// flecha de regreso, pero nunca es un callejón: "Cerrar sesión" siempre está.
class SetNewPasswordScreen extends ConsumerStatefulWidget {
  const SetNewPasswordScreen({super.key});

  static const minLength = 8;

  @override
  ConsumerState<SetNewPasswordScreen> createState() => _SetNewPasswordScreenState();
}

class _SetNewPasswordScreenState extends ConsumerState<SetNewPasswordScreen> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _obscure = true;
  bool _saving = false;
  bool _submitted = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _password.addListener(() => setState(() {}));
    _confirm.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  String? get _problem {
    if (_password.text.length < SetNewPasswordScreen.minLength) {
      return 'Usa al menos ${SetNewPasswordScreen.minLength} caracteres.';
    }
    if (_confirm.text != _password.text) return 'Las dos contraseñas no coinciden.';
    return null;
  }

  Future<void> _save() async {
    setState(() => _submitted = true);
    if (_problem != null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(loginProvider.notifier).completePasswordChange(_password.text);
      messenger.showSnackBar(const SnackBar(
        content: Text('Listo. Desde ahora entras con tu contraseña nueva.'),
        behavior: SnackBarBehavior.floating,
      ));
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final length = _password.text.length;
    final hint = length == 0
        ? 'Mínimo ${SetNewPasswordScreen.minLength} caracteres.'
        : length < SetNewPasswordScreen.minLength
            ? 'Faltan ${SetNewPasswordScreen.minLength - length} caracteres.'
            : 'Largo suficiente.';

    return PopScope(
      canPop: false,
      child: AuthLayout(
        showBack: false,
        title: 'Pon una contraseña nueva',
        message: 'Entraste con un código de un solo uso. Para seguir, elige la contraseña con la '
            'que vas a entrar de ahora en adelante.',
        children: [
          TextField(
            key: const Key('newPasswordField'),
            controller: _password,
            obscureText: _obscure,
            enabled: !_saving,
            autocorrect: false,
            enableSuggestions: false,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: 'Contraseña nueva',
              prefixIcon: const Icon(Icons.lock_outline_rounded),
              suffixIcon: IconButton(
                tooltip: _obscure ? 'Mostrar' : 'Ocultar',
                icon: Icon(_obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 16),
            child: Text(
              hint,
              key: const Key('newPasswordHint'),
              style: TextStyle(
                fontSize: 13,
                color: length >= SetNewPasswordScreen.minLength ? AppColors.emerald : AppColors.onSurfaceMuted,
              ),
            ),
          ),
          TextField(
            key: const Key('confirmPasswordField'),
            controller: _confirm,
            obscureText: _obscure,
            enabled: !_saving,
            autocorrect: false,
            enableSuggestions: false,
            onSubmitted: (_) => _save(),
            decoration: const InputDecoration(
              labelText: 'Repite la contraseña',
              prefixIcon: Icon(Icons.lock_outline_rounded),
            ),
          ),
          if (_submitted && _problem != null) InlineError(_problem!),
          if (_error != null) InlineError(_error!),
          const SizedBox(height: 24),
          AuthPrimaryButton(
            key: const Key('newPasswordSaveButton'),
            label: 'Guardar y entrar',
            loading: _saving,
            onPressed: _save,
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 48,
            child: TextButton(
              key: const Key('newPasswordLogout'),
              style: TextButton.styleFrom(foregroundColor: AppColors.onSurfaceMuted),
              onPressed: _saving ? null : () => ref.read(loginProvider.notifier).logout(),
              child: const Text('Cerrar sesión'),
            ),
          ),
        ],
      ),
    );
  }
}
