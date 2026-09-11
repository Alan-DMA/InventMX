import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
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
class SaleReceiptScreen extends ConsumerStatefulWidget {
  const SaleReceiptScreen({super.key, required this.result});

  final CheckoutResult result;

  @override
  ConsumerState<SaleReceiptScreen> createState() => _SaleReceiptScreenState();
}

class _SaleReceiptScreenState extends ConsumerState<SaleReceiptScreen> {
  /// Permite capturar únicamente la tarjeta del ticket (sin el AppBar ni los
  /// botones de acción) como imagen PNG.
  final _receiptKey = GlobalKey();

  bool _isSharing = false;

  CheckoutResult get result => widget.result;

  @override
  Widget build(BuildContext context) {
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
              // RepaintBoundary con key — permite capturar solo la tarjeta
              // del ticket (sin encabezado ni botones) como imagen PNG.
              RepaintBoundary(
                key: _receiptKey,
                child: SaleReceiptCard(
                  result: result,
                  businessName: businessName,
                  warehouseName: onboarding.warehouseName,
                  footerMessage: footerMessage,
                  pageBackground: AppColors.darkSlate,
                ),
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
                      isLoading: _isSharing,
                      onTap: _isSharing ? null : _shareReceiptAsImage,
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

  /// Comparte el ticket como imagen PNG (no texto plano) vía la hoja nativa
  /// de compartir — Tarea 8.2.2. Misma técnica de captura que
  /// `ProductLabelModal` (Tarea 4.2.A): `RenderRepaintBoundary.toImage`.
  Future<void> _shareReceiptAsImage() async {
    setState(() => _isSharing = true);
    try {
      final boundary = _receiptKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) return;

      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;

      final tempDir = await getTemporaryDirectory();
      final fileName =
          'ticket_${result.folio}_${DateTime.now().millisecondsSinceEpoch}.png';
      final file = File('${tempDir.path}/$fileName');
      await file.writeAsBytes(byteData.buffer.asUint8List());

      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'image/png')],
        subject: 'Comprobante ${result.folio}',
      );
    } finally {
      if (mounted) setState(() => _isSharing = false);
    }
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
    this.isLoading = false,
  });

  final IconData icon;
  final String label;
  final Color foregroundColor;
  final Color borderColor;
  final VoidCallback? onTap;
  final bool isLoading;

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
              if (isLoading)
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: foregroundColor,
                  ),
                )
              else
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
