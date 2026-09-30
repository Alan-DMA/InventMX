import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../core/admin_colors.dart';
import '../../../core/admin_format.dart';
import '../../../core/admin_http.dart';
import '../../../session/admin_session.dart';
import '../../domain/desk_case.dart';
import '../../../tenants/presentation/tenant_providers.dart';
import '../cases_providers.dart';
import 'cases_widgets.dart';

/// Un caso abierto: quién y de qué tienda (sólo metadatos), lo que contestó en
/// el formulario, la conversación y el compositor. Lo que el operador escribe
/// lo lee el tendero tal cual.
class CaseThreadPane extends ConsumerStatefulWidget {
  const CaseThreadPane({super.key, required this.caseId, required this.composerFocus, this.onBack});

  final String caseId;
  final FocusNode composerFocus;

  /// Pantalla chica: vuelve a la cola.
  final VoidCallback? onBack;

  static const pollEvery = Duration(seconds: 60);

  @override
  ConsumerState<CaseThreadPane> createState() => _CaseThreadPaneState();
}

class _CaseThreadPaneState extends ConsumerState<CaseThreadPane> {
  Timer? _poll;
  String? _statusError;

  @override
  void initState() {
    super.initState();
    _poll = Timer.periodic(CaseThreadPane.pollEvery, (_) {
      if (mounted) ref.read(caseThreadProvider(widget.caseId).notifier).checkForNews();
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  void _afterChange() {
    ref.invalidate(waitingCountProvider);
    ref.read(caseListProvider.notifier).refreshSilently();
  }

  Future<void> _setStatus(DeskCaseStatus status) async {
    setState(() => _statusError = null);
    try {
      await ref.read(caseThreadProvider(widget.caseId).notifier).setStatus(status);
      _afterChange();
    } on AdminApiException catch (e) {
      if (mounted) setState(() => _statusError = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final thread = ref.watch(caseThreadProvider(widget.caseId));
    return thread.when(
      skipLoadingOnRefresh: true,
      loading: () => const Align(alignment: Alignment.topLeft, child: CasesSkeleton(rows: 4)),
      error: (e, _) => Align(
        alignment: Alignment.topLeft,
        child: CasesErrorBlock(
          message: e is AdminApiException && e.statusCode == 404
              ? 'Ese caso no existe o ya no está disponible.'
              : e.toString(),
          onRetry: () => ref.invalidate(caseThreadProvider(widget.caseId)),
        ),
      ),
      data: (t) {
        final d = t.detail;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(
              detail: d,
              onBack: widget.onBack,
              onStatus: _setStatus,
            ),
            if (_statusError != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                child: Text(_statusError!, style: const TextStyle(fontSize: 13, color: AppColors.error)),
              ),
            const Divider(height: 1),
            Expanded(child: _Conversation(detail: d)),
            if (t.pending != null)
              _NewMessageBar(onRefresh: () => ref.read(caseThreadProvider(widget.caseId).notifier).applyPending()),
            _Composer(
              key: ValueKey('composer_${widget.caseId}'),
              detail: d,
              focusNode: widget.composerFocus,
              onSent: _afterChange,
            ),
          ],
        );
      },
    );
  }
}

// ── Encabezado y contexto ───────────────────────────────────────────────────

class _Header extends ConsumerWidget {
  const _Header({required this.detail, required this.onStatus, this.onBack});
  final DeskCaseDetail detail;
  final ValueChanged<DeskCaseStatus> onStatus;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = detail.summary;
    final now = ref.read(adminClockProvider)();
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 18, 12, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (onBack != null) ...[
                IconButton(
                  key: const Key('caseBack'),
                  tooltip: 'Volver a la cola',
                  onPressed: onBack,
                  icon: const Icon(Icons.arrow_back_rounded),
                ),
                const SizedBox(width: 4),
              ],
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    'Caso ${c.number} · ${c.topicTitle}',
                    key: const Key('caseTitle'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.onSurface),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              PopupMenuButton<DeskCaseStatus>(
                key: const Key('caseMenu'),
                tooltip: 'Más acciones',
                icon: const Icon(Icons.more_horiz_rounded, color: AppColors.onSurfaceMuted),
                color: AppColors.surface,
                onSelected: onStatus,
                itemBuilder: (_) => [
                  if (c.status != DeskCaseStatus.resolved)
                    const PopupMenuItem(
                      key: Key('caseMarkResolved'),
                      value: DeskCaseStatus.resolved,
                      child: Text('Marcar como resuelto'),
                    ),
                  if (c.status != DeskCaseStatus.waiting)
                    const PopupMenuItem(
                      key: Key('caseMarkWaiting'),
                      value: DeskCaseStatus.waiting,
                      child: Text('Volver a "Esperando a soporte"'),
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          // El estado en su propia línea: el título largo nunca lo empuja fuera
          DeskStatusChip(c.status),
          const SizedBox(height: 10),
          _StoreLine(detail: detail),
          if (detail.store != null)
            TextButton.icon(
              key: const Key('caseOpenStore'),
              onPressed: () => openStore(context, detail.store!.tenantId),
              style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 32)),
              icon: const Icon(Icons.storefront_outlined, size: 16),
              label: Text(detail.store!.suggested ? 'Ver ficha de la tienda sugerida' : 'Ver ficha de la tienda'),
            ),
          const SizedBox(height: 4),
          Text(
            [
              if ((c.contactName ?? '').isNotEmpty) c.contactName!,
              c.contactEmail,
              c.fromApp ? 'desde la app' : 'sin sesión',
              'abierto ${adminAgo(c.createdAt, now)}',
            ].join(' · '),
            key: const Key('caseRequester'),
            style: const TextStyle(fontSize: 13, color: AppColors.onSurfaceMuted),
          ),
        ],
      ),
    );
  }
}

