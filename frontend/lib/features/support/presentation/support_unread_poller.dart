import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/login_provider.dart';
import 'support_provider.dart';

/// Cada cuánto se pregunta (sustituible en tests).
final supportPollIntervalProvider = Provider<Duration>((_) => const Duration(seconds: 60));

/// Mientras la app está en pantalla pregunta cada 60 s si soporte respondió, y
/// también al volver a la app. Sólo refresca insignias y avisos si la cuenta
/// cambió (una consulta ligera, `/support/cases/unread`). En segundo plano se
/// detiene: las notificaciones del sistema (push) siguen fuera del alcance.
class SupportUnreadPoller extends ConsumerStatefulWidget {
  const SupportUnreadPoller({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<SupportUnreadPoller> createState() => _SupportUnreadPollerState();
}

class _SupportUnreadPollerState extends ConsumerState<SupportUnreadPoller> with WidgetsBindingObserver {
  Timer? _timer;
  bool _checking = false;

  /// Sólo "volver a la app" cuenta si antes se fue de verdad a segundo plano
  /// (no cualquier aviso de ciclo de vida, p. ej. al arrancar).
  bool _wasInBackground = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  void _start() {
    _timer?.cancel();
    _timer = Timer.periodic(ref.read(supportPollIntervalProvider), (_) => _check());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _wasInBackground) {
      _wasInBackground = false;
      _check();
      _start();
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      _wasInBackground = true;
      _timer?.cancel();
    }
  }

  Future<void> _check() async {
    if (_checking || !mounted) return;
    if (!ref.read(sessionProvider) || ref.read(mustChangePasswordProvider)) return;
    _checking = true;
    try {
      final fresh = await ref.read(supportRepositoryProvider).unreadCount();
      if (!mounted) return;
      if (fresh != ref.read(supportUnreadProvider).valueOrNull) {
        ref.invalidate(supportUnreadProvider);
        ref.invalidate(supportCasesProvider);
      }
    } catch (_) {
      // Sin red: las insignias se quedan con el último número conocido
    } finally {
      _checking = false;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
