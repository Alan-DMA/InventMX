import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../cases/domain/desk_case.dart';
import '../../core/admin_http.dart';
import '../../core/browser/open_tab.dart';
import '../data/support_actions_repository.dart';
import '../domain/tenant_models.dart';
import 'support_action_dialog.dart' show ActionPreviewCard, SupportActionDialog;
import 'tenant_providers.dart';

/// Dirección de la pestaña de soporte (`main_support.dart`). En desarrollo:
/// `flutter run -d web-server --web-port 8090 -t lib/main_support.dart`.
const kSupportAppUrl = String.fromEnvironment('SUPPORT_APP_URL', defaultValue: 'http://localhost:8090/');

/// La URL que abre la pestaña con el código de un uso.
String supportTabUrl(String code) =>
    Uri.parse(kSupportAppUrl).replace(queryParameters: {'c': code}).toString();

/// Abre una pestaña (sustituible en tests).
final openTabProvider = Provider<void Function(String url)>((_) => openInNewTab);

/// Abre una pestaña en blanco dentro del clic para llevarla después a su
/// dirección (sustituible en tests).
final openPendingTabProvider = Provider<PendingTab Function()>((_) => openPendingTab);

String _clock(DateTime d) {
  final l = d.toLocal();
  return '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
}

/// "Ver la tienda (sólo lectura)" (etapa 4, P37–P42): motivo, caso opcional y
/// "Así lo verá la tienda"; al crearla, el diálogo pasa a "Lista" con "Abrir
/// la tienda" — un clic explícito, para que el navegador no bloquee la
/// pestaña (P42). Devuelve el enlace si se creó la sesión, se abra o no.
Future<SupportSessionLink?> showSupportSessionDialog(BuildContext context, TenantDetail detail) =>
    showDialog<SupportSessionLink>(
      context: context,
      barrierColor: Colors.black54,
      builder: (_) => SupportSessionDialog(detail: detail),
    );

class SupportSessionDialog extends ConsumerStatefulWidget {
  const SupportSessionDialog({super.key, required this.detail});
  final TenantDetail detail;

  @override
  ConsumerState<SupportSessionDialog> createState() => _SupportSessionDialogState();
}

class _SupportSessionDialogState extends ConsumerState<SupportSessionDialog> {
  final _reason = TextEditingController();
  String? _caseId;
  Timer? _debounce;
  OwnerPreview? _preview;
  bool _previewLoading = false;
  bool _previewFailed = false;
  int _previewRequest = 0;
  bool _busy = false;
  String? _error;
  SupportSessionLink? _link;

  TenantSummary get _t => widget.detail.summary;
  SupportActionsRepository get _repo => ref.read(supportActionsRepositoryProvider);
  bool get _valid => _reason.text.trim().length >= SupportActionDialog.minReason;

  @override
  void initState() {
    super.initState();
    _loadPreview();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _reason.dispose();
    super.dispose();
  }

