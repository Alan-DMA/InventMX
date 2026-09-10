// ignore_for_file: prefer_const_constructors
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../../../core/theme/app_colors.dart';
import '../data/import_repository.dart';
import 'inventory_provider.dart';
import 'widgets/scan_result_card.dart';

/// Pantalla de escaneo continuo de góndola (Modo Ráfaga).
///
/// Flujo por cada código detectado:
///   1. Cámara detecta EAN → lookup en catálogo semilla (mock)
///   2. Si encontrado  → ScanResultCard con nombre/categoría autocompletados
///   3. Si no encontrado → ScanResultCard con nombre editable
///   4. Al confirmar → createProduct() en InventoryNotifier → vibración + reset
///
/// La cámara permanece activa entre escaneos; el usuario nunca sale
/// de la pantalla hasta que pulsa el botón de cierre.
///
/// Trazabilidad: Constitución Art. II (2.5), Art. VII (7.8)
///              Doc. Maestro RF-30 · HU-10 / CU-10
class GondolaScanScreen extends ConsumerStatefulWidget {
  const GondolaScanScreen({super.key});

  @override
  ConsumerState<GondolaScanScreen> createState() => _GondolaScanScreenState();
}

class _GondolaScanScreenState extends ConsumerState<GondolaScanScreen> {
  // ── Cámara ───────────────────────────────────────────────────────────────
  final MobileScannerController _scanner = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    facing: CameraFacing.back,
  );

  // ── Estado de la sesión ──────────────────────────────────────────────────
  int _scannedCount = 0;

  // ── Estado del escaneo actual ────────────────────────────────────────────
  String? _currentBarcode;
  EanLookupResult? _lookupResult;
  bool _isLookingUp = false;
  bool _cardVisible = false;
  bool _isSaving = false;

  // ── Control de throttle — evita procesar el mismo EAN dos veces seguidas ─
  String? _lastProcessedBarcode;
  DateTime? _lastScanTime;

  @override
  void dispose() {
    _scanner.dispose();
    super.dispose();
  }

  // ── Handlers ─────────────────────────────────────────────────────────────

  Future<void> _onBarcodeDetected(BarcodeCapture capture) async {
    if (_cardVisible || _isLookingUp || _isSaving) return;

    final barcode = capture.barcodes.firstOrNull?.rawValue;
    if (barcode == null || barcode.isEmpty) return;

    // Throttle: ignora el mismo código si fue procesado hace menos de 2s
    final now = DateTime.now();
    if (_lastProcessedBarcode == barcode &&
        _lastScanTime != null &&
        now.difference(_lastScanTime!) < const Duration(seconds: 2)) {
      return;
    }

    _lastProcessedBarcode = barcode;
    _lastScanTime = now;

    // Feedback háptico al detectar el código
    HapticFeedback.lightImpact();

    setState(() {
      _currentBarcode = barcode;
      _isLookingUp = true;
      _cardVisible = false;
      _lookupResult = null;
    });

    try {
      final result =
          await ref.read(importRepositoryProvider).lookupEan(barcode);
      if (!mounted) return;
      setState(() {
        _lookupResult = result;
        _isLookingUp = false;
        _cardVisible = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLookingUp = false;
        _cardVisible = true;
      });
    }
  }

  Future<void> _onConfirm(String name, double priceMxn, int stock) async {
    setState(() => _isSaving = true);

    try {
      await ref.read(inventoryProvider.notifier).addProduct(
            name: name,
            priceMxn: priceMxn,
            stock: stock,
          );

      // Feedback de éxito: vibración doble
      HapticFeedback.mediumImpact();
      await Future.delayed(const Duration(milliseconds: 120));
      HapticFeedback.mediumImpact();

      if (!mounted) return;
      setState(() {
        _scannedCount++;
        _isSaving = false;
        _cardVisible = false;
        _currentBarcode = null;
        _lookupResult = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al guardar: ${e.toString()}'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _dismissCard() {
    setState(() {
      _cardVisible = false;
      _currentBarcode = null;
      _lookupResult = null;
      // Limpia el throttle para permitir re-escanear el mismo código
      _lastProcessedBarcode = null;
    });
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.black.withValues(alpha: 0.55),
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              size: 20, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Modo Góndola',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        actions: [
          // Contador de sesión
          if (_scannedCount > 0)
            Center(
              child: Container(
                margin: const EdgeInsets.only(right: 8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.emerald.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.check_rounded,
                        size: 14, color: AppColors.darkSlate),
                    const SizedBox(width: 4),
                    Text(
                      '$_scannedCount agregados',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.darkSlate,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          // Toggle flash
          IconButton(
            icon: const Icon(Icons.flash_on_rounded,
                size: 22, color: Colors.white70),
            onPressed: () => _scanner.toggleTorch(),
            tooltip: 'Linterna',
          ),
        ],
      ),
      body: Stack(
        children: [
          // ── Vista de cámara ───────────────────────────────────────────
          _CameraViewport(
            scanner: _scanner,
            onDetected: _onBarcodeDetected,
            isCardVisible: _cardVisible,
            isLookingUp: _isLookingUp,
            currentBarcode: _currentBarcode,
          ),

          // ── Overlay inferior: card de resultado ───────────────────────
          Positioned(
            left: 0,
            right: 0,
            bottom: MediaQuery.of(context).padding.bottom + 24,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              transitionBuilder: (child, anim) => SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.2),
                  end: Offset.zero,
                ).animate(CurvedAnimation(
                  parent: anim,
                  curve: Curves.easeOutCubic,
                )),
                child: FadeTransition(opacity: anim, child: child),
              ),
              child: _cardVisible && _currentBarcode != null
                  ? KeyedSubtree(
                      key: ValueKey(_currentBarcode),
                      child: _isSaving
                          ? _SavingOverlay(barcode: _currentBarcode!)
                          : ScanResultCard(
                              barcode: _currentBarcode!,
                              suggestedName: _lookupResult?.name,
                              suggestedCategory: _lookupResult?.category,
                              onConfirm: _onConfirm,
                              onDismiss: _dismissCard,
                            ),
                    )
                  : const SizedBox.shrink(),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Viewport de cámara con overlay de guía
// ---------------------------------------------------------------------------

class _CameraViewport extends StatelessWidget {
  const _CameraViewport({
    required this.scanner,
    required this.onDetected,
    required this.isCardVisible,
    required this.isLookingUp,
    required this.currentBarcode,
  });

  final MobileScannerController scanner;
  final void Function(BarcodeCapture) onDetected;
  final bool isCardVisible;
  final bool isLookingUp;
  final String? currentBarcode;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Cámara real
        MobileScanner(
          controller: scanner,
          onDetect: onDetected,
        ),

        // Overlay semitransparente en la parte inferior cuando hay card
        if (isCardVisible)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: MediaQuery.of(context).size.height * 0.55,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.85),
                  ],
                ),
              ),
            ),
          ),

        // Marco de escaneo — visible cuando la cámara está activa y sin card
        if (!isCardVisible)
          Center(
            child: _ScanFrame(isLookingUp: isLookingUp),
          ),

        // Indicador de lookup en progreso
        if (isLookingUp && currentBarcode != null)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              color: AppColors.darkSlate.withValues(alpha: 0.7),
              padding: EdgeInsets.fromLTRB(
                16,
                MediaQuery.of(context).padding.top + 64,
                16,
                12,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.emerald,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Buscando $currentBarcode…',
                    style: const TextStyle(
                      fontSize: 13,
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
            ),
          ),

        // Instrucción en la parte inferior cuando cámara activa sin card
        if (!isCardVisible && !isLookingUp)
          Positioned(
            left: 16,
            right: 16,
            bottom: MediaQuery.of(context).padding.bottom + 32,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                'Apunta la cámara al código de barras del producto',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.white70,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Marco animado de escaneo
// ---------------------------------------------------------------------------

class _ScanFrame extends StatefulWidget {
  const _ScanFrame({required this.isLookingUp});
  final bool isLookingUp;

  @override
  State<_ScanFrame> createState() => _ScanFrameState();
}

class _ScanFrameState extends State<_ScanFrame>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulse = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _pulse,
      child: CustomPaint(
        size: const Size(240, 120),
        painter: _FramePainter(
          color: widget.isLookingUp ? AppColors.warning : AppColors.emerald,
        ),
      ),
    );
  }
}

