import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../core/admin_http.dart';
import '../../core/admin_theme.dart';
import '../../core/browser/text_download.dart';
import '../../session/admin_session.dart';
import '../../shell/platform_strip.dart';
import '../data/access_repository.dart';
import '../domain/access_models.dart';
import 'access_widgets.dart';

enum _Step { password, code, recovery, enroll, recoveryCodes }

/// Acceso del operador (etapa 3a): contraseña → código de Authenticator. El
/// primer acceso vincula Authenticator (QR + clave) y muestra los 10 códigos
/// de recuperación una sola vez. La franja está desde el primer paso: aquí
/// ya se está en la plataforma, no en una tienda.
///
/// Al abrirse la sesión, el router regresa a `volver` (P34: la sesión vencida
/// vuelve a donde estaba).
class AccessScreen extends ConsumerStatefulWidget {
  const AccessScreen({super.key, this.sessionEnded = false});

  /// Llegó aquí porque su sesión terminó sola (no porque saliera).
  final bool sessionEnded;

  @override
  ConsumerState<AccessScreen> createState() => _AccessScreenState();
}

class _AccessScreenState extends ConsumerState<AccessScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _code = TextEditingController();
  final _recoveryCode = TextEditingController();
  final _codeFocus = FocusNode();

  _Step _step = _Step.password;
  LoginChallenge? _challenge;
  SessionGrant? _pendingGrant;
  bool _busy = false;
  bool _showPassword = false;
  bool _savedCodes = false;
  String? _message;
  AccessMessageTone _tone = AccessMessageTone.error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _code.dispose();
    _recoveryCode.dispose();
    _codeFocus.dispose();
    super.dispose();
  }

  AccessRepository get _repo => ref.read(accessRepositoryProvider);
  DateTime _now() => ref.read(adminClockProvider)();

  void _fail(AdminApiException e, {String? unauthorized}) {
    setState(() {
      _busy = false;
      if (e.statusCode == 423) {
        _tone = AccessMessageTone.locked;
        _message = lockedMessage(e.message, _now());
      } else {
        _tone = AccessMessageTone.error;
        _message = e.statusCode == 401 && unauthorized != null ? unauthorized : e.message;
      }
    });
  }

  // ── Paso 1: contraseña ───────────────────────────────────────────────────

  Future<void> _submitPassword() async {
    if (_email.text.trim().isEmpty || _password.text.isEmpty) {
      setState(() {
        _tone = AccessMessageTone.error;
        _message = 'Escribe tu correo y tu contraseña.';
      });
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final challenge = await _repo.login(_email.text, _password.text);
      if (!mounted) return;
      _password.clear();
      _code.clear();
      setState(() {
        _busy = false;
        _challenge = challenge;
        _step = challenge.needsEnrollment ? _Step.enroll : _Step.code;
      });
    } on AdminApiException catch (e) {
      if (mounted) _fail(e, unauthorized: 'Correo o contraseña incorrectos.');
    }
  }

  /// El reto dura 5 min: pasado ese tiempo el servidor responde igual que a un
  /// código incorrecto, así que se avisa aquí con la verdad.
  bool _challengeExpired() {
    final challenge = _challenge;
    if (challenge == null || _now().isBefore(challenge.expiresAt)) return false;
    setState(() {
      _step = _Step.password;
      _challenge = null;
      _busy = false;
      _tone = AccessMessageTone.info;
      _message = 'Pasaron más de 5 minutos desde tu contraseña. Escríbela de nuevo.';
    });
    return true;
  }

  // ── Paso 2: código ───────────────────────────────────────────────────────

  Future<void> _submitCode(String code) async {
    final challenge = _challenge;
    if (_busy || challenge == null || _challengeExpired()) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final grant = await _repo.verify(challenge.token, code);
      if (!mounted) return;
      if (grant.recoveryCodes != null && grant.recoveryCodes!.isNotEmpty) {
        setState(() {
          _busy = false;
          _pendingGrant = grant;
          _step = _Step.recoveryCodes;
        });
      } else {
        ref.read(adminSessionProvider.notifier).start(grant);
      }
    } on AdminApiException catch (e) {
      if (!mounted) return;
      _code.clear();
      _fail(e, unauthorized: 'Código incorrecto o ya usado. Espera el siguiente que muestre Authenticator.');
      _codeFocus.requestFocus();
    }
  }

  Future<void> _submitRecovery() async {
    final challenge = _challenge;
    final code = _recoveryCode.text.trim();
    if (_busy || challenge == null || _challengeExpired()) return;
    if (code.replaceAll(RegExp(r'[\s-]'), '').length < 10) {
      setState(() {
        _tone = AccessMessageTone.error;
        _message = 'El código de recuperación tiene 10 caracteres, como 3F9A2-C71BE.';
      });
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final grant = await _repo.recover(challenge.token, code);
      if (!mounted) return;
      ref.read(adminSessionProvider.notifier).start(grant, viaRecoveryCode: true);
    } on AdminApiException catch (e) {
      if (mounted) _fail(e, unauthorized: 'Ese código no es válido o ya se usó. Cada código sirve una sola vez.');
    }
  }

  void _backToPassword() => setState(() {
        _step = _Step.password;
        _challenge = null;
        _message = null;
        _code.clear();
        _recoveryCode.clear();
      });

  // ── Códigos de recuperación (primer acceso) ──────────────────────────────

  String get _codesText {
    final codes = _pendingGrant?.recoveryCodes ?? const <String>[];
    return 'Nexus · Panel de plataforma\n'
        'Códigos de recuperación de ${_pendingGrant?.operatorEmail ?? ''}\n'
        'Cada código sirve una sola vez.\n\n${codes.join('\n')}\n';
  }

  Future<void> _copy(String text, String done) async {
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: text));
    messenger.showSnackBar(SnackBar(content: Text(done), duration: const Duration(seconds: 2)));
  }

  void _enterAfterCodes() {
    final grant = _pendingGrant;
    if (grant == null || !_savedCodes) return;
    ref.read(adminSessionProvider.notifier).start(grant);
  }

  // ── UI ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final width = switch (_step) {
      _Step.enroll || _Step.recoveryCodes => 460.0,
      _ => 400.0,
    };
    return Scaffold(
      backgroundColor: AppColors.darkSlate,
      body: Column(
        children: [
          const PlatformStrip(),
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 40, 20, 40),
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: width),
                  child: AutofillGroup(child: _stepBody()),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stepBody() => switch (_step) {
        _Step.password => _passwordStep(),
        _Step.code => _codeStep(),
        _Step.recovery => _recoveryStep(),
        _Step.enroll => _enrollStep(),
        _Step.recoveryCodes => _codesStep(),
      };

  List<Widget> _messageSlot() => [
        if (_message != null) ...[AccessMessage(_message!, tone: _tone), const SizedBox(height: 16)],
      ];

  Widget _passwordStep() => Column(
        key: const Key('accessPasswordStep'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.sessionEnded && _message == null) ...[
            const AccessMessage(
              'Tu sesión de 2 horas terminó. Entra de nuevo y volverás a donde estabas.',
              tone: AccessMessageTone.info,
            ),
            const SizedBox(height: 24),
          ],
          const AccessHeading(
            title: 'Entrar al panel',
            hint: 'Soporte de Nexus. Después de tu contraseña te pediremos el código de Google Authenticator.',
          ),
          const SizedBox(height: 28),
          TextField(
            key: const Key('accessEmail'),
            controller: _email,
            enabled: !_busy,
            autofocus: true,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.username, AutofillHints.email],
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(labelText: 'Correo'),
          ),
          const SizedBox(height: 14),
          TextField(
            key: const Key('accessPassword'),
            controller: _password,
            enabled: !_busy,
            obscureText: !_showPassword,
            autofillHints: const [AutofillHints.password],
            textInputAction: TextInputAction.go,
            onSubmitted: (_) => _submitPassword(),
            decoration: InputDecoration(
              labelText: 'Contraseña',
              suffixIcon: IconButton(
                tooltip: _showPassword ? 'Ocultar contraseña' : 'Mostrar contraseña',
                icon: Icon(_showPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                onPressed: () => setState(() => _showPassword = !_showPassword),
              ),
            ),
          ),
          const SizedBox(height: 20),
          ..._messageSlot(),
          AccessPrimaryButton(
            label: 'Continuar',
            busyLabel: 'Revisando…',
            busy: _busy,
            onPressed: _submitPassword,
          ),
        ],
      );

  Widget _codeStep() => Column(
        key: const Key('accessCodeStep'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AccessHeading(
            title: 'Código de Authenticator',
            hint: 'Abre Google Authenticator y escribe el código de "Nexus Plataforma". '
                'Se envía solo al completar los 6 dígitos.',
          ),
          const SizedBox(height: 28),
          TotpCodeField(controller: _code, focusNode: _codeFocus, enabled: !_busy, onCompleted: _submitCode),
          const SizedBox(height: 20),
          ..._messageSlot(),
          AccessPrimaryButton(
            label: 'Entrar',
            busyLabel: 'Verificando…',
            busy: _busy,
            onPressed: () {
              if (_code.text.length == 6) {
                _submitCode(_code.text);
              } else {
                setState(() {
                  _tone = AccessMessageTone.error;
                  _message = 'Escribe los 6 dígitos del código.';
                });
              }
            },
          ),
          const SizedBox(height: 12),
          _SecondaryLinks(
            children: [
              TextButton(
                key: const Key('accessUseRecovery'),
                onPressed: _busy
                    ? null
                    : () => setState(() {
                          _step = _Step.recovery;
                          _message = null;
                        }),
                child: const Text('Usar un código de recuperación'),
              ),
              TextButton(
                key: const Key('accessBack'),
                onPressed: _busy ? null : _backToPassword,
                style: TextButton.styleFrom(foregroundColor: AppColors.onSurfaceMuted),
                child: const Text('Cambiar de cuenta'),
              ),
            ],
          ),
        ],
      );

  Widget _recoveryStep() => Column(
        key: const Key('accessRecoveryStep'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AccessHeading(
            title: 'Código de recuperación',
            hint: 'Si no tienes el teléfono a la mano, usa uno de los 10 códigos que guardaste al vincular '
                'Authenticator. Cada uno sirve una sola vez.',
          ),
          const SizedBox(height: 28),
          TextField(
            key: const Key('accessRecoveryField'),
            controller: _recoveryCode,
            enabled: !_busy,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            textInputAction: TextInputAction.go,
            onSubmitted: (_) => _submitRecovery(),
            style: adminMonoStyle.copyWith(fontSize: 20, letterSpacing: 2),
            decoration: const InputDecoration(labelText: 'Código de recuperación', hintText: '3F9A2-C71BE'),
          ),
          const SizedBox(height: 20),
          ..._messageSlot(),
          AccessPrimaryButton(label: 'Entrar', busyLabel: 'Verificando…', busy: _busy, onPressed: _submitRecovery),
          const SizedBox(height: 12),
          _SecondaryLinks(
            children: [
              TextButton(
                key: const Key('accessUseTotp'),
                onPressed: _busy
                    ? null
                    : () => setState(() {
                          _step = _Step.code;
                          _message = null;
                        }),
                child: const Text('Usar Authenticator'),
              ),
            ],
          ),
        ],
      );

  Widget _enrollStep() {
    final challenge = _challenge!;
    return Column(
      key: const Key('accessEnrollStep'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const AccessHeading(
          title: 'Vincula Google Authenticator',
          hint: 'Es tu primer acceso: el panel pide un código del teléfono además de la contraseña. '
              'En Authenticator toca + y "Escanear un código QR".',
        ),
        const SizedBox(height: 24),
        EnrollmentBlock(
          otpauthUri: challenge.otpauthUri!,
          manualSecret: challenge.manualSecret ?? '',
          onCopySecret: () => _copy(challenge.manualSecret ?? '', 'Clave copiada'),
        ),
        const SizedBox(height: 24),
        const Text(
          'Escribe el código de 6 dígitos que aparece en Authenticator para confirmar:',
          style: TextStyle(fontSize: 14, color: AppColors.onSurface, height: 1.4),
        ),
        const SizedBox(height: 12),
        TotpCodeField(controller: _code, focusNode: _codeFocus, enabled: !_busy, onCompleted: _submitCode),
        const SizedBox(height: 20),
        ..._messageSlot(),
        AccessPrimaryButton(
          label: 'Vincular y continuar',
          busyLabel: 'Vinculando…',
          busy: _busy,
          onPressed: () {
            if (_code.text.length == 6) _submitCode(_code.text);
          },
        ),
        const SizedBox(height: 12),
        _SecondaryLinks(
          children: [
            TextButton(
              onPressed: _busy ? null : _backToPassword,
              style: TextButton.styleFrom(foregroundColor: AppColors.onSurfaceMuted),
              child: const Text('Cambiar de cuenta'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _codesStep() {
    final codes = _pendingGrant?.recoveryCodes ?? const <String>[];
    return Column(
      key: const Key('accessCodesStep'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const AccessHeading(
          title: 'Guarda tus códigos de recuperación',
          hint: 'Si pierdes el teléfono, cada código te deja entrar una vez en lugar de Authenticator. '
              'No los volveremos a mostrar.',
        ),
        const SizedBox(height: 24),
        RecoveryCodesGrid(codes: codes),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            OutlinedButton.icon(
              key: const Key('accessCopyCodes'),
              onPressed: () => _copy(_codesText, 'Códigos copiados'),
              icon: const Icon(Icons.copy_rounded, size: 18),
              label: const Text('Copiar todos'),
            ),
            if (canDownloadText)
              OutlinedButton.icon(
                key: const Key('accessDownloadCodes'),
                onPressed: () => downloadText('nexus-codigos-recuperacion.txt', _codesText),
                icon: const Icon(Icons.download_rounded, size: 18),
                label: const Text('Descargar .txt'),
              ),
          ],
        ),
        const SizedBox(height: 20),
        const AccessMessage(
          'Guárdalos fuera de esta computadora (gestor de contraseñas o papel). Si cierras esta pestaña sin '
          'guardarlos, habrá que volver a vincular Authenticator.',
          tone: AccessMessageTone.info,
        ),
        const SizedBox(height: 16),
        CheckboxListTile(
          key: const Key('accessSavedCodes'),
          value: _savedCodes,
          onChanged: (value) => setState(() => _savedCodes = value ?? false),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
          title: const Text(
            'Ya los guardé en un lugar seguro',
            style: TextStyle(fontSize: 14.5, color: AppColors.onSurface),
          ),
        ),
        const SizedBox(height: 12),
        AccessPrimaryButton(
          label: 'Entrar al panel',
          busyLabel: 'Entrando…',
          busy: false,
          onPressed: _savedCodes ? _enterAfterCodes : null,
        ),
      ],
    );
  }
}

class _SecondaryLinks extends StatelessWidget {
  const _SecondaryLinks({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Wrap(
        alignment: WrapAlignment.spaceBetween,
        spacing: 8,
        children: children,
      );
}
