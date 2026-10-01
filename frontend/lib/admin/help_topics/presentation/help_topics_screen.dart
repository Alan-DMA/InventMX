import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../features/support/domain/support_models.dart' as tendero show HelpTopic;
import '../../cases/presentation/widgets/cases_widgets.dart';
import '../../core/admin_colors.dart';
import '../../core/admin_format.dart';
import '../../core/admin_http.dart';
import '../../router/admin_routes.dart';
import '../data/help_topics_repository.dart';
import '../domain/admin_help_topic.dart';

class HelpTopicsNotifier extends AsyncNotifier<List<AdminHelpTopic>> {
  @override
  Future<List<AdminHelpTopic>> build() => ref.watch(helpTopicsRepositoryProvider).list();

  void replace(AdminHelpTopic updated) {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncData([
      for (final t in current)
        if (t.key == updated.key) updated else t,
    ]..sort((a, b) => a.sortOrder != b.sortOrder ? a.sortOrder.compareTo(b.sortOrder) : a.title.compareTo(b.title)));
  }
}

final helpTopicsProvider = AsyncNotifierProvider<HelpTopicsNotifier, List<AdminHelpTopic>>(HelpTopicsNotifier.new);

/// El editor abierto tiene cambios sin guardar: cambiar de tema lo pregunta.
/// Se limpia sola al salir de la sección (autoDispose).
final helpTopicDirtyProvider = StateProvider.autoDispose<bool>((_) => false);

/// Temas de ayuda (etapa 3e, P29): el texto de la ayuda que ven los tenderos
/// en Soporte, editable sin publicar la app (P27). Lista a la izquierda y
/// editor con "Así lo verá el tendero" al lado.
class HelpTopicsScreen extends ConsumerWidget {
  const HelpTopicsScreen({super.key, this.selectedKey});

  final String? selectedKey;

  static const twoPaneFrom = 820.0;

  Future<void> _open(BuildContext context, WidgetRef ref, AdminHelpTopic topic) async {
    if (topic.key == selectedKey) return;
    if (ref.read(helpTopicDirtyProvider)) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: const Text('Tienes cambios sin guardar'),
          content: const Text('Si cambias de tema, se pierden los cambios del tema abierto.'),
          actions: [
            TextButton(
              key: const Key('topicsKeepEditing'),
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Seguir editando'),
            ),
            TextButton(
              key: const Key('topicsDiscard'),
              onPressed: () => Navigator.of(context).pop(true),
              style: TextButton.styleFrom(foregroundColor: AppColors.error),
              child: const Text('Descartar cambios'),
            ),
          ],
        ),
      );
      if (discard != true) return;
      ref.read(helpTopicDirtyProvider.notifier).state = false;
    }
    if (context.mounted) context.go('${AdminRoutes.helpTopics}/${topic.key}');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final topics = ref.watch(helpTopicsProvider);
    ref.watch(helpTopicDirtyProvider); // la mantiene viva mientras la sección está abierta
    return topics.when(
      skipLoadingOnRefresh: true,
      loading: () => const Align(alignment: Alignment.topLeft, child: CasesSkeleton()),
      error: (e, _) => Align(
        alignment: Alignment.topLeft,
        child: CasesErrorBlock(message: e.toString(), onRetry: () => ref.invalidate(helpTopicsProvider)),
      ),
      data: (items) => LayoutBuilder(builder: (context, box) {
        final selected = items.where((t) => t.key == selectedKey).firstOrNull;
        final list = _TopicList(topics: items, selectedKey: selectedKey, onOpen: (t) => _open(context, ref, t));
        final editor = selected == null
            ? const _NoSelection()
            : _TopicEditor(
                key: ValueKey('editor_${selected.key}'),
                topic: selected,
                onBack: box.maxWidth < twoPaneFrom ? () => context.go(AdminRoutes.helpTopics) : null,
              );
        if (box.maxWidth < twoPaneFrom) return selected == null ? list : editor;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(width: 320, child: list),
            const VerticalDivider(width: 1, color: AppColors.border),
            Expanded(child: editor),
          ],
        );
      }),
    );
  }
}

