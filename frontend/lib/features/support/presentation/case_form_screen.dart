import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../data/support_repository.dart';
import '../domain/support_models.dart';
import 'support_provider.dart';
import 'widgets/support_widgets.dart';

/// "Cuéntanos qué pasó" — el formulario del tema (P23). Los campos los define
/// el servidor (texto, texto largo, opciones); aquí se pintan. Con sesión
/// termina en el caso recién abierto; sin sesión (P24), en el acuse.
class CaseFormScreen extends ConsumerWidget {
  const CaseFormScreen({super.key, required this.topicKey, this.public = false});

  final String topicKey;
  final bool public;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final topicsAsync = ref.watch(public ? publicTopicsProvider : supportTopicsProvider);
    return Scaffold(
      backgroundColor: AppColors.darkSlate,
      appBar: AppBar(backgroundColor: AppColors.darkSlate, elevation: 0, title: const Text('Escribir a soporte')),
      body: topicsAsync.when(
        loading: () => const SupportSkeleton(rows: 4),
        error: (e, _) => SupportErrorState(
          message: errorText(e, 'No pudimos cargar el formulario.'),
          onRetry: () => ref.invalidate(public ? publicTopicsProvider : supportTopicsProvider),
        ),
        data: (topics) {
          final topic = topics.where((t) => t.key == topicKey).firstOrNull;
          if (topic == null) {
            return SupportErrorState(
              message: 'Este tema ya no está disponible.',
              onRetry: () => ref.invalidate(public ? publicTopicsProvider : supportTopicsProvider),
            );
          }
          return _CaseForm(topic: topic, public: public);
        },
      ),
    );
  }
}

class _CaseForm extends ConsumerStatefulWidget {
  const _CaseForm({required this.topic, required this.public});
  final HelpTopic topic;
  final bool public;

  @override
  ConsumerState<_CaseForm> createState() => _CaseFormState();
}

class _CaseFormState extends ConsumerState<_CaseForm> {
  static const minDescription = 10;

  final _formKey = GlobalKey<FormState>();
  late final Map<String, TextEditingController> _text = {
    for (final f in widget.topic.formFields)
      if (f.type != FormFieldType.select) f.key: TextEditingController(),
  };
  final Map<String, String> _choices = {};
  final _description = TextEditingController();
  final _accountEmail = TextEditingController();
  final _storeName = TextEditingController();
  final _contactEmail = TextEditingController();
  final _contactName = TextEditingController();

  bool _submitted = false;
  bool _sending = false;
  String? _error;
  String? _acceptedMessage;

  @override
  void dispose() {
    for (final c in [..._text.values, _description, _accountEmail, _storeName, _contactEmail, _contactName]) {
      c.dispose();
    }
    super.dispose();
  }

  Map<String, String> get _answers => {
        for (final f in widget.topic.formFields)
          f.key: f.type == FormFieldType.select ? (_choices[f.key] ?? '') : _text[f.key]!.text.trim(),
      };

  bool get _choicesComplete => widget.topic.formFields
      .where((f) => f.type == FormFieldType.select && f.required)
      .every((f) => (_choices[f.key] ?? '').isNotEmpty);

