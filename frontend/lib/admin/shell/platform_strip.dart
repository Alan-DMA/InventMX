import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../core/admin_colors.dart';
import '../session/admin_session.dart';

/// Franja fija "Panel de plataforma": dice dónde estás (nunca dentro de una
/// tienda), quién está en sesión y cuánto le queda. A 10 min del vencimiento
/// pasa a ámbar (P34); al llegar a cero da la sesión por vencida y el router
/// lleva al acceso, que regresa a donde estaba.
class PlatformStrip extends ConsumerStatefulWidget {
  const PlatformStrip({super.key});

  static const height = 40.0;
  static const warnBefore = Duration(minutes: 10);

  @override
  ConsumerState<PlatformStrip> createState() => _PlatformStripState();
}

class _PlatformStripState extends ConsumerState<PlatformStrip> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 15), (_) => _tick());
  }

  void _tick() {
    if (!mounted) return;
    final session = ref.read(adminSessionProvider).session;
    if (session != null && session.remaining(ref.read(adminClockProvider)()) <= Duration.zero) {
      ref.read(adminSessionProvider.notifier).expire();
      return;
    }
    setState(() {});
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(adminSessionProvider).session;
    final remaining = session?.remaining(ref.read(adminClockProvider)());
    final warning = remaining != null && remaining <= PlatformStrip.warnBefore;
    final accent = warning ? AdminColors.amber : AdminColors.indigo;
    // En pantalla chica se abrevia; nunca se pierde la palabra "plataforma"
    final compact = MediaQuery.sizeOf(context).width < 640;
    final sessionText = remaining == null
        ? ''
        : switch ((warning, compact)) {
            (true, false) => 'Tu sesión vence en ${_remainingText(remaining)} · lo que escribas se guarda',
            (true, true) => 'Vence en ${_remainingText(remaining)}',
            (false, false) => 'Sesión: ${_remainingText(remaining)}',
            (false, true) => _remainingText(remaining),
          };

    return Semantics(
      container: true,
      label: 'Panel de plataforma',
      child: Container(
        key: const Key('platformStrip'),
        height: PlatformStrip.height,
        padding: const EdgeInsets.only(left: 16, right: 8),
        decoration: BoxDecoration(
          color: warning ? AdminColors.stripWarning : AdminColors.strip,
          border: Border(bottom: BorderSide(color: accent.withValues(alpha: 0.4))),
        ),
        child: Row(
          children: [
            Icon(Icons.shield_outlined, size: 16, color: accent),
            const SizedBox(width: 8),
            Text(
              compact ? 'PLATAFORMA' : 'PANEL DE PLATAFORMA',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1.1, color: accent),
            ),
            if (session != null && !compact) ...[
              const _Dot(),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 220),
                child: Text(
                  session.shortName,
                  key: const Key('platformStripOperator'),
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, color: AppColors.onSurface, fontWeight: FontWeight.w500),
                ),
              ),
            ],
            const SizedBox(width: 16),
            if (session != null && remaining != null) ...[
              // Ocupa el resto y se pega a la derecha, junto a "Salir"
              Expanded(
                child: Text(
                  sessionText,
                  key: const Key('platformStripSession'),
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: TextStyle(
                    fontSize: 13,
                    color: warning ? AdminColors.amber : AppColors.onSurfaceMuted,
                    fontWeight: warning ? FontWeight.w600 : FontWeight.w400,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                key: const Key('platformStripSignOut'),
                onPressed: () => ref.read(adminSessionProvider.notifier).signOut(),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.onSurface,
                  minimumSize: const Size(0, 32),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                child: const Text('Salir'),
              ),
            ] else ...[
              const Spacer(),
              if (!compact)
                const Padding(
                  padding: EdgeInsets.only(right: 8),
                  child: Text('Acceso de fundadores', style: TextStyle(fontSize: 13, color: AppColors.onSurfaceMuted)),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

/// "1 h 42 min", "38 min", "menos de 1 min".
String _remainingText(Duration remaining) {
  final minutes = remaining.inMinutes;
  if (minutes < 1) return 'menos de 1 min';
  if (minutes < 60) return '$minutes min';
  final rest = minutes % 60;
  return rest == 0 ? '${minutes ~/ 60} h' : '${minutes ~/ 60} h $rest min';
}

class _Dot extends StatelessWidget {
  const _Dot();

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(horizontal: 10),
        child: Text('·', style: TextStyle(fontSize: 13, color: AppColors.onSurfaceMuted)),
      );
}