class _TopicList extends StatelessWidget {
  const _TopicList({required this.topics, required this.selectedKey, required this.onOpen});
  final List<AdminHelpTopic> topics;
  final String? selectedKey;
  final ValueChanged<AdminHelpTopic> onOpen;

  @override
  Widget build(BuildContext context) => ListView(
        key: const Key('topicsList'),
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
            child: Semantics(
              header: true,
              child: const Text('Temas de ayuda',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.onSurface)),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text('En el orden en que los ven los tenderos en Soporte.',
                style: TextStyle(fontSize: 13, color: AppColors.onSurfaceMuted, height: 1.4)),
          ),
          const Divider(height: 1),
          for (final t in topics) ...[
            Material(
              color: t.key == selectedKey ? AdminColors.indigoSoft : Colors.transparent,
              child: InkWell(
                key: Key('topicRow_${t.key}'),
                onTap: () => onOpen(t),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t.title,
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                          color: t.isActive ? AppColors.onSurface : AppColors.onSurfaceMuted,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        [t.audienceLabel, if (!t.isActive) 'Inactivo'].join(' · '),
                        style: TextStyle(
                          fontSize: 12.5,
                          color: AppColors.onSurfaceMuted,
                          fontWeight: t.isActive ? FontWeight.w400 : FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const Divider(height: 1, indent: 16, endIndent: 16),
          ],
        ],
      );
}

class _NoSelection extends StatelessWidget {
  const _NoSelection();

  @override
  Widget build(BuildContext context) => const Align(
        alignment: Alignment.topLeft,
        child: Padding(
          padding: EdgeInsets.fromLTRB(40, 48, 40, 40),
          child: Text(
            'Elige un tema para editar su texto. Los tenderos ven los cambios al abrir Soporte, sin publicar la app.',
            style: TextStyle(fontSize: 14.5, color: AppColors.onSurfaceMuted, height: 1.5),
          ),
        ),
      );
}

class _TopicEditor extends ConsumerStatefulWidget {
  const _TopicEditor({super.key, required this.topic, this.onBack});
  final AdminHelpTopic topic;
  final VoidCallback? onBack;

  @override
  ConsumerState<_TopicEditor> createState() => _TopicEditorState();
}

class _TopicEditorState extends ConsumerState<_TopicEditor> {
  late final _title = TextEditingController(text: widget.topic.title);
  late final _summary = TextEditingController(text: widget.topic.summary);
  late final _body = TextEditingController(text: widget.topic.body);
  late final _order = TextEditingController(text: '${widget.topic.sortOrder}');
  final _reason = TextEditingController();
  late String _audience = widget.topic.audience;
  late bool _active = widget.topic.isActive;
  bool _saving = false;
  String? _error;
  String? _notice;

  HelpTopicDraft get _draft => HelpTopicDraft(
        title: _title.text,
        summary: _summary.text,
        body: _body.text,
        audience: _audience,
        sortOrder: int.tryParse(_order.text.trim()) ?? widget.topic.sortOrder,
        isActive: _active,
      );

  bool get _dirty => !_draft.sameAs(widget.topic);

  bool get _valid {
    final order = int.tryParse(_order.text.trim());
    return _title.text.trim().length >= 2 &&
        order != null &&
        order >= 0 &&
        order <= 1000 &&
        _reason.text.trim().length >= 10;
  }

  void _changed() {
    setState(() {
      _error = null;
      _notice = null;
    });
    ref.read(helpTopicDirtyProvider.notifier).state = _dirty;
  }

