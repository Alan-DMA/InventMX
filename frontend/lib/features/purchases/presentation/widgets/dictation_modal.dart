import 'dart:math' show max;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/voice_dictation_helper.dart';
import '../purchases_provider.dart';

/// Modal de dictado de uno o más productos — iteración de Tarea 12.2.3 tras
/// descartar CRFsuite como método de extracción (ver
/// `docs/architecture/registro_implementacion.md`, sección de Tarea 12.2.3,
/// y `prototypes/dictation_crf/` para el detalle de esa exploración).
///
/// Reemplaza el botón de dictado que antes vivía embebido en el campo
/// "nombre" del formulario de línea — el ícono que abre este modal vive
/// junto al título de la sección "Agregar producto", para comunicar que es
/// una acción de nivel de sección (llenar varios productos), no un helper
/// de un solo campo.
///
/// Flujo con 2 puntos de validación explícitos (decisión de producto, no
/// negociable): (1) el transcript se revisa/edita ANTES de interpretarse —
/// desde la sexta iteración, en vivo mientras el micrófono sigue activo, en
/// el mismo campo que después se revisa al detener —, (2) los productos ya
/// segmentados se revisan/editan en la tabla principal después de cerrarse
/// el modal — este modal nunca inserta directo sin pasar por (1).
Future<List<DictatedProductInput>?> showDictationModal(BuildContext context) {
  return showModalBottomSheet<List<DictatedProductInput>>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const DictationModal(),
  );
}

enum _ModalState { idle, listening, stopped, error }

class DictationModal extends ConsumerStatefulWidget {
  const DictationModal({super.key});

  @override
  ConsumerState<DictationModal> createState() => _DictationModalState();
}

class _DictationModalState extends ConsumerState<DictationModal> {
  _ModalState _state = _ModalState.idle;
  String _partialTranscript = '';
  final _transcriptCtrl = TextEditingController();
  final _transcriptFocus = FocusNode();

  static const _segmenter = DictationSegmenter();
  static const _parser = VoiceDictationParser();

  @override
  void dispose() {
    _transcriptCtrl.dispose();
    _transcriptFocus.dispose();
    super.dispose();
  }

  // ── Lógica ─────────────────────────────────────────────────────────────
  //
  // Un segmento por toque: "Volver a grabar" arranca una sola sesión del
  // motor; cuando cierra (silencio de `pauseFor`, error o "Detener") lo
  // captado se anexa a `_transcriptCtrl` — que desde ahí es del usuario,
  // editable y fuera del alcance del motor — y el modal queda en "detenido"
  // hasta el siguiente toque. Sin reinicio automático: el bucle de
  // reintentos (bip, silencio, bip…) no dejaba al usuario pensar qué decir
  // (bugs reales, ver bitácora Tarea 12.2.3, iteraciones 4-8).

  // Entre que se pide `listen()` y el micrófono capta de verdad hay un hueco
  // (arranque del reconocedor) en el que lo dicho se pierde — se distingue
  // visual y hápticamente para que el usuario sepa cuándo hablar sin mirar
  // la pantalla (bug real reportado: "no sé cuándo está tomando mi voz").
  bool _micLive = false;

  Future<void> _startListening({bool resume = false}) async {
    final service = ref.read(voiceDictationServiceProvider);
    final messenger = ScaffoldMessenger.of(context);

    final ready = await service.initialize();
    if (!mounted) return;
    if (!ready) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('El dictado no está disponible. Revisa el permiso '
              'de micrófono en los ajustes del teléfono.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() {
      _state = _ModalState.listening;
      _partialTranscript = '';
      _micLive = false;
      if (!resume) _transcriptCtrl.clear();
    });

