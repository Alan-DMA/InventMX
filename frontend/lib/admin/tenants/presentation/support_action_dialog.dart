import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../core/admin_colors.dart';
import '../../core/admin_format.dart';
import '../../core/admin_http.dart';
import '../../core/admin_theme.dart';
import '../../session/admin_session.dart';
import '../data/support_actions_repository.dart';
import '../domain/tenant_models.dart';
import 'tenant_providers.dart';

/// Las acciones de soporte de la ficha (P16–P18, etapa 3d).
enum SupportActionKind {
  recovery,
  giftDays,
  suspend,
  lift,
  export,
  requestDeletion,
  approveDeletion,
  cancelDeletion;

  bool get destructive => this == suspend || this == requestDeletion || this == approveDeletion;

  /// Eliminar (pedir o aprobar) se confirma escribiendo el slug (P35).
  bool get needsSlug => this == requestDeletion || this == approveDeletion;

  PreviewAction? get preview => switch (this) {
        recovery => PreviewAction.assistedRecovery,
        giftDays => PreviewAction.giftDays,
        suspend => PreviewAction.suspend,
        lift => PreviewAction.lift,
        export => PreviewAction.export,
        requestDeletion => PreviewAction.deletion,
        approveDeletion || cancelDeletion => null,
      };

  /// El dueño lee el motivo en su app (P8); aprobar y cancelar quedan en la
  /// bitácora de la plataforma.
  bool get ownerReadsReason => this != approveDeletion && this != cancelDeletion;
}

/// Lo que pasó, en palabras, para mostrarlo en la ficha.
class ActionOutcome {
  const ActionOutcome(this.message, {this.storeDeleted = false});
  final String message;
  final bool storeDeleted;
}

Future<ActionOutcome?> showSupportAction(BuildContext context, SupportActionKind kind, TenantDetail detail) =>
    showDialog<ActionOutcome>(
      context: context,
      barrierDismissible: false, // un clic fuera no borra lo escrito
      builder: (_) => SupportActionDialog(kind: kind, detail: detail),
    );

/// Un diálogo para todas las acciones: lo que hace, sus campos, el motivo y
/// **"Así lo verá la tienda"** en vivo (el texto exacto del servidor). Los
/// rechazos del servidor se dicen aquí, sin cerrar ni perder lo escrito.
class SupportActionDialog extends ConsumerStatefulWidget {
  const SupportActionDialog({super.key, required this.kind, required this.detail});

  final SupportActionKind kind;
  final TenantDetail detail;

  static const minReason = 10;

  @override
  ConsumerState<SupportActionDialog> createState() => _SupportActionDialogState();
}

class _SupportActionDialogState extends ConsumerState<SupportActionDialog> {
  final _reason = TextEditingController();
  final _days = TextEditingController();
  final _slug = TextEditingController();
  final _order = TextEditingController();
  final _checks = <String, bool>{'store_name': false, 'owner_email': false, 'signup_date': false, 'employees': false};

  Timer? _debounce;
  OwnerPreview? _preview;
  bool _previewFailed = false;
  bool _previewLoading = false;
  int _previewRequest = 0;
  bool _busy = false;
  String? _error;

  SupportActionKind get _kind => widget.kind;
  TenantSummary get _t => widget.detail.summary;
  SupportActionsRepository get _repo => ref.read(supportActionsRepositoryProvider);
  bool get _payingWithPlay => _t.subscriptionSource == 'GOOGLE_PLAY';

  @override
  void initState() {
    super.initState();
    if (_kind.preview != null && _kind != SupportActionKind.giftDays) _loadPreview();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _reason.dispose();
    _days.dispose();
    _slug.dispose();
    _order.dispose();
    super.dispose();
  }

  int? get _dayCount {
    final n = int.tryParse(_days.text.trim());
    return n != null && n >= 1 && n <= 90 ? n : null;
  }

