import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/theme/app_colors.dart';
import '../../management/domain/app_permission.dart' show Permissions;
import '../../management/presentation/management_provider.dart'
    show hasPermissionProvider;
import '../../onboarding/presentation/onboarding_provider.dart';
import '../data/sales_repository.dart' show SaleNotFoundException;
import '../domain/cart_state.dart';
import 'sales_kardex_provider.dart';
import 'widgets/refund_sale_modal.dart';
import 'widgets/sale_receipt_card.dart';

/// Pantalla mostrada tras un cobro exitoso — Tarea 8.2.
///
/// Muestra el comprobante de venta (`SaleReceiptCard`) y permite compartirlo
/// por WhatsApp o iniciar una nueva venta.
///
/// Con [isLookup] (Fase 2, kardex de ventas) es la **consulta** de un ticket
/// ya cobrado: sin el aviso de "¡Venta registrada!" (celebrar algo que no
/// acaba de pasar mentiría), el folio como título y sin "Nueva Venta" —
/// se conserva compartir por WhatsApp, que es a lo que se viene.
///
/// Trazabilidad: Doc. Maestro RF-08 (Sección 5.2), Sección 6 (SR-05)
///              Constitución Art. VIII (8.2) · HU-14 / CU-16
class SaleReceiptScreen extends ConsumerStatefulWidget {
  const SaleReceiptScreen({
    super.key,
    required this.result,
    this.isLookup = false,
  });

  final CheckoutResult result;
  final bool isLookup;

  @override
  ConsumerState<SaleReceiptScreen> createState() => _SaleReceiptScreenState();
}

class _SaleReceiptScreenState extends ConsumerState<SaleReceiptScreen> {
  /// Permite capturar únicamente la tarjeta del ticket (sin el AppBar ni los
  /// botones de acción) como imagen PNG.
  final _receiptKey = GlobalKey();

  bool _isSharing = false;

  /// Reemplazada tras un reembolso exitoso — refleja el cambio al instante
  /// sin esperar a que `SaleLookupScreen` vuelva a resolver el provider.
  CheckoutResult? _updatedResult;

  CheckoutResult get result => _updatedResult ?? widget.result;

  @override
  Widget build(BuildContext context) {
    final onboarding = ref.watch(onboardingProvider).data;
    final businessName = onboarding.businessName.isEmpty
        ? 'NEXUS STORE'
        : onboarding.businessName;
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
          icon:
              const Icon(Icons.arrow_back_rounded, color: AppColors.onSurface),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(
          widget.isLookup ? result.folio : 'Comprobante de Venta',
          style: const TextStyle(
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
              if (!widget.isLookup) ...[
                const _SuccessIndicator(),
                const SizedBox(height: 8),
              ] else if (result.isRefunded) ...[
                _RefundedBanner(refund: result.refund!),
                const SizedBox(height: 12),
              ],
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
              if (!widget.isLookup) ...[
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
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ] else if (!result.isRefunded &&
                  ref.watch(
                      hasPermissionProvider(Permissions.ventasEliminar))) ...[
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: OutlinedButton.icon(
                    key: const Key('refundSaleButton'),
                    onPressed: _handleRefund,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.error,
                      side: const BorderSide(color: AppColors.error),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    icon: const Icon(Icons.assignment_return_rounded, size: 20),
                    label: const Text(
                      'Reembolsar',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
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

  /// Abre la hoja de reembolso (Fase 2 — acciones sobre la venta) y, si se
  /// confirma, refresca este ticket, la consulta por id y el kardex para que
  /// la etiqueta "Reembolsada" aparezca en todas partes sin recargar todo.
  Future<void> _handleRefund() async {
    final updated = await showRefundSaleModal(context, sale: result);
    if (updated == null || !mounted) return;
    setState(() => _updatedResult = updated);
    ref.invalidate(saleDetailProvider(updated.saleId));
    ref.invalidate(salesKardexProvider);
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
// Aviso de venta reembolsada
// ---------------------------------------------------------------------------

class _RefundedBanner extends StatelessWidget {
  const _RefundedBanner({required this.refund});
  final SaleRefund refund;

  @override
  Widget build(BuildContext context) {
    final d = refund.refundedAt;
    final date = '${d.day.toString().padLeft(2, '0')}/'
        '${d.month.toString().padLeft(2, '0')}/${d.year}';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.assignment_return_rounded,
              size: 18, color: AppColors.error),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Reembolsada el $date',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.error,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  refund.reason,
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.onSurfaceMuted),
                ),
              ],
            ),
          ),
        ],
      ),
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

// ---------------------------------------------------------------------------
// Consulta por id — `GET /sales/{id}` (Fase 2, kardex de ventas)
// ---------------------------------------------------------------------------

/// Resuelve la venta por id y muestra el ticket en modo consulta. Va por
/// ruta (`/ventas/historial/:id`) y no por objeto para que el swap al
/// backend sea sólo el repositorio.
class SaleLookupScreen extends ConsumerWidget {
  const SaleLookupScreen({super.key, required this.saleId});

  final String saleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sale = ref.watch(saleDetailProvider(saleId));

    return sale.when(
      data: (result) => SaleReceiptScreen(result: result, isLookup: true),
      loading: () => const _LookupShell(
        child: Center(
          child: CircularProgressIndicator(color: AppColors.emerald),
        ),
      ),
      error: (e, _) => _LookupShell(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  e is SaleNotFoundException
                      ? Icons.receipt_long_outlined
                      : Icons.cloud_off_rounded,
                  size: 48,
                  color: AppColors.onSurfaceMuted,
                ),
                const SizedBox(height: 12),
                Text(
                  e is SaleNotFoundException
                      ? 'Esta venta ya no está\ndisponible'
                      : 'No se pudo cargar\nel ticket',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: AppColors.onSurface,
                    height: 1.4,
                  ),
                ),
                if (e is! SaleNotFoundException) ...[
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () => ref.invalidate(saleDetailProvider(saleId)),
                    icon: const Icon(Icons.refresh_rounded, size: 16),
                    label: const Text('Reintentar'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LookupShell extends StatelessWidget {
  const _LookupShell({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkSlate,
      appBar: AppBar(
        backgroundColor: AppColors.darkSlate,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon:
              const Icon(Icons.arrow_back_rounded, color: AppColors.onSurface),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: SafeArea(child: child),
    );
  }
}
