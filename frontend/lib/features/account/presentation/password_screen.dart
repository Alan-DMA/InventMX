import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import 'account_provider.dart';

/// Cambio de contraseña.
///
/// Mock por ahora: el backend legacy sólo expone login y refresh. Queda
/// propuesto `POST /api/v1/auth/change-password` — ver [AccountRepository].
class PasswordScreen extends ConsumerStatefulWidget {
  const PasswordScreen({super.key});

  @override
  ConsumerState<PasswordScreen> createState() => _PasswordScreenState();
}

class _PasswordScreenState extends ConsumerState<PasswordScreen> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();

  bool _obscure = true;
  bool _isSaving = false;
  String? _error;

  static const _minLength = 8;

  @override
  void initState() {
    super.initState();
    for (final c in [_current, _next, _confirm]) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  bool get _isValid =>
      _current.text.isNotEmpty &&
      _next.text.length >= _minLength &&
      _next.text == _confirm.text;

  /// Se explica en el momento, no al enviar: el usuario no debería llegar al
  /// botón para enterarse de que su contraseña es corta.
  String? get _liveHint {
    if (_next.text.isNotEmpty && _next.text.length < _minLength) {
      return 'Debe tener al menos $_minLength caracteres.';
    }
    if (_confirm.text.isNotEmpty && _next.text != _confirm.text) {
      return 'Las dos contraseñas nuevas no coinciden.';
    }
    return null;
  }

  Future<void> _submit() async {
    if (!_isValid || _isSaving) return;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    setState(() {
      _isSaving = true;
      _error = null;
    });
    try {
      await ref.read(accountRepositoryProvider).changePassword(
            currentPassword: _current.text,
            newPassword: _next.text,
          );
      messenger.showSnackBar(
        const SnackBar(content: Text('Tu contraseña quedó cambiada.')),
      );
      navigator.pop();
    } catch (e) {
      setState(() {
        _isSaving = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final hint = _liveHint;

    return Scaffold(
      backgroundColor: AppColors.darkSlate,
      appBar: AppBar(
        backgroundColor: AppColors.darkSlate,
        title: const Text('Contraseña'),
        actions: [
          IconButton(
            onPressed: () => setState(() => _obscure = !_obscure),
            icon: Icon(
              _obscure
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
              color: AppColors.onSurfaceMuted,
            ),
            tooltip: _obscure ? 'Mostrar' : 'Ocultar',
          ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
            16, 16, 16, 32 + MediaQuery.of(context).padding.bottom),
        children: [
          _field(
            key: const Key('passwordCurrentField'),
            controller: _current,
            label: 'Contraseña actual',
            hint: 'La que usas hoy para entrar',
          ),
          const SizedBox(height: 22),
          _field(
            key: const Key('passwordNewField'),
            controller: _next,
            label: 'Contraseña nueva',
            hint: 'Al menos $_minLength caracteres',
          ),
          const SizedBox(height: 22),
          _field(
            key: const Key('passwordConfirmField'),
            controller: _confirm,
            label: 'Repite la nueva',
            hint: 'Para asegurar que no hubo un dedazo',
          ),
          if (hint != null) ...[
            const SizedBox(height: 16),
            Text(
              hint,
              key: const Key('passwordLiveHint'),
              style: const TextStyle(fontSize: 12.5, color: AppColors.warning),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(
              _error!,
              key: const Key('passwordError'),
              style: const TextStyle(fontSize: 13, color: AppColors.error),
            ),
          ],
          const SizedBox(height: 30),
          ElevatedButton(
            key: const Key('passwordSaveButton'),
            onPressed: _isValid && !_isSaving ? _submit : null,
            child: _isSaving
                ? const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.5, color: AppColors.darkSlate),
                  )
                : const Text('Cambiar contraseña'),
          ),
        ],
      ),
    );
  }

  Widget _field({
    required Key key,
    required TextEditingController controller,
    required String label,
    required String hint,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: AppColors.onSurface,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          key: key,
          controller: controller,
          obscureText: _obscure,
          style: const TextStyle(color: AppColors.onSurface, fontSize: 15),
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: const Icon(Icons.lock_outline_rounded, size: 18),
          ),
        ),
      ],
    );
  }
}