  void _changed() {
    setState(() => _error = null);
    if (_kind.preview == null) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _loadPreview);
  }

  Future<void> _loadPreview() async {
    final action = _kind.preview;
    if (action == null) return;
    if (_kind == SupportActionKind.giftDays && _dayCount == null) {
      setState(() => _preview = null);
      return;
    }
    final request = ++_previewRequest;
    setState(() => _previewLoading = true);
    try {
      final p = await _repo.preview(_t.id, action, reason: _reason.text, days: _dayCount);
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

  bool get _valid {
    if (_reason.text.trim().length < SupportActionDialog.minReason) return false;
    if (_kind.needsSlug && _slug.text.trim() != _t.slug) return false;
    return switch (_kind) {
      SupportActionKind.giftDays => _dayCount != null,
      SupportActionKind.recovery =>
        _checks.values.every((v) => v) && (!_payingWithPlay || _order.text.trim().isNotEmpty),
      _ => true,
    };
  }

  String get _confirmLabel => switch (_kind) {
        SupportActionKind.recovery => 'Enviar código',
        SupportActionKind.giftDays =>
          _dayCount == null ? 'Regalar días' : 'Regalar $_dayCount ${_dayCount == 1 ? 'día' : 'días'}',
        SupportActionKind.suspend => 'Suspender ${_t.name}',
        SupportActionKind.lift => 'Levantar la suspensión',
        SupportActionKind.export => 'Exportar y enviar al dueño',
        SupportActionKind.requestDeletion => 'Pedir la eliminación (1 de 2)',
        SupportActionKind.approveDeletion => 'Eliminar ${_t.name} para siempre',
        SupportActionKind.cancelDeletion => 'Cancelar la eliminación',
      };

  String get _title => switch (_kind) {
        SupportActionKind.recovery => 'Enviar código de acceso al dueño',
        SupportActionKind.giftDays => 'Regalar días a ${_t.name}',
        SupportActionKind.suspend => 'Suspender ${_t.name} por abuso',
        SupportActionKind.lift => 'Levantar la suspensión de ${_t.name}',
        SupportActionKind.export => 'Exportar los datos de ${_t.name}',
        SupportActionKind.requestDeletion => 'Eliminar ${_t.name}',
        SupportActionKind.approveDeletion => 'Aprobar la eliminación de ${_t.name}',
        SupportActionKind.cancelDeletion => 'Cancelar la eliminación de ${_t.name}',
      };

  String get _explanation {
    final s = widget.detail.support;
    return switch (_kind) {
      SupportActionKind.recovery =>
        'Para quien ya no puede entrar. Confirma con el dueño cada dato; el código le llega a su correo registrado, '
            'vence en 24 h y lo obliga a cambiar la contraseña. Tú no lo ves.',
      SupportActionKind.giftDays =>
        'Se suman a su vigencia (hoy: ${_t.paidUntil == null ? 'sin fecha' : 'hasta ${adminDate(_t.paidUntil!)}'}).',
      SupportActionKind.suspend =>
        'Bloquea la tienda de inmediato. Ni un pago ni un regalo de días la levantan: sólo "Levantar la suspensión". '
            'El dueño ve el motivo al abrir su app.',
      SupportActionKind.lift =>
        'La tienda vuelve a funcionar. Si su vigencia ya venció, queda bloqueada por falta de pago.',
      SupportActionKind.export =>
        'Se genera un archivo con todos sus datos y le llega al dueño por correo. Tú no ves el contenido.',
      SupportActionKind.requestDeletion =>
        'Borra la tienda y todos sus datos. Es irreversible. Otro fundador debe aprobarla en las próximas 72 h; si no, '
            'vence.',
      SupportActionKind.approveDeletion =>
        '${s.deletionRequestedBy ?? 'Otro fundador'} la pidió${(s.deletionReason ?? '').isEmpty ? '' : ': "${s.deletionReason}"'}. '
            'Al aprobar se borran la tienda y todos sus datos, de inmediato y sin vuelta atrás. El dueño recibe un '
            'correo avisándole.',
      SupportActionKind.cancelDeletion => 'La tienda sigue como está; si aún procede, habrá que pedirla de nuevo.',
    };
  }

  Future<void> _submit() async {
    if (_busy || !_valid) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final reason = _reason.text.trim();
    final detail = ref.read(tenantDetailProvider(_t.id).notifier);
    final me = ref.read(adminSessionProvider).session;
    try {
      final ActionOutcome outcome;
      switch (_kind) {
        case SupportActionKind.recovery:
          final sent = await _repo.assistedRecovery(
            _t.id,
            reason: reason,
            checks: Map.of(_checks),
            googleOrderId: _payingWithPlay ? _order.text : null,
          );
          detail.patchSupport((s) => s.copyWith(assistedCodeUntil: sent.expiresAt));
          outcome =
              ActionOutcome('Código enviado a ${sent.sentTo}; vence ${adminMoment(sent.expiresAt)}. Tú no lo ves.');
        case SupportActionKind.giftDays:
          final updated = await _repo.giftDays(_t.id, days: _dayCount!, reason: reason);
          detail.replace(updated);
          final until = updated.summary.paidUntil;
          outcome = ActionOutcome('Listo: regalaste $_dayCount ${_dayCount == 1 ? 'día' : 'días'}'
              '${until == null ? '' : '; vigente hasta ${adminDate(until)}'}. El dueño lo verá en Actividad de soporte.');
        case SupportActionKind.suspend:
          detail.replace(await _repo.suspend(_t.id, reason: reason));
          outcome = ActionOutcome('Suspendiste ${_t.name}. El dueño ve el motivo al abrir su app.');
        case SupportActionKind.lift:
          detail.replace(await _repo.lift(_t.id, reason: reason));
          outcome = ActionOutcome('Levantaste la suspensión de ${_t.name}.');
        case SupportActionKind.export:
          final status = await _repo.export(_t.id, reason: reason);
          detail.patchSupport((s) => s.copyWith(lastExportStatus: status, lastExportAt: DateTime.now()));
          outcome = const ActionOutcome('Exportación en proceso: le llegará al dueño por correo.');
        case SupportActionKind.requestDeletion:
          final req = await _repo.requestDeletion(_t.id, reason: reason, confirmSlug: _slug.text);
          detail.patchSupport((s) => s.copyWith(
                deletion: (
                  id: req.id,
                  byId: req.requestedById ?? me?.operatorId,
                  by: req.requestedBy ?? me?.shortName,
                  reason: req.reason.isEmpty ? reason : req.reason,
                  expiresAt: req.expiresAt,
                ),
              ));
          outcome = ActionOutcome('Pediste eliminar ${_t.name}. Falta que otro fundador la apruebe antes del '
              '${adminDate(req.expiresAt)}.');
        case SupportActionKind.approveDeletion:
          await _repo.approveDeletion(widget.detail.support.deletionRequestId!, reason: reason);
          outcome =
              ActionOutcome('Se eliminó ${_t.name} y todos sus datos. El dueño recibió un correo.', storeDeleted: true);
        case SupportActionKind.cancelDeletion:
          await _repo.cancelDeletion(widget.detail.support.deletionRequestId!, reason: reason);
          detail.patchSupport((s) => s.copyWith(clearDeletion: true));
          outcome = ActionOutcome('Cancelaste la eliminación de ${_t.name}.');
      }
      if (mounted) Navigator.of(context).pop(outcome);
    } on AdminApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final destructive = _kind.destructive;
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
          bindings: {const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.of(context).pop()},
          child: Column(
            key: Key('actionDialog_${_kind.name}'),
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 22, 24, 6),
                child: Semantics(
                  header: true,
                  child: Text(
                    _title,
                    style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: AppColors.onSurface),
                  ),
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 6, 24, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(_explanation,
                          style: const TextStyle(fontSize: 14, color: AppColors.onSurfaceMuted, height: 1.45)),
                      const SizedBox(height: 16),
                      ..._fields(),
                      TextField(
                        key: const Key('actionReason'),
                        controller: _reason,
                        enabled: !_busy,
                        autofocus: _kind != SupportActionKind.giftDays && _kind != SupportActionKind.recovery,
                        minLines: 2,
                        maxLines: 4,
                        maxLength: 500,
                        onChanged: (_) => _changed(),
                        decoration: InputDecoration(
                          labelText: _kind.ownerReadsReason
                              ? 'Motivo — lo leerá el dueño en su app'
                              : 'Motivo (queda en la bitácora)',
                          alignLabelWithHint: true,
                        ),
                        buildCounter: (context, {required currentLength, required isFocused, maxLength}) => Text(
                          currentLength < SupportActionDialog.minReason
                              ? 'Mínimo ${SupportActionDialog.minReason} caracteres ($currentLength)'
                              : '$currentLength / $maxLength',
                          style: const TextStyle(fontSize: 12, color: AppColors.onSurfaceMuted),
                        ),
                      ),
                      if (_kind.needsSlug) ...[
                        const SizedBox(height: 10),
                        Text.rich(
                          TextSpan(children: [
                            const TextSpan(text: 'Para confirmar, escribe el slug de la tienda: '),
                            TextSpan(text: _t.slug, style: adminMonoStyle.copyWith(fontSize: 13.5)),
                          ]),
                          style: const TextStyle(fontSize: 13, color: AppColors.onSurface, height: 1.4),
                        ),
                        const SizedBox(height: 6),
                        TextField(
                          key: const Key('actionSlug'),
                          controller: _slug,
                          enabled: !_busy,
                          onChanged: (_) => setState(() => _error = null),
                          style: adminMonoStyle.copyWith(fontSize: 15),
                          decoration: InputDecoration(hintText: _t.slug),
                        ),
                      ],
                      if (_kind.preview != null) ...[
                        const SizedBox(height: 16),
                        ActionPreviewCard(preview: _preview, loading: _previewLoading, failed: _previewFailed),
                      ] else if (_kind == SupportActionKind.approveDeletion) ...[
                        const SizedBox(height: 12),
                        const Text(
                          'No hay vista previa: la tienda deja de existir. El dueño recibe un correo avisándole.',
                          style: TextStyle(fontSize: 13, color: AppColors.onSurfaceMuted, height: 1.4),
                        ),
                      ],
                      if (_error != null) ...[
                        const SizedBox(height: 14),
                        Semantics(
                          liveRegion: true,
                          child: Container(
                            key: const Key('actionError'),
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
                                Expanded(
                                  child: Text(_error!,
                                      style: const TextStyle(fontSize: 13.5, color: AppColors.onSurface, height: 1.4)),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
                child: Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    OutlinedButton(
                      key: const Key('actionCancel'),
                      onPressed: _busy ? null : () => Navigator.of(context).pop(),
                      child: const Text('Cancelar'),
                    ),
                    FilledButton(
                      key: const Key('actionConfirm'),
                      onPressed: _busy || !_valid ? null : _submit,
                      style: destructive
                          ? FilledButton.styleFrom(backgroundColor: AdminColors.danger, foregroundColor: Colors.white)
                          : null,
                      child: Text(_busy ? 'Enviando…' : _confirmLabel),
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

  List<Widget> _fields() => switch (_kind) {
        SupportActionKind.giftDays => [
            TextField(
              key: const Key('actionDays'),
              controller: _days,
              enabled: !_busy,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(2)],
              onChanged: (_) => _changed(),
              decoration: const InputDecoration(labelText: 'Días', helperText: 'De 1 a 90'),
            ),
            const SizedBox(height: 14),
          ],
        SupportActionKind.recovery => [
            const Text('Lo que el dueño te dijo (debe coincidir):',
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: AppColors.onSurface)),
            const SizedBox(height: 4),
            _check('store_name', 'El nombre de la tienda', _t.name),
            _check('owner_email', 'El correo con el que entra', _t.ownerEmail ?? 'sin dueño activo'),
            _check('signup_date', 'Cuándo se registró, aproximadamente', adminDate(_t.createdAt)),
            _check(
              'employees',
              'Quiénes trabajan en la tienda',
              widget.detail.users.where((u) => u.isActive).map((u) => u.fullName).join(', '),
            ),
            if (_payingWithPlay) ...[
              const SizedBox(height: 8),
              TextField(
                key: const Key('actionOrder'),
                controller: _order,
                enabled: !_busy,
                onChanged: (_) => setState(() => _error = null),
                decoration: const InputDecoration(
                  labelText: 'Número de orden de Google Play (GPA.…)',
                  helperText: 'Paga con Google Play: pídeselo al dueño',
                ),
              ),
            ],
            const SizedBox(height: 14),
          ],
        _ => const [],
      };

  Widget _check(String key, String label, String expected) => CheckboxListTile(
        key: Key('actionCheck_$key'),
        value: _checks[key],
        onChanged: _busy ? null : (v) => setState(() => _checks[key] = v ?? false),
        controlAffinity: ListTileControlAffinity.leading,
        contentPadding: EdgeInsets.zero,
        dense: true,
        title: Text(label, style: const TextStyle(fontSize: 14, color: AppColors.onSurface)),
        subtitle: Text('Debe coincidir con: $expected',
            style: const TextStyle(fontSize: 12.5, color: AppColors.onSurfaceMuted)),
      );
}

/// "Así lo verá la tienda": el texto del servidor con el estilo de la
/// Actividad de soporte de la app del tendero (la única cita de su mundo en
/// el panel).
class ActionPreviewCard extends StatelessWidget {
  const ActionPreviewCard({super.key, required this.preview, required this.loading, required this.failed});
  final OwnerPreview? preview;
  final bool loading;
  final bool failed;

  @override
  Widget build(BuildContext context) {
    final p = preview;
    return Column(
      key: const Key('actionPreview'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Así lo verá la tienda',
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.onSurfaceMuted)),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            color: AppColors.darkSlate,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: failed && p == null
              ? const Text('No pudimos mostrar la vista previa; puedes enviar igual (el servidor valida).',
                  style: TextStyle(fontSize: 13, color: AppColors.onSurfaceMuted))
              : p == null
                  ? Text(loading ? 'Preparando la vista previa…' : 'Completa los datos para ver cómo le llegará.',
                      style: const TextStyle(fontSize: 13, color: AppColors.onSurfaceMuted))
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(p.summary,
                            key: const Key('actionPreviewSummary'),
                            style: const TextStyle(fontSize: 14, color: AppColors.onSurface, height: 1.4)),
                        if ((p.reason ?? '').isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text('"${p.reason}"',
                              style: const TextStyle(fontSize: 13.5, color: AppColors.onSurfaceMuted, height: 1.4)),
                        ],
                        const SizedBox(height: 6),
                        Text(p.by,
                            style:
                                const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.emerald)),
                      ],
                    ),
        ),
      ],
    );
  }
}