    await service.listen(
      onListening: () {
        if (!mounted || _state != _ModalState.listening) return;
        setState(() => _micLive = true);
        HapticFeedback.lightImpact();
      },
      onResult: (transcript, isFinal) {
        // Un resultado tardío tras "Detener" (el motor entrega el final
        // después de que `stop()` retornó) ya se anexó en `_finishListening`
        // — aceptarlo aquí lo duplicaría.
        if (!mounted || _state != _ModalState.listening) return;
        // Dentro del segmento en curso el motor sigue pudiendo revisar su
        // hipótesis hacia atrás (parcial o final más corto que el anterior)
        // — nunca se acepta algo más corto que lo mejor ya visto; el
        // usuario corrige a mano en el campo si el motor de verdad oyó mal.
        if (transcript.trim().length >= _partialTranscript.trim().length) {
          setState(() => _partialTranscript = transcript);
        }
        if (isFinal) _finishListening();
      },
      // Un error de plataforma (red, timeout del reconocedor) cierra el
      // segmento igual que el silencio: lo captado hasta ahí se conserva y
      // el usuario decide si vuelve a grabar.
      onError: () {
        if (!mounted || _state != _ModalState.listening) return;
        _finishListening();
      },
    );
  }

  /// Anexa al texto ACTUAL del campo (que puede traer ediciones a mano del
  /// usuario, hechas mientras el micrófono seguía activo) sin mover su
  /// cursor/selección si está editando en ese instante.
  void _appendSegment(String segment) {
    final current = _transcriptCtrl.text;
    final needsSpace = current.isNotEmpty && !current.endsWith(' ');
    final next = current.isEmpty ? segment : '$current${needsSpace ? ' ' : ''}$segment';

    final selection = _transcriptCtrl.selection;
    final keepSelection = selection.isValid && selection.end <= current.length;
    _transcriptCtrl.value = TextEditingValue(
      text: next,
      selection: keepSelection
          ? selection
          : TextSelection.collapsed(offset: next.length),
    );
  }

  Future<void> _stopListening() async {
    await ref.read(voiceDictationServiceProvider).stop();
    // Si `stop()` ya disparó `onResult(isFinal: true)`, el modal ya está en
    // "stopped" y este chequeo no hace nada — cubre el caso en que el motor
    // no dispara callback al detenerse.
    if (mounted && _state == _ModalState.listening) _finishListening();
  }

  void _finishListening() {
    final pending = _partialTranscript.trim();
    if (pending.isNotEmpty) _appendSegment(pending);
    setState(() {
      _partialTranscript = '';
      _micLive = false;
      _state = _ModalState.stopped;
    });
  }

  void _submit() {
    final text = _transcriptCtrl.text.trim();
    final segments = _segmenter.segment(text);
    final parsed = segments.map(_parser.parse).toList();
    final hasUsableResult = parsed.any((p) => !p.isEmpty);

    if (!hasUsableResult) {
      setState(() => _state = _ModalState.error);
      return;
    }

    Navigator.of(context).pop(parsed);
  }

  void _clearAll() {
    setState(() {
      _transcriptCtrl.clear();
      _partialTranscript = '';
      _state = _ModalState.idle;
    });
  }

  void _editTranscriptFromError() {
    setState(() => _state = _ModalState.stopped);
    _transcriptFocus.requestFocus();
  }

  // ── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final bottomInset = max(mq.viewInsets.bottom, mq.padding.bottom);

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(24, 12, 24, 24 + bottomInset),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _handle(),
            _header(),
            const SizedBox(height: 20),
            switch (_state) {
              _ModalState.idle => _idleBody(),
              _ModalState.listening => _listeningBody(),
              _ModalState.stopped => _stoppedBody(),
              _ModalState.error => _errorBody(),
            },
          ],
        ),
      ),
    );
  }

  Widget _handle() => Center(
        child: Container(
          width: 40,
          height: 4,
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: AppColors.border,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      );

  Widget _header() => Row(
        children: [
          const Expanded(
            child: Text(
              'Dictar productos',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.onSurface),
            ),
          ),
          IconButton(
            key: const Key('dictationModalCloseButton'),
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded,
                size: 22, color: AppColors.onSurfaceMuted),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      );

  // ── Estado: instructivo ───────────────────────────────────────────────

  Widget _idleBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Di así, uno tras otro:',
          style: TextStyle(fontSize: 14, color: AppColors.onSurfaceMuted),
        ),
        const SizedBox(height: 10),
        _exampleCard(),
        const SizedBox(height: 14),
        const Text(
          'Cantidad → producto → precio. Di "también" entre cada producto.',
          style: TextStyle(
              fontSize: 12.5,
              color: AppColors.onSurfaceMuted,
              height: 1.4),
        ),
        const SizedBox(height: 24),
        _micButton(
          key: const Key('dictationModalStartButton'),
          icon: Icons.mic_none_rounded,
          label: 'Toca para hablar',
          onPressed: _startListening,
        ),
      ],
    );
  }

  /// Resalta el conector "también" dentro de la frase de ejemplo — es la
  /// única palabra que el usuario realmente necesita memorizar del molde.
  Widget _exampleCard() {
    const example = kDictationFormatExample;
    final idx = example.indexOf('también');
    final spans = idx < 0
        ? const [TextSpan(text: example)]
        : [
            TextSpan(text: example.substring(0, idx)),
            TextSpan(
              text: example.substring(idx, idx + 'también'.length),
              style: const TextStyle(
                  color: AppColors.skyBlue, fontWeight: FontWeight.w700),
            ),
            TextSpan(text: example.substring(idx + 'también'.length)),
          ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Text.rich(
        TextSpan(
          style: const TextStyle(
              fontSize: 14.5,
              color: AppColors.onSurface,
              fontStyle: FontStyle.italic,
              height: 1.4),
          children: [const TextSpan(text: '"'), ...spans, const TextSpan(text: '"')],
        ),
      ),
    );
  }

  // ── Estado: escuchando ─────────────────────────────────────────────────

  Widget _listeningBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Lo que llevas dicho — toca para corregir',
          style: TextStyle(fontSize: 12.5, color: AppColors.onSurfaceMuted),
        ),
        const SizedBox(height: 10),
        _transcriptPanel(live: true),
        const SizedBox(height: 24),
        _micButton(
          key: const Key('dictationModalStopButton'),
          icon: Icons.stop_rounded,
          label: 'Detener',
          filled: true,
          onPressed: _stopListening,
        ),
      ],
    );
  }

  // ── Estado: detenido (punto de validación 1) ───────────────────────────

  Widget _stoppedBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Revisa lo que dijiste',
          style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.onSurface),
        ),
        const SizedBox(height: 10),
        _transcriptPanel(live: false),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                key: const Key('dictationModalResumeButton'),
                onPressed: () => _startListening(resume: true),
                icon: const Icon(Icons.mic_none_rounded, size: 18),
                label: const Text('Volver a grabar'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                key: const Key('dictationModalSubmitButton'),
                onPressed: _submit,
                icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                label: const Text('Enviar'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // Destructiva y de uso raro (el campo ya es editable y "Volver a
        // grabar" anexa) — jerarquía baja a propósito para que no sea el
        // botón que se toca por reflejo.
        TextButton(
          key: const Key('dictationModalClearButton'),
          onPressed: _clearAll,
          style: TextButton.styleFrom(
            foregroundColor: AppColors.onSurfaceMuted,
            minimumSize: const Size(0, 44),
          ),
          child: const Text('Borrar todo'),
        ),
      ],
    );
  }

  /// Texto fijado (editable, del usuario) y, si [live], el segmento que el
  /// motor está oyendo ahora mismo — en un solo contenedor para que se lea
  /// como un único texto en curso. El segmento en vivo va fuera del campo:
  /// el motor lo reescribe varias veces por segundo y dentro pelearía con
  /// el cursor del usuario.
  Widget _transcriptPanel({required bool live}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const Key('dictationModalTranscriptField'),
            controller: _transcriptCtrl,
            focusNode: _transcriptFocus,
            minLines: 1,
            maxLines: 6,
            keyboardType: TextInputType.multiline,
            cursorColor: AppColors.skyBlue,
            style: const TextStyle(
                fontSize: 14, color: AppColors.onSurface, height: 1.4),
            decoration: InputDecoration.collapsed(
              hintText:
                  live ? null : 'No capté nada — escribe aquí o vuelve a grabar',
              hintStyle: const TextStyle(
                  fontSize: 14, color: AppColors.onSurfaceMuted, height: 1.4),
            ),
          ),
          if (live) ...[
            const SizedBox(height: 8),
            Semantics(
              liveRegion: true,
              child: _liveRow(),
            ),
          ],
        ],
      ),
    );
  }

  /// Segmento en curso. Tres lecturas, sin ambigüedad: gris "Un momento…"
  /// mientras el reconocedor arranca (lo dicho ahí se pierde), azul
  /// "Escuchando…" cuando el micrófono ya capta, y el parcial en azul en
  /// cuanto hay palabras.
  Widget _liveRow() {
    final hasPartial = _partialTranscript.trim().isNotEmpty;
    final color = _micLive ? AppColors.skyBlue : AppColors.onSurfaceMuted;
    return Row(
      key: const Key('dictationModalLiveRow'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(
            _micLive ? Icons.graphic_eq_rounded : Icons.more_horiz_rounded,
            size: 16,
            color: color,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            hasPartial
                ? _partialTranscript
                : _micLive
                    ? 'Escuchando…'
                    : 'Un momento…',
            style: TextStyle(fontSize: 14, color: color, height: 1.4),
          ),
        ),
      ],
    );
  }

  // ── Estado: error (nada reconocible) ────────────────────────────────────

  Widget _errorBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.error.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline_rounded,
                  size: 18, color: AppColors.error),
              SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'No reconocí ningún producto ahí',
                      style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.error),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Revisa que hayas dicho la cantidad y el precio '
                      '(ej. "a 20 pesos") — sin eso no puedo separar el '
                      'nombre.',
                      style: TextStyle(
                          fontSize: 12.5,
                          color: AppColors.onSurfaceMuted,
                          height: 1.4),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                key: const Key('dictationModalErrorRetryButton'),
                onPressed: _clearAll,
                icon: const Icon(Icons.mic_none_rounded, size: 18),
                label: const Text('Grabar de nuevo'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                key: const Key('dictationModalErrorEditButton'),
                onPressed: _editTranscriptFromError,
                icon: const Icon(Icons.edit_rounded, size: 18),
                label: const Text('Editar el texto'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ── Botón de micrófono grande — mismo criterio que el botón original: ──
  // relleno + contorno, nunca solo color, legible bajo luz de tienda.
  Widget _micButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    Key? key,
    bool filled = false,
  }) {
    return SizedBox(
      height: 56,
      child: filled
          ? ElevatedButton.icon(
              key: key,
              onPressed: onPressed,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
              ),
              icon: Icon(icon, size: 22),
              label: Text(label),
            )
          : OutlinedButton.icon(
              key: key,
              onPressed: onPressed,
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppColors.skyBlue),
                foregroundColor: AppColors.skyBlue,
              ),
              icon: Icon(icon, size: 22),
              label: Text(label),
            ),
    );
  }
}