/// Dibuja las 4 esquinas del marco de escaneo.
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

    // Esquina superior-izquierda — Offset/Rect usan variables, no pueden ser const
    canvas.drawLine(Offset(r, 0), Offset(cornerLen, 0), paint);
    canvas.drawLine(Offset(0, r), Offset(0, cornerLen), paint);
    canvas.drawArc(
        Rect.fromLTWH(0, 0, r * 2, r * 2), 3.14, -1.57, false, paint);

    // Esquina superior-derecha
    canvas.drawLine(Offset(w - cornerLen, 0), Offset(w - r, 0), paint);
    canvas.drawLine(Offset(w, r), Offset(w, cornerLen), paint);
    canvas.drawArc(
        Rect.fromLTWH(w - r * 2, 0, r * 2, r * 2), 4.71, -1.57, false, paint);

    // Esquina inferior-izquierda
    canvas.drawLine(Offset(0, h - cornerLen), Offset(0, h - r), paint);
    canvas.drawLine(Offset(r, h), Offset(cornerLen, h), paint);
    canvas.drawArc(
        Rect.fromLTWH(0, h - r * 2, r * 2, r * 2), 1.57, -1.57, false, paint);

    // Esquina inferior-derecha
    canvas.drawLine(Offset(w, h - cornerLen), Offset(w, h - r), paint);
    canvas.drawLine(Offset(w - cornerLen, h), Offset(w - r, h), paint);
    canvas.drawArc(Rect.fromLTWH(w - r * 2, h - r * 2, r * 2, r * 2), 0, -1.57,
        false, paint);
  }

  @override
  bool shouldRepaint(_FramePainter old) => old.color != color;
}

// ---------------------------------------------------------------------------
// Overlay de guardado en progreso
// ---------------------------------------------------------------------------

class _SavingOverlay extends StatelessWidget {
  const _SavingOverlay({required this.barcode});
  final String barcode;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.emerald.withValues(alpha: 0.4),
        ),
      ),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: AppColors.emerald,
            ),
          ),
          SizedBox(width: 14),
          Text(
            'Guardando producto…',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}
