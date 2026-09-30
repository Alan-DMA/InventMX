import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../data/auth_repository.dart';
import 'widgets/auth_layout.dart';

/// "¿Olvidaste tu contraseña?" (Centro de soporte, P16).
///
/// Pide un código de un solo uso al correo. La respuesta es la misma exista o
/// no el correo, así que la pantalla nunca dice "ese correo no existe". Desde
/// aquí también se llega con un código que ya mandó soporte, y a escribirle a
/// soporte si ni el correo sirve (P24).
class RecoverAccessScreen extends ConsumerStatefulWidget {
  const RecoverAccessScreen({super.key, this.initialEmail});

  final String? initialEmail;

  @override
  ConsumerState<RecoverAccessScreen> createState() => _RecoverAccessScreenState();
}

class _RecoverAccessScreenState extends ConsumerState<RecoverAccessScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _email = TextEditingController(text: widget.initialEmail ?? '');
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider).requestPasswordRecovery(_email.text.trim());
      if (!mounted) return;
      context.push(AppRoutes.recoverCodePath(_email.text.trim(), sent: true));
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthLayout(
      title: 'Recupera tu acceso',
      message: 'Te enviamos a tu correo un código de un solo uso. Con él entras y eliges una '
          'contraseña nueva.',
      children: [
        Form(
          key: _formKey,
          child: TextFormField(
            key: const Key('recoverEmailField'),
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            textInputAction: TextInputAction.send,
            onFieldSubmitted: (_) => _send(),
            enabled: !_sending,
            decoration: const InputDecoration(
              labelText: 'Correo con el que entras',
              hintText: 'tu@correo.com',
              prefixIcon: Icon(Icons.mail_outline_rounded),
            ),
            validator: (v) {
              final value = v?.trim() ?? '';
              if (value.isEmpty) return 'Escribe tu correo.';
              if (!value.contains('@') || !value.contains('.')) return 'Revisa el correo: le falta algo.';
              return null;
            },
          ),
        ),
        if (_error != null) InlineError(_error!),
        const SizedBox(height: 20),
        AuthPrimaryButton(
          key: const Key('recoverSendButton'),
          label: 'Enviarme un código',
          loading: _sending,
          onPressed: _send,
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 48,
          child: TextButton(
            key: const Key('recoverHaveCode'),
            onPressed: _sending
                ? null
                : () => context.push(AppRoutes.recoverCodePath(_email.text.trim(), sent: false)),
            child: const Text('Ya tengo un código'),
          ),
        ),
        const SizedBox(height: 24),
        const Divider(color: AppColors.border),
        const SizedBox(height: 12),
        const Text(
          '¿Ya no tienes acceso a tu correo?',
          style: TextStyle(fontSize: 14, color: AppColors.onSurface, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        const Text(
          'Escríbenos: revisamos que la cuenta sea tuya y te ayudamos a recuperarla.',
          style: TextStyle(fontSize: 13.5, color: AppColors.onSurfaceMuted, height: 1.4),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            key: const Key('recoverContactSupport'),
            style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 48)),
            onPressed: () => context.push(AppRoutes.publicHelp),
            child: const Text('Escribir a soporte'),
          ),
        ),
      ],
    );
  }
}