  @override
  void dispose() {
    for (final c in [_title, _summary, _body, _order, _reason]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_dirty || !_valid) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final saved = await ref.read(helpTopicsRepositoryProvider).save(widget.topic, _draft, reason: _reason.text);
      if (!mounted) return;
      ref.read(helpTopicDirtyProvider.notifier).state = false;
      // El editor compara contra lo guardado: deja de verse con cambios
      ref.read(helpTopicsProvider.notifier).replace(saved);
      _reason.clear();
      setState(() {
        _saving = false;
        _notice = 'Guardado. Los tenderos lo ven al abrir Soporte.';
      });
    } on AdminApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.topic;
    final fields = _fields(t);
    final preview = _ArticlePreview(title: _title.text, body: _body.text);
    return LayoutBuilder(builder: (context, box) {
      // Lado a lado desde ~820 px: a 1440 la vista previa se ve mientras se escribe
      final side = box.maxWidth >= 820;
      return ListView(
        key: const Key('topicEditor'),
        padding: const EdgeInsets.fromLTRB(28, 20, 28, 40),
        children: [
          Row(
            children: [
              if (widget.onBack != null)
                IconButton(
                  tooltip: 'Volver a los temas',
                  onPressed: widget.onBack,
                  icon: const Icon(Icons.arrow_back_rounded),
                ),
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(t.title,
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.onSurface)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            t.updatedByName == null
                ? 'Texto original (sin cambios desde que se sembró).'
                : 'Editado por ${t.updatedByName} el ${adminMoment(t.updatedAt)}.',
            key: const Key('topicLastEdit'),
            style: const TextStyle(fontSize: 13, color: AppColors.onSurfaceMuted),
          ),
          const SizedBox(height: 20),
          if (side)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: fields),
                const SizedBox(width: 24),
                SizedBox(width: 340, child: preview),
              ],
            )
          else ...[
            fields,
            const SizedBox(height: 24),
            preview,
          ],
        ],
      );
    });
  }

  Widget _fields(AdminHelpTopic t) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const Key('topicTitle'),
            controller: _title,
            enabled: !_saving,
            maxLength: 120,
            onChanged: (_) => _changed(),
            decoration: const InputDecoration(labelText: 'Título (con las palabras del tendero)'),
          ),
          const SizedBox(height: 8),
          TextField(
            key: const Key('topicSummary'),
            controller: _summary,
            enabled: !_saving,
            maxLength: 200,
            onChanged: (_) => _changed(),
            decoration: const InputDecoration(labelText: 'Resumen de una línea (se ve en la lista de temas)'),
          ),
          const SizedBox(height: 8),
          TextField(
            key: const Key('topicBody'),
            controller: _body,
            enabled: !_saving,
            minLines: 8,
            maxLines: 18,
            maxLength: 5000,
            onChanged: (_) => _changed(),
            decoration: const InputDecoration(
              labelText: 'Artículo',
              alignLabelWithHint: true,
              helperText: 'Párrafos separados por una línea en blanco. Empieza una línea con "• " para una viñeta.',
              helperMaxLines: 3,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 16,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 300,
                child: DropdownButtonFormField<String>(
                  key: const Key('topicAudience'),
                  initialValue: _audience,
                  isExpanded: true, // la opción larga se recorta en vez de desbordar
                  dropdownColor: AppColors.surface,
                  decoration: const InputDecoration(labelText: 'Lo ven'),
                  items: [
                    for (final e in AdminHelpTopic.audienceLabels.entries)
                      DropdownMenuItem(value: e.key, child: Text(e.value, overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: _saving
                      ? null
                      : (v) {
                          _audience = v ?? _audience;
                          _changed();
                        },
                ),
              ),
              SizedBox(
                width: 120,
                child: TextField(
                  key: const Key('topicOrder'),
                  controller: _order,
                  enabled: !_saving,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)],
                  onChanged: (_) => _changed(),
                  decoration: const InputDecoration(labelText: 'Orden'),
                ),
              ),
            ],
          ),
          if (_audience == 'ANONYMOUS')
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('Es el formulario de "No puedo entrar": lo ve quien no tiene sesión.',
                  style: TextStyle(fontSize: 12.5, color: AppColors.onSurfaceMuted)),
            ),
          const SizedBox(height: 8),
          SwitchListTile(
            key: const Key('topicActive'),
            value: _active,
            onChanged: _saving
                ? null
                : (v) {
                    _active = v;
                    _changed();
                  },
            contentPadding: EdgeInsets.zero,
            title: const Text('Activo', style: TextStyle(fontSize: 14.5, color: AppColors.onSurface)),
            subtitle: Text(
              _active ? 'Los tenderos lo ven en Soporte.' : 'Los tenderos dejarán de verlo en Soporte.',
              key: const Key('topicActiveNote'),
              style: TextStyle(fontSize: 12.5, color: _active ? AppColors.onSurfaceMuted : AdminColors.amber),
            ),
          ),
          _ReadOnlyParts(topic: t),
          const SizedBox(height: 16),
          TextField(
            key: const Key('topicReason'),
            controller: _reason,
            enabled: !_saving,
            minLines: 1,
            maxLines: 3,
            maxLength: 500,
            onChanged: (_) => _changed(),
            decoration: const InputDecoration(labelText: 'Motivo del cambio (queda en la bitácora)'),
            buildCounter: (context, {required currentLength, required isFocused, maxLength}) => Text(
              currentLength < 10 ? 'Mínimo 10 caracteres ($currentLength)' : '$currentLength / $maxLength',
              style: const TextStyle(fontSize: 12, color: AppColors.onSurfaceMuted),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(_error!,
                  key: const Key('topicError'), style: const TextStyle(fontSize: 13.5, color: AppColors.error)),
            ),
          if (_notice != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(_notice!,
                  key: const Key('topicSaved'), style: const TextStyle(fontSize: 13.5, color: AppColors.skyBlue)),
            ),
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              key: const Key('topicSave'),
              onPressed: _saving || !_dirty || !_valid ? null : _save,
              child: Text(_saving ? 'Guardando…' : 'Guardar cambios'),
            ),
          ),
        ],
      );
}

