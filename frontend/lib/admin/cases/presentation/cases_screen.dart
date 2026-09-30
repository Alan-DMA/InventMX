import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../core/admin_format.dart';
import '../../router/admin_routes.dart';
import '../../session/admin_session.dart';
import '../domain/desk_case.dart';
import 'cases_providers.dart';
import 'widgets/case_queue.dart';
import 'widgets/case_thread.dart';

/// Casos (etapa 3b, P28): la cola a la izquierda y el hilo al lado; en
/// pantalla chica, una cosa a la vez. Teclado primero: J/K entre casos, R para
/// responder, Ctrl+Enter envía, Esc sale del campo.
class CasesScreen extends ConsumerStatefulWidget {
  const CasesScreen({super.key, this.selectedId});

  final String? selectedId;

  static const twoPaneFrom = 820.0;

  @override
  ConsumerState<CasesScreen> createState() => _CasesScreenState();
}

class _CasesScreenState extends ConsumerState<CasesScreen> {
  final _composerFocus = FocusNode(debugLabel: 'caseComposer');
  final _screenFocus = FocusNode(debugLabel: 'casesScreen');

  @override
  void dispose() {
    _composerFocus.dispose();
    _screenFocus.dispose();
    super.dispose();
  }

  void _open(DeskCase c) => context.go(AdminRoutes.casePath(c.id));

  bool get _typing =>
      FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<EditableText>() != null;

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent || _typing) return KeyEventResult.ignored;
    final items = ref.read(caseListProvider).valueOrNull?.items ?? const <DeskCase>[];
    final key = event.logicalKey;
    if ((key == LogicalKeyboardKey.keyJ || key == LogicalKeyboardKey.keyK) && items.isNotEmpty) {
      final index = items.indexWhere((c) => c.id == widget.selectedId);
      final next = key == LogicalKeyboardKey.keyJ
          ? (index < 0 ? 0 : (index + 1).clamp(0, items.length - 1))
          : (index < 0 ? 0 : (index - 1).clamp(0, items.length - 1));
      _open(items[next]);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyR && widget.selectedId != null) {
      _composerFocus.requestFocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final selected = widget.selectedId;
    return Focus(
      focusNode: _screenFocus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final thread = selected == null
              ? null
              : CaseThreadPane(
                  key: ValueKey('thread_$selected'),
                  caseId: selected,
                  composerFocus: _composerFocus,
                  onBack: constraints.maxWidth < CasesScreen.twoPaneFrom ? () => context.go(AdminRoutes.cases) : null,
                );
          if (constraints.maxWidth < CasesScreen.twoPaneFrom) {
            return thread ?? CaseQueue(selectedId: null, onOpen: _open);
          }
          final queueWidth = constraints.maxWidth >= 1100 ? 380.0 : 330.0;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(width: queueWidth, child: CaseQueue(selectedId: selected, onOpen: _open)),
              const VerticalDivider(width: 1, color: AppColors.border),
              Expanded(child: thread ?? _NoSelection(onOpen: _open)),
            ],
          );
        },
      ),
    );
  }
}

/// Sin caso abierto: cuántos esperan y cuál lleva más tiempo.
class _NoSelection extends ConsumerWidget {
  const _NoSelection({required this.onOpen});
  final ValueChanged<DeskCase> onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(waitingCountProvider).valueOrNull;
    final oldest = ref.watch(oldestWaitingProvider).valueOrNull;
    final now = ref.read(adminClockProvider)();

    final title = switch (count) {
      null => 'Casos',
      0 => 'Sin casos esperando',
      1 => '1 caso espera respuesta',
      _ => '$count casos esperan respuesta',
    };
    return Align(
      alignment: Alignment.topLeft,
      child: Padding(
        key: const Key('casesNoSelection'),
        padding: const EdgeInsets.fromLTRB(40, 48, 40, 40),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.onSurface)),
              const SizedBox(height: 10),
              if (count == 0)
                const Text('Todo en orden: nadie espera respuesta de soporte.',
                    style: TextStyle(fontSize: 14.5, color: AppColors.onSurfaceMuted, height: 1.5))
              else if (oldest != null) ...[
                Text(
                  'El que más lleva esperando: Caso ${oldest.number} · ${oldest.storeLabel} · '
                  'espera ${adminSpan(now.difference(oldest.lastMessageAt))}.',
                  style: const TextStyle(fontSize: 14.5, color: AppColors.onSurfaceMuted, height: 1.5),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  key: const Key('casesOpenOldest'),
                  onPressed: () => onOpen(oldest),
                  child: const Text('Abrir el más antiguo'),
                ),
              ],
              const SizedBox(height: 32),
              const Text(
                'Atajos: J y K para moverte entre casos, R para responder, Ctrl + Enter para enviar, Esc para salir del campo.',
                style: TextStyle(fontSize: 12.5, color: AppColors.onSurfaceMuted, height: 1.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