/// Metadatos de la tienda en una línea: nombre, estado escrito, plan y
/// vigencia. Nada de su contenido (P2).
class _StoreLine extends StatelessWidget {
  const _StoreLine({required this.detail});
  final DeskCaseDetail detail;

  @override
  Widget build(BuildContext context) {
    final c = detail.summary;
    final store = detail.store;
    const muted = TextStyle(fontSize: 13.5, color: AppColors.onSurfaceMuted);
    final parts = <InlineSpan>[];
    void sep() => parts.add(const TextSpan(text: '  ·  ', style: muted));

    if (!c.fromApp) {
      parts.add(TextSpan(
        text: 'Responde por correo a ${c.contactEmail}',
        style: const TextStyle(fontSize: 13.5, color: AppColors.skyBlue, fontWeight: FontWeight.w600),
      ));
      if (c.claimedStoreName != null) {
        sep();
        parts.add(TextSpan(text: 'dice ser de "${c.claimedStoreName}"', style: muted));
      }
    }
    if (store != null) {
      if (parts.isNotEmpty) sep();
      if (store.suggested) {
        parts.add(const TextSpan(text: 'su correo coincide con ', style: muted));
      }
      parts.add(TextSpan(
        text: store.name,
        style: const TextStyle(fontSize: 13.5, color: AppColors.onSurface, fontWeight: FontWeight.w600),
      ));
      if (store.suggested) parts.add(const TextSpan(text: ' (hay que validar)', style: muted));
      sep();
      final (String label, Color color) = store.suspendedForAbuse
          ? ('Suspendida por soporte', AppColors.error)
          : store.lockedForNonPayment
              ? ('Bloqueada por falta de pago', AdminColors.amber)
              : store.status == 'SOFT_LOCK'
                  ? ('Sólo lectura', AdminColors.amber)
                  : ('Activa', AppColors.onSurface);
      parts.add(TextSpan(text: label, style: TextStyle(fontSize: 13.5, color: color, fontWeight: FontWeight.w600)));
      sep();
      parts.add(TextSpan(text: store.planLabel, style: muted));
      if (store.paidUntil != null) {
        sep();
        parts.add(TextSpan(text: 'vigente hasta ${adminDate(store.paidUntil!)}', style: muted));
      }
    } else if (c.fromApp) {
      parts.add(TextSpan(text: c.storeLabel, style: muted));
    }
    return Text.rich(TextSpan(children: parts), key: const Key('caseStoreLine'));
  }
}

// ── Conversación ────────────────────────────────────────────────────────────

class _Conversation extends StatelessWidget {
  const _Conversation({required this.detail});
  final DeskCaseDetail detail;

  @override
  Widget build(BuildContext context) {
    // Invertida: abre en el último mensaje; el formulario queda arriba del hilo
    final children = <Widget>[
      if (detail.answers.isNotEmpty) _Answers(answers: detail.answers),
      for (final m in detail.messages) _Bubble(message: m),
    ];
    return ListView(
      key: const Key('caseConversation'),
      reverse: true,
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
      children: children.reversed.toList(),
    );
  }
}

class _Answers extends StatelessWidget {
  const _Answers({required this.answers});
  final List<DeskAnswer> answers;

  @override
  Widget build(BuildContext context) => Container(
        key: const Key('caseAnswers'),
        margin: const EdgeInsets.only(bottom: 20),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Lo que contestó en el formulario',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.onSurfaceMuted),
            ),
            for (final a in answers) ...[
              const SizedBox(height: 10),
              Text(a.label, style: const TextStyle(fontSize: 12.5, color: AppColors.onSurfaceMuted)),
              const SizedBox(height: 2),
              SelectableText(a.value, style: const TextStyle(fontSize: 14, color: AppColors.onSurface, height: 1.4)),
            ],
          ],
        ),
      );
}

/// Quien escribió a la izquierda; soporte (el operador) a la derecha, en índigo.
class _Bubble extends StatelessWidget {
  const _Bubble({required this.message});
  final DeskMessage message;

