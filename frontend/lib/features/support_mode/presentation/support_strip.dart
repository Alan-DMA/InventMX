import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/app_colors.dart';
import '../domain/support_session.dart';
import 'support_session_controller.dart';

/// Colores de plataforma de DESIGN.md ("Franja de plataforma"): la pestaña de
/// soporte es la única pieza fuera del panel que los usa.
abstract final class SupportColors {
  static const indigo = Color(0xFF818CF8);
  static const indigoPressed = Color(0xFF6366F1);
  static const strip = Color(0xFF1F2747);
  static const stripWarning = Color(0xFF2F2A26);
}

const _nbsp = '\u00A0';

/// La franja fija de la pestaña de soporte (etapa 4): dice siempre que es una
/// visita de sólo lectura, de qué tienda y cuánto le queda según el servidor.
class SupportStrip extends ConsumerStatefulWidget {
  const SupportStrip({super.key});

  static const height = 40.0;

  @override
  ConsumerState<SupportStrip> createState() => _SupportStripState();
}

class _SupportStripState extends ConsumerState<SupportStrip> {
  Timer? _tick;
  Timer? _noticeTimer;
  String? _extendError;
  bool _ending = false;

  @override
  void initState() {
    super.initState();
    // Minutos en la franja: basta con mirar cada 5 s; a 0 se confirma con el servidor
    _tick = Timer.periodic(const Duration(seconds: 5), (_) => _onTick());
  }

  @override
  void dispose() {
    _tick?.cancel();
    _noticeTimer?.cancel();
    super.dispose();
  }

  void _onTick() {
    if (!mounted) return;
    final phase = ref.read(supportSessionProvider);
    if (phase is SupportActive && !phase.status.expiresAt.isAfter(ref.read(supportClockProvider)())) {
      ref.read(supportSessionProvider.notifier).refresh();
    }
    setState(() {});
  }

  Future<void> _extend() async {
    setState(() => _extendError = null);
    final message = await ref.read(supportSessionProvider.notifier).extend();
    if (mounted && message != null) setState(() => _extendError = message);
  }

  Future<void> _end() async {
    setState(() => _ending = true);
    await ref.read(supportSessionProvider.notifier).end();
    if (mounted) setState(() => _ending = false);
  }

