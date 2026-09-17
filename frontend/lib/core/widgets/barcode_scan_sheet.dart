import 'dart:math' show max;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../theme/app_colors.dart';

/// Escáner mínimo reutilizable: abre la cámara, devuelve el primer código
/// leído (o el tecleado a mano) y se cierra. Sin búsqueda ni lógica de
/// negocio — eso lo decide quien lo abre (POS: buscar/sugerir; edición:
/// rellenar el campo).
///
/// Misma anatomía que el escáner de búsqueda de Inventario
/// (`BarcodeSearchModal`): pantalla completa sobre negro, marco de esquinas
/// pulsante, controles en píldora arriba y tarjeta de entrada manual abajo —
/// el tendero no debe notar que son dos widgets distintos.
///
/// Devuelve `null` si el usuario cierra sin escanear.
Future<String?> showBarcodeScanSheet(
  BuildContext context, {
  String title = 'Escanear código de barras',
  String hint = 'Apunta al código de barras o ingrésalo manualmente:',
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    backgroundColor: Colors.black,
    builder: (_) => BarcodeScanSheet(title: title, hint: hint),
  );
}

class BarcodeScanSheet extends StatefulWidget {
  const BarcodeScanSheet({super.key, required this.title, required this.hint});

  final String title;
  final String hint;

  @override
  State<BarcodeScanSheet> createState() => _BarcodeScanSheetState();
}

class _BarcodeScanSheetState extends State<BarcodeScanSheet> {
  final MobileScannerController _scanner = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    facing: CameraFacing.back,
  );
  final TextEditingController _manual = TextEditingController();

  bool _done = false;

  @override
  void dispose() {
    _scanner.dispose();
    _manual.dispose();
    super.dispose();
  }

  void _finish(String raw) {
    final code = raw.trim();
    if (_done || code.isEmpty) return;
    _done = true;
    HapticFeedback.lightImpact();
    Navigator.of(context).pop(code);
  }

  void _onDetect(BarcodeCapture capture) {
    final code = capture.barcodes.firstOrNull?.rawValue;
    if (code != null) _finish(code);
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // ── Cámara ────────────────────────────────────────────────────────
          Positioned.fill(
            child: MobileScanner(
              controller: _scanner,
              onDetect: _onDetect,
              errorBuilder: (_, error, __) => _CameraUnavailable(error: error),
            ),
          ),

          // ── Marco de escaneo ──────────────────────────────────────────────
          const Positioned.fill(child: Center(child: _ScanFrame())),

          // ── Controles superiores ──────────────────────────────────────────
          Positioned(
            top: mq.padding.top + 8,
            left: 16,
            right: 16,
            child: Row(
              children: [
                IconButton(
                  key: const Key('scanCloseButton'),
                  tooltip: 'Cerrar',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const _Pill(
                      child: Icon(Icons.close_rounded,
                          color: Colors.white, size: 20)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      widget.title,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  key: const Key('scanTorchButton'),
                  tooltip: 'Linterna',
                  onPressed: () => _scanner.toggleTorch(),
                  icon: const _Pill(
                      child: Icon(Icons.flash_on_rounded,
                          color: Colors.white, size: 20)),
                ),
              ],
            ),
          ),

          // ── Tarjeta inferior: entrada manual ──────────────────────────────
          Positioned(
            left: 16,
            right: 16,
            bottom: max(mq.viewInsets.bottom, mq.padding.bottom) + 16,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    widget.hint,
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.onSurfaceMuted),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          key: const Key('scanManualField'),
                          controller: _manual,
                          keyboardType: TextInputType.number,
                          style: const TextStyle(
                              color: AppColors.onSurface, fontSize: 14),
                          decoration: InputDecoration(
                            hintText: 'Ej. 7501055300075',
                            hintStyle: const TextStyle(
                                color: AppColors.onSurfaceMuted, fontSize: 13),
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 12),
                            filled: true,
                            fillColor: AppColors.surfaceVariant,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                          ),
                          onSubmitted: _finish,
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        key: const Key('scanManualButton'),
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(80, 44),
                          backgroundColor: AppColors.skyBlue,
                          foregroundColor: AppColors.darkSlate,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 18, vertical: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () => _finish(_manual.text),
                        child: const Text('Usar',
                            style: TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Piezas visuales (mismo lenguaje que BarcodeSearchModal)
// ---------------------------------------------------------------------------

class _Pill extends StatelessWidget {
  const _Pill({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        shape: BoxShape.circle,
      ),
      child: child,
    );
  }
}

class _ScanFrame extends StatefulWidget {
  const _ScanFrame();

  @override
  State<_ScanFrame> createState() => _ScanFrameState();
}

class _ScanFrameState extends State<_ScanFrame>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat(reverse: true);
  late final Animation<double> _pulse = Tween<double>(begin: 0.9, end: 1.0)
      .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _pulse,
      child: const CustomPaint(
        size: Size(260, 140),
        painter: _FramePainter(color: AppColors.emerald),
      ),
    );
  }
}

class _FramePainter extends CustomPainter {
  const _FramePainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 3.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    const cornerLen = 28.0;
    const r = 8.0;
    final w = size.width;
    final h = size.height;

    canvas.drawLine(const Offset(r, 0), const Offset(cornerLen, 0), paint);
    canvas.drawLine(const Offset(0, r), const Offset(0, cornerLen), paint);
    canvas.drawArc(
        const Rect.fromLTWH(0, 0, r * 2, r * 2), 3.14, -1.57, false, paint);

    canvas.drawLine(Offset(w - cornerLen, 0), Offset(w - r, 0), paint);
    canvas.drawLine(Offset(w, r), Offset(w, cornerLen), paint);
    canvas.drawArc(
        Rect.fromLTWH(w - r * 2, 0, r * 2, r * 2), 4.71, -1.57, false, paint);

    canvas.drawLine(Offset(0, h - cornerLen), Offset(0, h - r), paint);
    canvas.drawLine(Offset(r, h), Offset(cornerLen, h), paint);
    canvas.drawArc(
        Rect.fromLTWH(0, h - r * 2, r * 2, r * 2), 1.57, -1.57, false, paint);

    canvas.drawLine(Offset(w, h - cornerLen), Offset(w, h - r), paint);
    canvas.drawLine(Offset(w - cornerLen, h), Offset(w - r, h), paint);
    canvas.drawArc(Rect.fromLTWH(w - r * 2, h - r * 2, r * 2, r * 2), 0, -1.57,
        false, paint);
  }

  @override
  bool shouldRepaint(_FramePainter old) => old.color != color;
}

class _CameraUnavailable extends StatelessWidget {
  const _CameraUnavailable({required this.error});
  final MobileScannerException error;

  @override
  Widget build(BuildContext context) {
    final denied = error.errorCode == MobileScannerErrorCode.permissionDenied;
    return ColoredBox(
      color: AppColors.darkSlate,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(32, 32, 32, 160),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.no_photography_outlined,
                  size: 40, color: AppColors.onSurfaceMuted),
              const SizedBox(height: 12),
              Text(
                denied
                    ? 'Sin permiso de cámara. Actívalo en Ajustes del teléfono para escanear.'
                    : 'No se pudo abrir la cámara. Puedes teclear el código abajo.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 13, color: AppColors.onSurfaceMuted, height: 1.4),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
