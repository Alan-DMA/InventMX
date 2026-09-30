import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../core/admin_colors.dart';
import '../../core/admin_theme.dart';

/// Título de cada paso del acceso y una línea que dice qué hacer.
class AccessHeading extends StatelessWidget {
  const AccessHeading({super.key, required this.title, required this.hint});
  final String title;
  final String hint;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(
              title,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: AppColors.onSurface, height: 1.2),
            ),
          ),
          const SizedBox(height: 8),
          Text(hint, style: const TextStyle(fontSize: 14.5, color: AppColors.onSurfaceMuted, height: 1.45)),
        ],
      );
}

enum AccessMessageTone { error, locked, info }

/// Mensaje en su lugar (no SnackBar): quien no puede entrar tiene que poder
/// releerlo. El tono se escribe con ícono y texto, nunca sólo con color.
class AccessMessage extends StatelessWidget {
  const AccessMessage(this.text, {super.key, this.tone = AccessMessageTone.error});
  final String text;
  final AccessMessageTone tone;

  @override
  Widget build(BuildContext context) {
    final (Color color, IconData icon) = switch (tone) {
      AccessMessageTone.error => (AppColors.error, Icons.error_outline_rounded),
      AccessMessageTone.locked => (AdminColors.amber, Icons.lock_clock_outlined),
      AccessMessageTone.info => (AppColors.skyBlue, Icons.info_outline_rounded),
    };
    return Semantics(
      liveRegion: true,
      child: Container(
        key: const Key('accessMessage'),
        padding: const EdgeInsets.fromLTRB(12, 10, 14, 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Text(text, style: const TextStyle(fontSize: 13.5, color: AppColors.onSurface, height: 1.4)),
            ),
          ],
        ),
      ),
    );
  }
}

/// El código de Authenticator: mono grande con espacio amplio entre cifras
/// (es un dato que se teclea y se compara con el teléfono). Acepta pegar
/// "123 456" y se envía solo al completar los 6 dígitos.
class TotpCodeField extends StatelessWidget {
  const TotpCodeField({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.onCompleted,
    this.enabled = true,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onCompleted;
  final bool enabled;

  @override
  Widget build(BuildContext context) => TextField(
        key: const Key('accessCodeField'),
        controller: controller,
        focusNode: focusNode,
        enabled: enabled,
        autofocus: true,
        keyboardType: TextInputType.number,
        textAlign: TextAlign.center,
        autofillHints: const [AutofillHints.oneTimeCode],
        inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
        style: adminMonoStyle.copyWith(fontSize: 28, letterSpacing: 10, fontWeight: FontWeight.w600),
        decoration: const InputDecoration(
          labelText: 'Código de 6 dígitos',
          hintText: '······',
          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        ),
        onChanged: (value) {
          if (value.length == 6) onCompleted(value);
        },
        onSubmitted: (value) {
          if (value.length == 6) onCompleted(value);
        },
      );
}

/// Botón principal de cada paso, con estado de "trabajando" escrito.
class AccessPrimaryButton extends StatelessWidget {
  const AccessPrimaryButton({
    super.key,
    required this.label,
    required this.busyLabel,
    required this.busy,
    required this.onPressed,
  });

  final String label;
  final String busyLabel;
  final bool busy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: double.infinity,
        child: FilledButton(
          key: const Key('accessSubmit'),
          onPressed: busy ? null : onPressed,
          style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
          child: busy
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onSurfaceMuted),
                    ),
                    const SizedBox(width: 10),
                    Text(busyLabel),
                  ],
                )
              : Text(label),
        ),
      );
}

/// QR de vinculación sobre blanco (los lectores necesitan contraste y margen
/// en blanco) y la clave para teclearla a mano, en grupos de 4.
class EnrollmentBlock extends StatelessWidget {
  const EnrollmentBlock({super.key, required this.otpauthUri, required this.manualSecret, required this.onCopySecret});
  final String otpauthUri;
  final String manualSecret;
  final VoidCallback onCopySecret;

  static String grouped(String secret) {
    final clean = secret.replaceAll(' ', '');
    return [for (var i = 0; i < clean.length; i += 4) clean.substring(i, (i + 4).clamp(0, clean.length))].join(' ');
  }

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Wrap(
          spacing: 20,
          runSpacing: 16,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Semantics(
              label: 'Código QR para vincular Google Authenticator',
              image: true,
              child: Container(
                key: const Key('accessEnrollQr'),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
                child: QrImageView(data: otpauthUri, size: 156, padding: EdgeInsets.zero),
              ),
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 190),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '¿No puedes escanearlo? Escribe esta clave en Authenticator:',
                    style: TextStyle(fontSize: 13, color: AppColors.onSurfaceMuted, height: 1.4),
                  ),
                  const SizedBox(height: 8),
                  SelectableText(
                    grouped(manualSecret),
                    key: const Key('accessEnrollSecret'),
                    style: adminMonoStyle.copyWith(fontSize: 15, height: 1.5, letterSpacing: 1),
                  ),
                  const SizedBox(height: 4),
                  TextButton.icon(
                    key: const Key('accessCopySecret'),
                    onPressed: onCopySecret,
                    icon: const Icon(Icons.copy_rounded, size: 16),
                    label: const Text('Copiar clave'),
                    style: TextButton.styleFrom(padding: EdgeInsets.zero),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

/// Los 10 códigos de recuperación en rejilla de 2 × 5: se leen en pares, se
/// comparan contra lo que se guardó.
class RecoveryCodesGrid extends StatelessWidget {
  const RecoveryCodesGrid({super.key, required this.codes});
  final List<String> codes;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < codes.length; i += 2) {
      rows.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            for (final code in codes.skip(i).take(2))
              Expanded(
                child: SelectableText(
                  code,
                  textAlign: TextAlign.center,
                  style: adminMonoStyle.copyWith(fontSize: 16, letterSpacing: 1.2),
                ),
              ),
          ],
        ),
      ));
    }
    return Container(
      key: const Key('accessRecoveryCodes'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(children: rows),
    );
  }
}