  void _changed() {
    setState(() => _error = null);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _loadPreview);
  }

  Future<void> _loadPreview() async {
    final request = ++_previewRequest;
    setState(() => _previewLoading = true);
    try {
      final p = await _repo.preview(_t.id, PreviewAction.supportSession, reason: _reason.text);
      if (!mounted || request != _previewRequest) return;
      setState(() {
        _preview = p;
        _previewFailed = false;
        _previewLoading = false;
      });
    } catch (_) {
      if (!mounted || request != _previewRequest) return;
      setState(() {
        _previewFailed = true;
        _previewLoading = false;
      });
    }
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final link = await _repo.startSupportSession(_t.id, reason: _reason.text, caseId: _caseId);
      if (!mounted) return;
      setState(() {
        _link = link;
        _busy = false;
      });
    } on AdminApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _busy = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = toAdminError(e, 'No pudimos abrir la sesión de soporte.').message;
          _busy = false;
        });
      }
    }
  }

  void _openStore() {
    final link = _link!;
    // Dentro del clic: el navegador no la bloquea
    ref.read(openTabProvider)(supportTabUrl(link.code));
    Navigator.of(context).pop(link);
  }

  void _close() => Navigator.of(context).pop(_link);

  @override
  Widget build(BuildContext context) {
    final ready = _link != null;
    return Dialog(
      backgroundColor: AppColors.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AppColors.border),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: CallbackShortcuts(
          bindings: {const SingleActivator(LogicalKeyboardKey.escape): _close},
          child: Column(
            key: Key(ready ? 'sessionDialogReady' : 'sessionDialog'),
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 22, 24, 6),
                child: Semantics(
                  header: true,
                  child: Text(
                    ready ? 'Sesión lista' : 'Ver ${_t.name} (sólo lectura)',
                    style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: AppColors.onSurface),
                  ),
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 6, 24, 8),
                  child: ready ? _readyBody() : _formBody(),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
                child: Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 10,
                  runSpacing: 8,
                  children: ready
                      ? [
                          OutlinedButton(
                            key: const Key('sessionLater'),
                            onPressed: _close,
                            child: const Text('Más tarde'),
                          ),
                          FilledButton.icon(
                            key: const Key('sessionOpenStore'),
                            autofocus: true,
                            onPressed: _openStore,
                            icon: const Icon(Icons.open_in_new_rounded, size: 18),
                            label: const Text('Abrir la tienda'),
                          ),
                        ]
                      : [
                          OutlinedButton(
                            key: const Key('sessionCancel'),
                            onPressed: _busy ? null : () => Navigator.of(context).pop(),
                            child: const Text('Cancelar'),
                          ),
                          FilledButton(
                            key: const Key('sessionConfirm'),
                            onPressed: _busy || !_valid ? null : _submit,
                            child: Text(_busy ? 'Abriendo…' : 'Abrir sesión'),
                          ),
                        ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _formBody() {
    final cases = ref.watch(tenantCasesProvider(_t.id)).valueOrNull ?? const <DeskCase>[];
    final open = cases.where((c) => c.status != DeskCaseStatus.resolved).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Verás la tienda como la ve el dueño, en una pestaña aparte y sin poder cambiar nada. '
          'La sesión dura 30 min desde que abras la pestaña y el dueño ve quién entró, por qué y qué revisaste.',
          style: TextStyle(fontSize: 14, color: AppColors.onSurfaceMuted, height: 1.45),
        ),
        const SizedBox(height: 16),
        if (open.isNotEmpty) ...[
          DropdownButtonFormField<String?>(
            key: const Key('sessionCase'),
            initialValue: _caseId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Caso (opcional)'),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('Sin caso')),
              for (final c in open)
                DropdownMenuItem<String?>(
                  value: c.id,
                  child: Text('Caso ${c.number} · ${c.topicTitle}', overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: _busy ? null : (v) => setState(() => _caseId = v),
          ),
          const SizedBox(height: 14),
        ],
        TextField(
          key: const Key('sessionReason'),
          controller: _reason,
          enabled: !_busy,
          autofocus: true,
          minLines: 2,
          maxLines: 4,
          maxLength: 500,
          onChanged: (_) => _changed(),
          decoration: const InputDecoration(
            labelText: 'Motivo — lo leerá el dueño en su app',
            alignLabelWithHint: true,
          ),
          buildCounter: (context, {required currentLength, required isFocused, maxLength}) => Text(
            currentLength < SupportActionDialog.minReason
                ? 'Mínimo ${SupportActionDialog.minReason} caracteres ($currentLength)'
                : '$currentLength / $maxLength',
            style: const TextStyle(fontSize: 12, color: AppColors.onSurfaceMuted),
          ),
        ),
        const SizedBox(height: 16),
        ActionPreviewCard(preview: _preview, loading: _previewLoading, failed: _previewFailed),
        if (_error != null) ...[
          const SizedBox(height: 14),
          _ErrorNote(message: _error!),
        ],
      ],
    );
  }

  Widget _readyBody() {
    final link = _link!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'El enlace es de un solo uso y vale hasta las ${_clock(link.expiresAt)}. '
          'Los 30 min empiezan cuando se abra la pestaña.',
          key: const Key('sessionReadyText'),
          style: const TextStyle(fontSize: 14.5, color: AppColors.onSurface, height: 1.45),
        ),
        const SizedBox(height: 8),
        const Text(
          'Si lo dejas para más tarde, en la ficha queda «Abrir de nuevo» mientras la sesión siga vigente.',
          style: TextStyle(fontSize: 13, color: AppColors.onSurfaceMuted, height: 1.45),
        ),
      ],
    );
  }
}

class _ErrorNote extends StatelessWidget {
  const _ErrorNote({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => Semantics(
        liveRegion: true,
        child: Container(
          key: const Key('sessionError'),
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            color: AppColors.error.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.error.withValues(alpha: 0.35)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.error_outline_rounded, size: 18, color: AppColors.error),
              const SizedBox(width: 10),
              Expanded(child: Text(message, style: const TextStyle(fontSize: 13.5, color: AppColors.onSurface, height: 1.4))),
            ],
          ),
        ),
      );
}
