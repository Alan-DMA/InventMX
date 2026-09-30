import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_colors.dart';

/// Columna de las pantallas de acceso (login, recuperar, código, contraseña
/// nueva): centrada, 420 px de ancho máximo, título y explicación arriba.
class AuthLayout extends StatelessWidget {
  const AuthLayout({
    super.key,
    required this.title,
    required this.message,
    required this.children,
    this.showBack = true,
  });

  final String title;
  final String message;
  final List<Widget> children;

  /// La pantalla de contraseña nueva no deja volver: la salida es "Cerrar sesión".
  final bool showBack;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: showBack,
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(title, style: Theme.of(context).textTheme.headlineMedium),
                  const SizedBox(height: 10),
                  Text(
                    message,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.onSurfaceMuted,
                          height: 1.45,
                        ),
                  ),
                  const SizedBox(height: 28),
                  ...children,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Mensaje de error junto al campo (no un SnackBar que se va): quien está en
/// crisis tiene que poder releerlo.
class InlineError extends StatelessWidget {
  const InlineError(this.message, {super.key});
  final String message;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 1),
              child: Icon(Icons.error_outline_rounded, size: 18, color: AppColors.error),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(fontSize: 13.5, color: AppColors.error, height: 1.4),
              ),
            ),
          ],
        ),
      );
}

/// Botón principal de las pantallas de acceso con su estado de carga.
class AuthPrimaryButton extends StatelessWidget {
  const AuthPrimaryButton({super.key, required this.label, required this.onPressed, this.loading = false});

  final String label;
  final VoidCallback? onPressed;
  final bool loading;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 52,
        child: ElevatedButton(
          onPressed: loading ? null : onPressed,
          child: loading
              ? const SizedBox(
                  height: 22,
                  width: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.darkSlate),
                )
              : Text(label),
        ),
      );
}

/// El código de un solo uso: mayúsculas, sólo letras y números del alfabeto
/// del servidor, y el guion después de los primeros cuatro (`K7PM-Q3XR`).
class AccessCodeFormatter extends TextInputFormatter {
  static final _allowed = RegExp('[A-Z0-9]');

  /// Largo sin guion.
  static const length = 8;

  static String raw(String text) =>
      text.toUpperCase().split('').where(_allowed.hasMatch).take(length).join();

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final chars = raw(newValue.text);
    final formatted = chars.length > 4 ? '${chars.substring(0, 4)}-${chars.substring(4)}' : chars;
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
