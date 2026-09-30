import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../data/support_repository.dart';
import '../domain/support_models.dart';
import 'support_provider.dart';
import 'widgets/support_widgets.dart';

/// Un caso como conversación (P23): número y estado arriba, lo que respondió
/// en el formulario, y el hilo — soporte a la izquierda con su nombre, lo
/// propio a la derecha. Responder reabre un caso resuelto.
class CaseDetailScreen extends ConsumerStatefulWidget {
  const CaseDetailScreen({super.key, required this.caseId});
  final String caseId;

  @override
  ConsumerState<CaseDetailScreen> createState() => _CaseDetailScreenState();
}

class _CaseDetailScreenState extends ConsumerState<CaseDetailScreen> {
  final _reply = TextEditingController();
  final _scroll = ScrollController();
  bool _scrolledToLatest = false;
  bool _sending = false;
  bool _resolving = false;
  String? _error;

  /// Lo que devuelve el servidor tras responder/resolver: se muestra sin
  /// volver a pedir el caso.
  SupportCase? _latest;

  @override
  void initState() {
    super.initState();
    _reply.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _reply.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// Se abre en el último mensaje: casi siempre es la respuesta que vino a leer.
  void _toLatest({bool animate = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final end = _scroll.position.maxScrollExtent;
      animate
          ? _scroll.animateTo(end, duration: const Duration(milliseconds: 250), curve: Curves.easeOutCubic)
          : _scroll.jumpTo(end);
    });
  }

  Future<void> _send(SupportCase current) async {
    final body = _reply.text.trim();
    if (body.isEmpty) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final updated = await ref.read(supportRepositoryProvider).reply(current.id, body);
      _reply.clear();
      ref.invalidate(supportCasesProvider);
      if (mounted) setState(() => _latest = updated);
      _toLatest(animate: true);
    } on SupportException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _resolve(SupportCase current) async {
    setState(() => _resolving = true);
    try {
      final updated = await ref.read(supportRepositoryProvider).resolve(current.id);
      ref.invalidate(supportCasesProvider);
      if (mounted) setState(() => _latest = updated);
    } on SupportException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _resolving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(supportCaseProvider(widget.caseId));
    final current = _latest ?? async.valueOrNull;
    if (current != null && !_scrolledToLatest) {
      _scrolledToLatest = true;
      _toLatest();
    }

    return Scaffold(
      backgroundColor: AppColors.darkSlate,
      appBar: AppBar(
        backgroundColor: AppColors.darkSlate,
        elevation: 0,
        title: Text(current == null ? 'Caso' : 'Caso ${current.number}'),
      ),
      body: current == null
          ? async.hasError
              ? SupportErrorState(
                  message: errorText(async.error!, 'No pudimos abrir el caso.'),
                  onRetry: () => ref.invalidate(supportCaseProvider(widget.caseId)),
                )
              : const SupportSkeleton(rows: 3)
          : Column(
              children: [
                Expanded(
                  child: _Thread(
                    supportCase: current,
                    controller: _scroll,
                    resolving: _resolving,
                    onResolve: () => _resolve(current),
                  ),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                    child: Text(_error!, style: const TextStyle(color: AppColors.error, fontSize: 13)),
                  ),
                _Composer(
                  controller: _reply,
                  sending: _sending,
                  resolved: current.status == CaseStatus.resolved,
                  onSend: () => _send(current),
                ),
              ],
            ),
    );
  }
}

class _Thread extends StatelessWidget {
  const _Thread({
    required this.supportCase,
    required this.controller,
    required this.resolving,
    required this.onResolve,
  });
  final SupportCase supportCase;
  final ScrollController controller;
  final bool resolving;
  final VoidCallback onResolve;

