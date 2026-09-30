import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../data/auth_repository.dart';
import 'login_provider.dart';
import 'widgets/auth_layout.dart';

/// "Revisa tu correo" / "Escribe tu código" (Centro de soporte, P16).
///
/// Un solo camino para el código que pidió el tendero (30 min) y el que le
/// mandó soporte tras validarlo (24 h): no necesita saber cuál es cuál. Al
/// entrar, el router lo lleva a "Pon una contraseña nueva".
class EnterCodeScreen extends ConsumerStatefulWidget {
  const EnterCodeScreen({super.key, this.initialEmail, this.justSent = false});

  final String? initialEmail;

  /// Llegó de "Enviarme un código": el reenvío arranca con espera.
  final bool justSent;

  @override
  ConsumerState<EnterCodeScreen> createState() => _EnterCodeScreenState();
}

class _EnterCodeScreenState extends ConsumerState<EnterCodeScreen> {
  /// Espera entre reenvíos; el servidor además acepta 3 por hora.
  static const resendWait = Duration(seconds: 60);
  static const maxSends = 3;

  late final _email = TextEditingController(text: widget.initialEmail ?? '');
  final _code = TextEditingController();
  bool _entering = false;
  String? _error;
  late int _sends = widget.justSent ? 1 : 0;
  int _secondsLeft = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (widget.justSent) _startWait();
    _code.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _timer?.cancel();
    _email.dispose();
    _code.dispose();
    super.dispose();
  }

  void _startWait() {
    _timer?.cancel();
    setState(() => _secondsLeft = resendWait.inSeconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _secondsLeft = (_secondsLeft - 1).clamp(0, resendWait.inSeconds));
      if (_secondsLeft == 0) t.cancel();
    });
  }

  bool get _codeComplete => AccessCodeFormatter.raw(_code.text).length == AccessCodeFormatter.length;
  bool get _emailLooksValid => _email.text.trim().contains('@');

  Future<void> _enter() async {
    if (!_codeComplete || !_emailLooksValid) return;
    setState(() {
      _entering = true;
      _error = null;
    });
    try {
      await ref.read(loginProvider.notifier).loginWithCode(email: _email.text.trim(), code: _code.text);
      // El router ya redirige a "Pon una contraseña nueva".
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _entering = false);
    }
  }

  Future<void> _resend() async {
    if (!_emailLooksValid) {
      setState(() => _error = 'Escribe tu correo para enviarte el código.');
      return;
    }
    setState(() => _error = null);
    try {
      await ref.read(authRepositoryProvider).requestPasswordRecovery(_email.text.trim());
      if (!mounted) return;
      setState(() => _sends++);
      _startWait();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Te enviamos otro código. Usa el más reciente.'),
        behavior: SnackBarBehavior.floating,
      ));
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final email = _email.text.trim();
    return AuthLayout(
      title: widget.justSent ? 'Revisa tu correo' : 'Escribe tu código',
      message: widget.justSent
          ? 'Si ${email.isEmpty ? 'tu correo' : email} tiene una cuenta en Nexus, te llegó un código de '
              '8 caracteres. Vence en 30 minutos; revisa también en spam.'
          : 'Escribe el código que te llegó al correo. Si te lo envió soporte, vence en 24 horas.',
      children: [
        TextField(
          key: const Key('codeEmailField'),
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          enabled: !_entering,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            labelText: 'Correo con el que entras',
            prefixIcon: Icon(Icons.mail_outline_rounded),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          key: const Key('codeField'),
          controller: _code,
          enabled: !_entering,
          autocorrect: false,
          enableSuggestions: false,
          keyboardType: TextInputType.visiblePassword,
          textCapitalization: TextCapitalization.characters,
          textAlign: TextAlign.center,
          inputFormatters: [AccessCodeFormatter()],
          onSubmitted: (_) => _enter(),
          style: const TextStyle(
            fontFamily: 'monospace',
            fontSize: 28,
            fontWeight: FontWeight.w700,
            letterSpacing: 4,
            color: AppColors.onSurface,
          ),
          decoration: const InputDecoration(
            labelText: 'Código',
            hintText: 'XXXX-XXXX',
            floatingLabelAlignment: FloatingLabelAlignment.center,
          ),
        ),
        if (_error != null) InlineError(_error!),
        const SizedBox(height: 20),
        AuthPrimaryButton(
          key: const Key('codeEnterButton'),
          label: 'Entrar',
          loading: _entering,
          onPressed: _codeComplete && _emailLooksValid ? _enter : null,
        ),
        const SizedBox(height: 8),
        if (_sends >= maxSends)
          const Padding(
            key: Key('codeSendsExhausted'),
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'Ya te enviamos varios códigos. Si no llegan, escríbenos y lo revisamos.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13.5, color: AppColors.onSurfaceMuted, height: 1.4),
            ),
          )
        else
          SizedBox(
            height: 48,
            child: TextButton(
              key: const Key('codeResendButton'),
              onPressed: _secondsLeft > 0 || _entering ? null : _resend,
              child: Text(
                _secondsLeft > 0
                    ? 'Reenviar en $_secondsLeft s'
                    : (_sends == 0 ? 'Enviarme un código' : 'Reenviar código'),
              ),
            ),
          ),
        const SizedBox(height: 16),
        const Divider(color: AppColors.border),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            key: const Key('codeContactSupport'),
            style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 48)),
            onPressed: () => context.push(AppRoutes.publicHelp),
            child: const Text('¿No te llega? Escríbenos'),
          ),
        ),
      ],
    );
  }
}
