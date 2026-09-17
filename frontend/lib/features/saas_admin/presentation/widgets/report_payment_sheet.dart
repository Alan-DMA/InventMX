import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import '../../data/saas_repository.dart';
import '../../domain/subscription.dart';
import '../saas_provider.dart';

/// "Ya pagué" — Tarea 14.2.1 (Constitución Art. V §5.2, SPEI manual).
///
/// Pide lo mínimo para que un fundador encuentre el pago en el banco: método
/// y referencia (clave de rastreo SPEI, referencia OXXO o una nota si fue en
/// efectivo). Al enviar, el estado queda visible en la pantalla: "Recibimos
/// tu aviso" — nunca un envío al vacío.
Future<PaymentValidation?> showReportPaymentSheet(
  BuildContext context, {
  required double amountMxn,
  SaasPaymentMethod initialMethod = SaasPaymentMethod.spei,
}) {
  return showModalBottomSheet<PaymentValidation>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => ReportPaymentSheet(
      amountMxn: amountMxn,
      initialMethod: initialMethod,
    ),
  );
}

class ReportPaymentSheet extends ConsumerStatefulWidget {
  const ReportPaymentSheet({
    super.key,
    required this.amountMxn,
    this.initialMethod = SaasPaymentMethod.spei,
  });

  final double amountMxn;
  final SaasPaymentMethod initialMethod;

  @override
  ConsumerState<ReportPaymentSheet> createState() => _ReportPaymentSheetState();
}

class _ReportPaymentSheetState extends ConsumerState<ReportPaymentSheet> {
  late SaasPaymentMethod _method = widget.initialMethod;
  final _reference = TextEditingController();
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _reference.dispose();
    super.dispose();
  }

  String get _hint => switch (_method) {
        SaasPaymentMethod.spei => 'Clave de rastreo o folio de tu banco',
        SaasPaymentMethod.oxxo => 'Número de la referencia que pagaste',
        SaasPaymentMethod.efectivo => '¿A quién y cuándo se lo entregaste?',
      };

  Future<void> _submit() async {
    final ref0 = _reference.text.trim();
    if (ref0.length < 4) {
      setState(() => _error = 'Escribe la referencia (mínimo 4 caracteres).');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final validation = await ref
          .read(subscriptionProvider.notifier)
          .reportPayment(method: _method, reference: ref0);
      if (!mounted) return;
      Navigator.of(context).pop(validation);
    } on SaasException catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = 'No pudimos registrar tu aviso. Inténtalo de nuevo.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Avísanos que ya pagaste',
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.onSurface),
          ),
          const SizedBox(height: 4),
          Text(
            'Pagaste ${mxn(widget.amountMxn)} MXN. Un fundador lo revisa en el banco, '
            'tu cuenta se actualiza y te avisamos aquí; mientras, sigue como está.',
            style: const TextStyle(
                fontSize: 13.5, color: AppColors.onSurfaceMuted, height: 1.4),
          ),
          const SizedBox(height: 16),
          SegmentedButton<SaasPaymentMethod>(
            segments: const [
              ButtonSegment(value: SaasPaymentMethod.spei, label: Text('SPEI')),
              ButtonSegment(value: SaasPaymentMethod.oxxo, label: Text('OXXO')),
              ButtonSegment(
                  value: SaasPaymentMethod.efectivo, label: Text('Efectivo')),
            ],
            selected: {_method},
            onSelectionChanged: (s) => setState(() => _method = s.first),
            style: ButtonStyle(
              visualDensity: VisualDensity.compact,
              side: WidgetStateProperty.all(
                  const BorderSide(color: AppColors.border)),
              backgroundColor: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.selected)
                    ? AppColors.emerald.withValues(alpha: 0.18)
                    : Colors.transparent,
              ),
              foregroundColor: WidgetStateProperty.all(AppColors.onSurface),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            key: const Key('paymentReferenceField'),
            controller: _reference,
            autofocus: true,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
            style: const TextStyle(color: AppColors.onSurface, fontSize: 16),
            decoration: InputDecoration(
              labelText: 'Referencia',
              hintText: _hint,
              errorText: _error,
              filled: true,
              fillColor: AppColors.surfaceVariant,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 48,
            child: FilledButton(
              key: const Key('submitPaymentReport'),
              onPressed: _sending ? null : _submit,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.emerald,
                foregroundColor: AppColors.darkSlate,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: _sending
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppColors.darkSlate),
                    )
                  : const Text('Enviar aviso',
                      style:
                          TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }
}
