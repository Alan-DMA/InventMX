import 'dart:io';
import 'dart:math' as math show max, Random;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import '../../../../../../core/theme/app_colors.dart';
import '../../domain/product.dart';

// ---------------------------------------------------------------------------
// Función de conveniencia
// ---------------------------------------------------------------------------

Future<void> showProductLabelModal(BuildContext context, Product product) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    backgroundColor: Colors.transparent,
    builder: (_) => ProductLabelModal(product: product),
  );
}

// ---------------------------------------------------------------------------
// CustomPainter — Barcode Code128 simplificado
// ---------------------------------------------------------------------------

class _BarcodePainter extends CustomPainter {
  const _BarcodePainter({required this.code, required this.color});

  final String code;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final rng = math.Random(
      code.codeUnits.fold<int>(0, (a, b) => a + b),
    );

    const barCount = 60;
    final totalWidth = size.width;
    double x = 0;

    for (int i = 0; i < barCount; i++) {
      final isBar = i.isEven;
      final widthFactor = (rng.nextInt(4) + 1).toDouble();
      final barW = (totalWidth / barCount) * widthFactor * 0.6;

      if (isBar) {
        canvas.drawRect(
            Rect.fromLTWH(x, 0, barW.clamp(1, barW), size.height), paint);
      }
      x += barW;
      if (x >= totalWidth) break;
    }
  }

  @override
  bool shouldRepaint(_BarcodePainter old) =>
      old.code != code || old.color != color;
}

// ---------------------------------------------------------------------------
// Widget principal
// ---------------------------------------------------------------------------

class ProductLabelModal extends StatefulWidget {
  const ProductLabelModal({super.key, required this.product});

  final Product product;

  @override
  State<ProductLabelModal> createState() => _ProductLabelModalState();
}

class _ProductLabelModalState extends State<ProductLabelModal> {
  int _copies = 1;
  bool _isSharing = false;

  /// GlobalKey para capturar el widget de etiqueta como imagen PNG.
  final _labelKey = GlobalKey();

  // ── Compartir como imagen ─────────────────────────────────────────────────

  Future<void> _share() async {
    setState(() => _isSharing = true);
    try {
      // 1. Captura el widget renderizado a imagen con pixelRatio 3x para
      //    garantizar buena resolución en impresión o visualización.
      final boundary = _labelKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) return;

      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;

      // 2. Escribe los bytes en un archivo temporal.
      final tempDir = await getTemporaryDirectory();
      final fileName =
          'etiqueta_${widget.product.sku}_${DateTime.now().millisecondsSinceEpoch}.png';
      final file = File('${tempDir.path}/$fileName');
      await file.writeAsBytes(byteData.buffer.asUint8List());

      // 3. Comparte el archivo PNG con la hoja nativa del SO.
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'image/png')],
        subject: 'Etiqueta: ${widget.product.name}',
      );
    } finally {
      if (mounted) setState(() => _isSharing = false);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final bottomInset = math.max(mq.viewInsets.bottom, mq.padding.bottom);

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(24, 12, 24, 24 + bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _handle(),
          _header(),
          const SizedBox(height: 20),
          _labelPreview(),
          const SizedBox(height: 20),
          _copiesSelector(),
          const SizedBox(height: 24),
          _actionButtons(),
        ],
      ),
    );
  }

  Widget _handle() => Center(
        child: Container(
          width: 40,
          height: 4,
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: AppColors.border,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      );

  Widget _header() => Row(
        children: [
          const Expanded(
            child: Text(
              'Vista previa de etiqueta',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.onSurface),
            ),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded,
                size: 22, color: AppColors.onSurfaceMuted),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      );

  // ── Preview de etiqueta ───────────────────────────────────────────────────

  Widget _labelPreview() {
    final barcode = widget.product.barcode ?? widget.product.sku;

    return Center(
      // RepaintBoundary con key — permite capturar este widget exacto
      // como imagen PNG sin interferencia del resto del árbol de widgets.
      child: RepaintBoundary(
        key: _labelKey,
        child: Container(
          width: 260,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Nombre del comercio (placeholder)
                const Text(
                  'Nexus',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF374151),
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  widget.product.name,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF111827),
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.product.sku,
                  style: const TextStyle(
                    fontSize: 10,
                    color: Color(0xFF6B7280),
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  height: 50,
                  child: CustomPaint(
                    painter: _BarcodePainter(
                      code: barcode,
                      color: const Color(0xFF111827),
                    ),
                    size: const Size(double.infinity, 50),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  barcode,
                  style: const TextStyle(
                    fontSize: 9,
                    color: Color(0xFF374151),
                    letterSpacing: 1.2,
                    fontFamily: 'monospace',
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  '\$${widget.product.priceMxn.toStringAsFixed(2)} MXN',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF111827),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Selector de copias ─────────────────────────────────────────────────────

  Widget _copiesSelector() => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text(
            'Cantidad de etiquetas:',
            style: TextStyle(fontSize: 13, color: AppColors.onSurfaceMuted),
          ),
          const SizedBox(width: 16),
          _stepBtn(Icons.remove_rounded, () {
            if (_copies > 1) setState(() => _copies--);
          }),
          const SizedBox(width: 12),
          SizedBox(
            width: 36,
            child: Text(
              '$_copies',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.onSurface),
            ),
          ),
          const SizedBox(width: 12),
          _stepBtn(Icons.add_rounded, () => setState(() => _copies++)),
        ],
      );

  Widget _stepBtn(IconData icon, VoidCallback onTap) => Material(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: 36,
            height: 36,
            child: Icon(icon, size: 18, color: AppColors.onSurface),
          ),
        ),
      );

  // ── Botones de acción ──────────────────────────────────────────────────────

  Widget _actionButtons() => Row(
        children: [
          Expanded(
            child: ElevatedButton.icon(
              onPressed: _isSharing ? null : _share,
              icon: _isSharing
                  ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppColors.darkSlate))
                  : const Icon(Icons.share_rounded, size: 18),
              label: const Text('Compartir imagen'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Impresión térmica — próximamente'),
                  behavior: SnackBarBehavior.floating,
                ),
              ),
              icon: const Icon(Icons.print_rounded, size: 18),
              label: const Text('Imprimir'),
            ),
          ),
        ],
      );
}