  @override
  Widget build(BuildContext context) {
    final c = supportCase;
    return ListView(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      children: [
        Text(
          c.topicTitle,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.onSurface, height: 1.2),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            CaseStatusChip(c.status, key: const Key('caseStatusChip')),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Abierto el ${caseMoment(c.createdAt)}${!c.isMine && c.authorName != null ? ' · ${c.authorName}' : ''}',
                style: const TextStyle(fontSize: 12.5, color: AppColors.onSurfaceMuted),
              ),
            ),
          ],
        ),
        if (c.answers.isNotEmpty) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final a in c.answers)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text.rich(TextSpan(children: [
                      TextSpan(text: '${a.label}  ', style: const TextStyle(color: AppColors.onSurfaceMuted)),
                      TextSpan(text: a.value, style: const TextStyle(color: AppColors.onSurface, fontWeight: FontWeight.w600)),
                    ]), style: const TextStyle(fontSize: 13.5, height: 1.35)),
                  ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 18),
        for (final m in c.messages) _Bubble(message: m),
        const SizedBox(height: 6),
        Text(
          switch (c.status) {
            CaseStatus.waitingSupport =>
              'Soporte te responde aquí. Cuando lo haga, verás un punto en ☰ · Soporte y te llegará un correo.',
            CaseStatus.answered => 'Si con esto se resolvió, márcalo como resuelto. Si no, respóndenos aquí abajo.',
            CaseStatus.resolved => 'Caso resuelto. Si vuelve a pasar, escríbenos aquí y lo reabrimos.',
          },
          key: const Key('caseNextStep'),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 12.5, color: AppColors.onSurfaceMuted, height: 1.4),
        ),
        if (c.status != CaseStatus.resolved)
          Center(
            child: TextButton(
              key: const Key('caseResolveButton'),
              style: TextButton.styleFrom(minimumSize: const Size(0, 48)),
              onPressed: resolving ? null : onResolve,
              child: const Text('Marcar como resuelto'),
            ),
          ),
      ],
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message});
  final CaseMessage message;

  @override
  Widget build(BuildContext context) {
    final fromSupport = message.fromSupport;
    return Align(
      alignment: fromSupport ? Alignment.centerLeft : Alignment.centerRight,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.82),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            crossAxisAlignment: fromSupport ? CrossAxisAlignment.start : CrossAxisAlignment.end,
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                decoration: BoxDecoration(
                  color: fromSupport ? AppColors.surface : AppColors.surfaceVariant,
                  border: fromSupport ? Border.all(color: AppColors.skyBlue.withValues(alpha: 0.35)) : null,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(14),
                    topRight: const Radius.circular(14),
                    bottomLeft: Radius.circular(fromSupport ? 4 : 14),
                    bottomRight: Radius.circular(fromSupport ? 14 : 4),
                  ),
                ),
                child: SelectableText(
                  message.body,
                  style: const TextStyle(fontSize: 14.5, color: AppColors.onSurface, height: 1.45),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${message.authorName} · ${caseMoment(message.createdAt)}',
                style: TextStyle(
                  fontSize: 11.5,
                  color: fromSupport ? AppColors.skyBlue : AppColors.onSurfaceMuted,
                  fontWeight: fromSupport ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({required this.controller, required this.sending, required this.resolved, required this.onSend});
  final TextEditingController controller;
  final bool sending;
  final bool resolved;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) => SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
          decoration: const BoxDecoration(
            color: AppColors.darkSlate,
            border: Border(top: BorderSide(color: AppColors.border)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  key: const Key('caseReplyField'),
                  controller: controller,
                  minLines: 1,
                  maxLines: 5,
                  maxLength: 2000,
                  enabled: !sending,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    hintText: resolved ? 'Escribe para reabrir el caso' : 'Escribe tu respuesta',
                    counterText: '',
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              IconButton.filled(
                key: const Key('caseSendReply'),
                tooltip: 'Enviar',
                style: IconButton.styleFrom(
                  backgroundColor: AppColors.emerald,
                  foregroundColor: AppColors.darkSlate,
                  minimumSize: const Size(48, 48),
                ),
                onPressed: sending || controller.text.trim().isEmpty ? null : onSend,
                icon: sending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.darkSlate),
                      )
                    : const Icon(Icons.send_rounded),
              ),
            ],
          ),
        ),
      );
}