  @override
  Widget build(BuildContext context) {
    final phase = ref.watch(supportSessionProvider);
    final notice = ref.watch(supportNoticeProvider);
    ref.listen<String?>(supportNoticeProvider, (_, next) {
      _noticeTimer?.cancel();
      if (next != null) {
        _noticeTimer = Timer(const Duration(seconds: 4), () {
          if (mounted) ref.read(supportNoticeProvider.notifier).state = null;
        });
      }
    });

    final now = ref.watch(supportClockProvider)();
    final status = phase is SupportActive ? phase.status : null;
    final remaining = status?.expiresAt.difference(now);
    final warning = remaining != null && remaining <= SupportSessionStatus.warnWindow;
    final ink = warning ? AppColors.warning : SupportColors.indigo;
    final compact = MediaQuery.sizeOf(context).width < 640;
    final extendable = status?.extendableAt(now) ?? false;
    final noticeText = notice ?? _extendError;
    // Compacta (teléfono): "SOPORTE" nunca se pierde ("sólo lectura" a secas es un estado
    // de la propia tienda); con el botón de extender no cabe más
    final title = phase is SupportClosed
        ? (compact ? 'SOPORTE · TERMINADO' : 'MODO SOPORTE · TERMINADO')
        : compact
            ? (extendable ? 'SOPORTE' : 'SOPORTE · SÓLO LECTURA')
            : 'MODO SOPORTE · SÓLO LECTURA';
    // En el teléfono el aviso de un rechazo reemplaza al título mientras dura
    final compactNotice = compact && noticeText != null;

    return Semantics(
      container: true,
      label: status == null
          ? 'Modo soporte, sólo lectura'
          : 'Modo soporte, sólo lectura, ${status.tenantName}, ${_remainingText(remaining!)}',
      // El paso a ámbar es el único momento en que la franja advierte: se nota, sin saltar
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        key: const Key('supportStrip'),
        height: SupportStrip.height,
        padding: EdgeInsets.only(left: compact ? 12 : 16, right: compact ? 6 : 8),
        decoration: BoxDecoration(
          color: warning ? SupportColors.stripWarning : SupportColors.strip,
          border: Border(bottom: BorderSide(color: ink.withValues(alpha: 0.4))),
        ),
        child: Row(
          children: [
            ExcludeSemantics(child: Icon(Icons.shield_outlined, size: 16, color: ink)),
            const SizedBox(width: 8),
            // El título y la tienda se quedan con todo el espacio libre; el tiempo y
            // los botones van pegados a la derecha
            Expanded(
              child: Row(
                children: [
                  // El título nunca se recorta en escritorio; en el teléfono, como último recurso
                  if (!compactNotice)
                    if (compact) Flexible(child: _title(title, ink, compact)) else _title(title, ink, compact),
                  // El aviso de un rechazo ocupa, mientras dura, el lugar del nombre de la tienda
                  if (noticeText != null) ...[
                    if (!compactNotice) const SizedBox(width: 16),
                    Flexible(
                      child: Semantics(
                        liveRegion: true,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const ExcludeSemantics(
                                child: Icon(Icons.block_rounded, size: 15, color: AppColors.onSurface)),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(compact && notice != null ? 'No se guardó nada' : noticeText,
                                  key: const Key('supportStripNotice'),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.inter(
                                      fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.onSurface)),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ] else if (!compact && status != null) ...[
                    const SizedBox(width: 16),
                    Flexible(
                      child: ExcludeSemantics(
                        child: Text(status.tenantName,
                            key: const Key('supportStripTenant'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                                fontSize: 13.5, fontWeight: FontWeight.w600, color: AppColors.onSurface)),
                      ),
                    ),
                  ],
                  const SizedBox(width: 12),
                ],
              ),
            ),
            if (status != null) ...[
              ExcludeSemantics(
                child: Text(_remainingText(remaining!, compact: compact),
                    key: const Key('supportStripRemaining'),
                    style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: warning ? AppColors.warning : AppColors.onSurface,
                        fontFeatures: const [FontFeature.tabularFigures()])),
              ),
              if (extendable) ...[
                const SizedBox(width: 4),
                TextButton(
                  key: const Key('supportStripExtend'),
                  onPressed: _extend,
                  style: TextButton.styleFrom(
                    foregroundColor: ink,
                    textStyle: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600),
                    padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 10),
                    minimumSize: const Size(0, 32),
                  ),
                  child: Text(compact ? '+30${_nbsp}min' : 'Seguir 30${_nbsp}min más'),
                ),
              ],
              const SizedBox(width: 8),
              OutlinedButton(
                key: const Key('supportStripEnd'),
                onPressed: _ending ? null : _end,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.onSurface,
                  side: BorderSide(color: ink.withValues(alpha: 0.6)),
                  textStyle: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600),
                  padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 14),
                  minimumSize: const Size(0, 32),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text('Terminar'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static Widget _title(String title, Color ink, bool compact) => ExcludeSemantics(
        child: Text(title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(
                fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: compact ? 0.6 : 1.1, color: ink)),
      );

  static String _remainingText(Duration remaining, {bool compact = false}) {
    if (remaining.inSeconds <= 0) return 'terminando…';
    if (remaining.inMinutes < 1) return compact ? '<1${_nbsp}min' : 'queda menos de 1${_nbsp}min';
    // Hacia arriba: con 29:10 por delante se leen 30 min, no 29
    final minutes = (remaining.inSeconds / 60).ceil();
    return compact ? '$minutes${_nbsp}min' : 'quedan $minutes${_nbsp}min';
  }
}