  Future<void> _send() async {
    setState(() => _submitted = true);
    final formOk = _formKey.currentState?.validate() ?? false;
    if (!formOk || !_choicesComplete) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    final repo = ref.read(supportRepositoryProvider);
    try {
      if (widget.public) {
        final account = _accountEmail.text.trim();
        final contact = _contactEmail.text.trim();
        final message = await repo.createPublicCase(
          topicKey: widget.topic.key,
          answers: _answers,
          description: _description.text.trim(),
          accountEmail: account,
          storeName: _storeName.text.trim(),
          contactEmail: contact.isEmpty ? account : contact,
          contactName: _contactName.text.trim(),
        );
        if (mounted) setState(() => _acceptedMessage = message);
      } else {
        final created = await repo.createCase(
          topicKey: widget.topic.key,
          answers: _answers,
          description: _description.text.trim(),
        );
        ref.invalidate(supportCasesProvider);
        if (!mounted) return;
        // El caso sustituye al artículo y al formulario: "atrás" vuelve a
        // donde empezó (Soporte, o la suspensión si vino de ahí).
        final router = GoRouter.of(context);
        router.pop();
        router.pushReplacement(AppRoutes.supportCasePath(created.id));
      }
    } on SupportException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  String? _required(String? v, String what) => (v == null || v.trim().isEmpty) ? 'Falta $what.' : null;

  String? _email(String? v, {bool optional = false}) {
    final value = v?.trim() ?? '';
    if (value.isEmpty) return optional ? null : 'Falta el correo.';
    if (!value.contains('@') || !value.contains('.')) return 'Revisa el correo: le falta algo.';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (_acceptedMessage != null) return _Accepted(message: _acceptedMessage!);

    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Text(
            widget.topic.title,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.onSurface, height: 1.2),
          ),
          const SizedBox(height: 6),
          Text(
            widget.public
                ? 'Te respondemos por correo. Nadie de Nexus te va a pedir tu contraseña.'
                : 'Te respondemos aquí, en la app, y también te avisamos por correo.',
            style: const TextStyle(fontSize: 13.5, color: AppColors.onSurfaceMuted, height: 1.4),
          ),
          const SizedBox(height: 20),
          if (widget.public) ...[
            TextFormField(
              key: const Key('publicAccountEmail'),
              controller: _accountEmail,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              decoration: const InputDecoration(labelText: 'Correo con el que entrabas a Nexus'),
              validator: (v) => _email(v),
            ),
            const SizedBox(height: 14),
            TextFormField(
              key: const Key('publicStoreName'),
              controller: _storeName,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Nombre de tu tienda'),
              validator: (v) => _required(v, 'el nombre de la tienda'),
            ),
            const SizedBox(height: 14),
            TextFormField(
              key: const Key('publicContactEmail'),
              controller: _contactEmail,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: '¿A qué correo te respondemos? (opcional)',
                helperText: 'Si ya no tienes el de tu cuenta, escribe otro. Si lo dejas vacío, usamos el de arriba.',
                helperMaxLines: 3,
              ),
              validator: (v) => _email(v, optional: true),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _contactName,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Tu nombre (opcional)'),
            ),
            const SizedBox(height: 22),
          ],
          for (final field in widget.topic.formFields) ...[
            if (field.type == FormFieldType.select)
              _Choices(
                field: field,
                selected: _choices[field.key],
                showError: _submitted && field.required && (_choices[field.key] ?? '').isEmpty,
                onSelected: (value) => setState(() => _choices[field.key] = value),
              )
            else
              TextFormField(
                key: Key('caseField_${field.key}'),
                controller: _text[field.key],
                minLines: field.type == FormFieldType.textarea ? 3 : 1,
                maxLines: field.type == FormFieldType.textarea ? 6 : 1,
                maxLength: 500,
                decoration: InputDecoration(
                  labelText: field.required ? field.label : '${field.label} (opcional)',
                  counterText: '',
                ),
                validator: (v) => field.required ? _required(v, 'esta respuesta') : null,
              ),
            const SizedBox(height: 16),
          ],
          TextFormField(
            key: const Key('caseDescription'),
            controller: _description,
            minLines: 4,
            maxLines: 10,
            maxLength: 2000,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Cuéntanos qué pasó',
              hintText: 'Qué hacías, qué esperabas y qué pasó en cambio.',
              alignLabelWithHint: true,
            ),
            validator: (v) => (v?.trim().length ?? 0) < minDescription
                ? 'Cuéntanos un poco más (al menos $minDescription letras).'
                : null,
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error!, key: const Key('caseFormError'),
                  style: const TextStyle(color: AppColors.error, fontSize: 13.5, height: 1.4)),
            ),
          const SizedBox(height: 20),
          SizedBox(
            height: 52,
            child: ElevatedButton(
              key: const Key('caseSendButton'),
              onPressed: _sending ? null : _send,
              child: _sending
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.darkSlate),
                    )
                  : const Text('Enviar a soporte'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Opciones como chips: se ven todas, un toque para elegir.
class _Choices extends StatelessWidget {
  const _Choices({required this.field, required this.selected, required this.showError, required this.onSelected});

  final FormFieldSpec field;
  final String? selected;
  final bool showError;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            field.required ? field.label : '${field.label} (opcional)',
            style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: AppColors.onSurface),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final option in field.options)
                ChoiceChip(
                  key: Key('caseChoice_${field.key}_$option'),
                  label: Text(option),
                  selected: selected == option,
                  onSelected: (_) => onSelected(option),
                  selectedColor: AppColors.emerald.withValues(alpha: 0.18),
                  backgroundColor: AppColors.surface,
                  side: BorderSide(color: selected == option ? AppColors.emerald : AppColors.border),
                  labelStyle: TextStyle(
                    color: selected == option ? AppColors.emerald : AppColors.onSurface,
                    fontWeight: selected == option ? FontWeight.w600 : FontWeight.w500,
                  ),
                  showCheckmark: false,
                  materialTapTargetSize: MaterialTapTargetSize.padded,
                ),
            ],
          ),
          if (showError)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text('Elige una opción.', style: TextStyle(color: AppColors.error, fontSize: 12.5)),
            ),
        ],
      );
}

/// Sin sesión: el acuse. Mismo texto exista o no la cuenta.
class _Accepted extends StatelessWidget {
  const _Accepted({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
        children: [
          const Icon(Icons.mark_email_read_outlined, size: 40, color: AppColors.emerald),
          const SizedBox(height: 16),
          const Text(
            'Recibimos tu mensaje',
            key: Key('publicCaseAccepted'),
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.onSurface),
          ),
          const SizedBox(height: 10),
          Text(message, style: const TextStyle(fontSize: 15, color: AppColors.onSurface, height: 1.5)),
          const SizedBox(height: 8),
          const Text(
            'Te llegará un correo con el número de tu caso. Es posible que te pidamos algunos datos de tu '
            'tienda para confirmar que la cuenta es tuya.',
            style: TextStyle(fontSize: 14, color: AppColors.onSurfaceMuted, height: 1.45),
          ),
          const SizedBox(height: 28),
          SizedBox(
            height: 52,
            child: OutlinedButton(
              key: const Key('publicCaseBackToLogin'),
              onPressed: () => context.go(AppRoutes.login),
              child: const Text('Volver al acceso'),
            ),
          ),
        ],
      );
}