/// Acciones y campos del formulario: se ven, no se editan aquí (PD-07).
class _ReadOnlyParts extends StatelessWidget {
  const _ReadOnlyParts({required this.topic});
  final AdminHelpTopic topic;

  @override
  Widget build(BuildContext context) {
    const muted = TextStyle(fontSize: 13, color: AppColors.onSurfaceMuted, height: 1.4);
    return Container(
      key: const Key('topicReadOnly'),
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Botones y formulario del tema',
              style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: AppColors.onSurface)),
          const SizedBox(height: 2),
          const Text('Se ven aquí, pero se editan en una etapa posterior.', style: muted),
          const SizedBox(height: 8),
          Text(
            topic.rawActions.isEmpty
                ? 'Sin botones.'
                : 'Botones: ${topic.rawActions.map((a) => a['label']).join(', ')}.',
            style: muted,
          ),
          Text(
            topic.rawFormFields.isEmpty
                ? 'Formulario: sólo "Cuéntanos qué pasó".'
                : 'Formulario: ${topic.rawFormFields.map((f) => '${f['label']}${f['required'] == true ? ' (obligatorio)' : ''}').join(' · ')}'
                    ' + "Cuéntanos qué pasó".',
            style: muted,
          ),
        ],
      ),
    );
  }
}

/// "Así lo verá el tendero": el mismo intérprete de párrafos y viñetas que
/// la app del tendero (`HelpTopic.blocks`), con su tipografía.
class _ArticlePreview extends StatelessWidget {
  const _ArticlePreview({required this.title, required this.body});
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final blocks = tendero.HelpTopic(key: 'vista', title: title, body: body).blocks;
    const bodyStyle = TextStyle(fontSize: 15, color: AppColors.onSurface, height: 1.55);
    return Column(
      key: const Key('topicPreview'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Así lo verá el tendero',
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.onSurfaceMuted)),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          constraints: const BoxConstraints(maxHeight: 560),
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
          decoration: BoxDecoration(
            color: AppColors.darkSlate,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title.trim().isEmpty ? 'Sin título' : title.trim(),
                    style: const TextStyle(
                        fontSize: 21, fontWeight: FontWeight.w800, color: AppColors.onSurface, height: 1.2)),
                const SizedBox(height: 14),
                if (blocks.isEmpty)
                  const Text('Sin artículo.', style: TextStyle(fontSize: 14, color: AppColors.onSurfaceMuted)),
                for (final block in blocks) ...[
                  if (block.isList)
                    for (final bullet in block.bullets)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8, left: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Padding(
                              padding: EdgeInsets.only(top: 9, right: 12),
                              child: SizedBox(
                                width: 6,
                                height: 6,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(color: AppColors.onSurfaceMuted, shape: BoxShape.circle),
                                ),
                              ),
                            ),
                            Expanded(child: Text(bullet, style: bodyStyle)),
                          ],
                        ),
                      )
                  else
                    Text(block.text, style: bodyStyle),
                  const SizedBox(height: 12),
                ],
                const SizedBox(height: 4),
                const Text('Aún necesito ayuda',
                    style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: AppColors.emerald)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