  @override
  Widget build(BuildContext context) {
    final mine = message.fromSupport;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Column(
            crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                decoration: BoxDecoration(
                  color: mine ? AdminColors.indigo.withValues(alpha: 0.12) : AppColors.surface,
                  border: Border.all(color: mine ? AdminColors.indigoLine : AppColors.border),
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(14),
                    topRight: const Radius.circular(14),
                    bottomLeft: Radius.circular(mine ? 14 : 4),
                    bottomRight: Radius.circular(mine ? 4 : 14),
                  ),
                ),
                child: SelectableText(
                  message.body,
                  style: const TextStyle(fontSize: 14.5, color: AppColors.onSurface, height: 1.45),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${message.authorName} · ${adminMoment(message.createdAt)}',
                style: TextStyle(
                  fontSize: 12,
                  color: mine ? AdminColors.indigo : AppColors.onSurfaceMuted,
                  fontWeight: mine ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NewMessageBar extends StatelessWidget {
  const _NewMessageBar({required this.onRefresh});
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) => Semantics(
        liveRegion: true,
        child: Container(
          key: const Key('caseNewMessage'),
          color: AppColors.skyBlue.withValues(alpha: 0.1),
          padding: const EdgeInsets.fromLTRB(24, 4, 12, 4),
          child: Row(
            children: [
              const Icon(Icons.mark_chat_unread_outlined, size: 18, color: AppColors.skyBlue),
              const SizedBox(width: 10),
              const Expanded(
                child: Text('Hay un mensaje nuevo en este caso.',
                    style: TextStyle(fontSize: 13.5, color: AppColors.onSurface)),
              ),
              TextButton(key: const Key('caseApplyNew'), onPressed: onRefresh, child: const Text('Actualizar')),
            ],
          ),
        ),
      );
}

// ── Compositor ──────────────────────────────────────────────────────────────

class _Composer extends ConsumerStatefulWidget {
  const _Composer({super.key, required this.detail, required this.focusNode, required this.onSent});
  final DeskCaseDetail detail;
  final FocusNode focusNode;
  final VoidCallback onSent;

  @override
  ConsumerState<_Composer> createState() => _ComposerState();
}

class _ComposerState extends ConsumerState<_Composer> {
  late final TextEditingController _text;
  bool _sending = false;
  String? _error;

  String get _caseId => widget.detail.summary.id;

  @override
  void initState() {
    super.initState();
    // El borrador de la pestaña: sobrevive a F5 y al vencimiento de la sesión
    _text = TextEditingController(text: ref.read(caseDraftsProvider).read(_caseId));
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _send({required bool resolve}) async {
    final body = _text.text.trim();
    if (_sending) return;
    if (body.isEmpty) {
      setState(() => _error = 'Escribe la respuesta antes de enviar.');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await ref.read(caseThreadProvider(_caseId).notifier).reply(body, resolve: resolve);
      ref.read(caseDraftsProvider).clear(_caseId);
      if (!mounted) return;
      _text.clear();
      setState(() => _sending = false);
      widget.onSent();
    } on AdminApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = 'No se envió: ${e.message} Tu respuesta sigue aquí.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.detail.summary;
    final requester = (c.contactName ?? '').isNotEmpty ? c.contactName! : 'el tendero';

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.border))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.enter, control: true): () => _send(resolve: false),
              const SingleActivator(LogicalKeyboardKey.escape): () => widget.focusNode.unfocus(),
            },
            child: TextField(
              key: const Key('caseReplyField'),
              controller: _text,
              focusNode: widget.focusNode,
              enabled: !_sending,
              minLines: 3,
              maxLines: 8,
              maxLength: 2000,
              maxLengthEnforcement: MaxLengthEnforcement.enforced,
              buildCounter: (context, {required currentLength, required isFocused, maxLength}) =>
                  currentLength > 1800 ? Text('$currentLength / $maxLength') : null,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (value) {
                ref.read(caseDraftsProvider).write(_caseId, value);
                setState(() {});
              },
              style: const TextStyle(fontSize: 14.5, height: 1.45),
              decoration: InputDecoration(
                hintText:
                    c.fromApp ? 'Escribe tu respuesta a $requester' : 'Escribe la respuesta (le llegará por correo)',
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Semantics(
              liveRegion: true,
              child: Text(_error!,
                  key: const Key('caseSendError'), style: const TextStyle(fontSize: 13, color: AppColors.error)),
            ),
          ],
          const SizedBox(height: 12),
          LayoutBuilder(builder: (context, box) {
            final buttons = [
              OutlinedButton(
                key: const Key('caseSendResolve'),
                onPressed: _sending ? null : () => _send(resolve: true),
                child: const Text('Enviar y resolver'),
              ),
              FilledButton(
                key: const Key('caseSend'),
                onPressed: _sending ? null : () => _send(resolve: false),
                child: Text(_sending ? 'Enviando…' : 'Enviar'),
              ),
            ];
            // En angosto la pista sobra y los botones pueden bajar de línea
            if (box.maxWidth < 520) {
              return Wrap(alignment: WrapAlignment.end, spacing: 10, runSpacing: 8, children: buttons);
            }
            return Row(
              children: [
                const Expanded(
                  child: Text('Ctrl + Enter envía', style: TextStyle(fontSize: 12.5, color: AppColors.onSurfaceMuted)),
                ),
                buttons[0],
                const SizedBox(width: 10),
                buttons[1],
              ],
            );
          }),
        ],
      ),
    );
  }
}
