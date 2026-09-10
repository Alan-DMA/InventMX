import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/theme/app_colors.dart';
import '../../onboarding/presentation/onboarding_provider.dart';
import '../domain/cart_state.dart';
import 'widgets/sale_receipt_card.dart';

/// Pantalla mostrada tras un cobro exitoso — Tarea 8.2.
///
/// Muestra el comprobante de venta (`SaleReceiptCard`) y permite compartirlo
/// por WhatsApp o iniciar una nueva venta.
///
/// Trazabilidad: Doc. Maestro RF-08 (Sección 5.2), Sección 6 (SR-05)
///              Constitución Art. VIII (8.2) · HU-14 / CU-16
class SaleReceiptScreen extends ConsumerWidget {
  const SaleReceiptScreen({super.key, required this.result});

  final CheckoutResult result;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final onboarding = ref.watch(onboardingProvider).data;
    final businessName =
        onboarding.businessName.isEmpty ? 'NEXUS STORE' : onboarding.businessName;
    final footerMessage = onboarding.ticketHeader.isEmpty
        ? '¡Gracias por su compra!'
        : onboarding.ticketHeader;

    return Scaffold(
      backgroundColor: AppColors.darkSlate,
      appBar: AppBar(
        backgroundColor: AppColors.darkSlate,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.onSurface),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text(
          'Comprobante de Venta',
          style: TextStyle(
            color: AppColors.skyBlue,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 13, 16, 24),
          child: Column(
            children: [
              const _SuccessIndicator(),
              const SizedBox(height: 8),
              SaleReceiptCard(
                result: result,
                businessName: businessName,
                warehouseName: onboarding.warehouseName,
                footerMessage: footerMessage,
                pageBackground: AppColors.darkSlate,
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: _SecondaryActionButton(
                      icon: Icons.share_rounded,
                      label: 'WhatsApp',
                      foregroundColor: AppColors.onSurface,
                      borderColor: AppColors.border,
                      onTap: () => _shareReceipt(
                        businessName: businessName,
                        footerMessage: footerMessage,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _SecondaryActionButton(
                      icon: Icons.print_outlined,
                      label: 'Imprimir',
                      foregroundColor: AppColors.skyBlue,
                      borderColor: AppColors.skyBlue,
                      onTap: () => _showPrintBlocker(context),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton.icon(
                  onPressed: () => Navigator.of(context).maybePop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.emerald,
                    foregroundColor: AppColors.darkSlate,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  icon: const Icon(Icons.shopping_cart_rounded, size: 20),
                  label: const Text(
                    'Nueva Venta',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Comparte el comprobante como texto plano vía la hoja nativa de
  /// compartir (WhatsApp entre las opciones) — Tarea 8.2.2.
  ///
  /// Blocker: sin el endpoint `/sales/{id}/receipt` (Tarea 8.1.1) no hay PDF
  /// térmico real que adjuntar; se comparte el desglose en texto mientras
  /// tanto.
  Future<void> _shareReceipt({
    required String businessName,
    required String footerMessage,
  }) {
    final buffer = StringBuffer()
      ..writeln(businessName)
      ..writeln(result.folio)
      ..writeln('Atendió: ${result.cashierName}')
      ..writeln('---------------------------');
    for (final item in result.items) {
      buffer.writeln(
        '${item.name} x${item.quantity}  \$${item.subtotalMxn.toStringAsFixed(2)}',
      );
    }
    buffer
      ..writeln('---------------------------')
      ..writeln('Total: \$${result.totalMxn.toStringAsFixed(2)} MXN');
    for (final payment in result.payments) {
      buffer.writeln(
        '${payment.method.label}: \$${payment.amountMxn.toStringAsFixed(2)}',
      );
    }
    if (result.changeGivenMxn > 0) {
      buffer.writeln('Vuelto: \$${result.changeGivenMxn.toStringAsFixed(2)}');
    }
    buffer.writeln(footerMessage);

    return Share.share(buffer.toString(), subject: 'Comprobante ${result.folio}');
  }

  void _showPrintBlocker(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Impresión térmica disponible cuando el backend entregue el PDF (Tarea 8.1)',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Indicador de éxito
// ---------------------------------------------------------------------------

class _SuccessIndicator extends StatelessWidget {
  const _SuccessIndicator();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: AppColors.emerald.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.check_circle_rounded,
            color: AppColors.emerald,
            size: 48,
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          '¡Venta registrada!',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: AppColors.onSurface,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Botón secundario de acciones (WhatsApp / Imprimir)
// ---------------------------------------------------------------------------

class _SecondaryActionButton extends StatelessWidget {
  const _SecondaryActionButton({
    required this.icon,
    required this.label,
    required this.foregroundColor,
    required this.borderColor,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color foregroundColor;
  final Color borderColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          height: 72,
          decoration: BoxDecoration(
            border: Border.all(color: borderColor),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: foregroundColor, size: 20),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: foregroundColor,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
