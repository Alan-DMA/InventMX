import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/capture_quality.dart';
import '../../../core/utils/viewfinder_region.dart';
import '../../../core/widgets/scan_corner_frame.dart';
import '../domain/receipt_scan.dart';
import 'purchases_provider.dart';
import 'widgets/capture_guidance.dart';

/// Cada cuánto se evalúa un cuadro. Analizar todos los frames satura el hilo
/// en los teléfonos de gama baja que son el objetivo del proyecto, y el
/// usuario no reacciona más rápido que esto de todos modos.
const _kAnalysisInterval = Duration(milliseconds: 400);

/// Marco guía: vertical para remisiones y tickets, apaisado para órdenes de
/// compra impresas en horizontal. Solo lo que queda dentro se lee.
const _kPortraitFrame = Size(300, 400);
const _kLandscapeFrame = Size(400, 260);

/// Captura de la factura con revisión previa de condiciones — Tarea 12.2.1.
///
/// Sustituye al disparo directo con `image_picker`: antes de dejar tomar la
/// foto se comprueba en vivo que haya luz, que el OCR ya esté leyendo texto,
/// que la hoja llene el encuadre y que no esté torcida. Una foto mala aquí se
/// paga después con renglones mal leídos que el usuario tiene que corregir a
/// mano frente al repartidor.
///
/// **El bloqueo nunca es absoluto:** "Tomar de todos modos" está siempre
/// disponible. Una factura arrugada o en papel térmico decolorado puede no
/// pasar nunca la revisión, y dejar al usuario sin salida sería peor que una
/// foto mediocre.
///
/// Devuelve un [ReceiptCapture] con la ruta de la foto y la región del marco
/// guía (Q-01: solo se lee lo que el usuario vio dentro del marco), o `null`
/// si canceló.
class ReceiptCaptureScreen extends ConsumerStatefulWidget {
  const ReceiptCaptureScreen({super.key});

  @override
  ConsumerState<ReceiptCaptureScreen> createState() =>
      _ReceiptCaptureScreenState();
}

class _ReceiptCaptureScreenState extends ConsumerState<ReceiptCaptureScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;
  final _tracker = CaptureReadinessTracker();

  CaptureAssessment? _assessment;
  bool _isReady = false;
  bool _isAnalyzing = false;
  bool _isCapturing = false;
  bool _torchOn = false;
  DateTime _lastAnalysis = DateTime.fromMillisecondsSinceEpoch(0);

  /// Mensaje de error de inicialización — cámara ausente o permiso negado.
  String? _cameraError;

  /// Tamaño del visor y del marco guía en el último `build` — con ellos se
  /// calcula qué parte de la foto corresponde a lo que el usuario encuadró.
  Size? _viewportSize;
  Size _frameSize = _kPortraitFrame;
  bool _portraitViewport = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;

    // Android suelta la cámara al pasar a segundo plano; hay que rearmarla.
    if (state == AppLifecycleState.inactive) {
      controller.dispose();
      _controller = null;
    } else if (state == AppLifecycleState.resumed) {
      _initCamera();
    }
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (mounted) {
          setState(() => _cameraError = 'Este equipo no tiene cámara.');
        }
        return;
      }

      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      final controller = CameraController(
        back,
        // `medium` basta para el OCR y deja margen de FPS para analizar cada
        // cuadro; la foto final se toma a la resolución del sensor.
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.nv21,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }

      await controller.startImageStream(_onFrame);
      setState(() {
        _controller = controller;
        _cameraError = null;
      });
    } on CameraException catch (e) {
      if (!mounted) return;
      setState(() {
        _cameraError = e.code == 'CameraAccessDenied'
            ? 'Nexus necesita permiso de cámara para leer la factura. '
                'Actívalo en los ajustes del teléfono.'
            : 'No se pudo abrir la cámara.';
      });
    }
  }

  Future<void> _onFrame(CameraImage frame) async {
    if (_isAnalyzing || _isCapturing || !mounted) return;

    final now = DateTime.now();
    if (now.difference(_lastAnalysis) < _kAnalysisInterval) return;
    _lastAnalysis = now;
    _isAnalyzing = true;

    try {
      final assessment = await ref.read(captureFrameAnalyzerProvider).analyze(
            frame,
            _controller?.description.sensorOrientation ?? 0,
          );
      final stable = _tracker.update(assessment);
      if (!mounted) return;
      setState(() {
        _assessment = assessment;
        _isReady = stable;
      });
    } catch (_) {
      // Un cuadro que ML Kit no pudo procesar no es un error de la pantalla:
      // se descarta y se evalúa el siguiente.
    } finally {
      _isAnalyzing = false;
    }
  }

  Future<void> _toggleTorch() async {
    final controller = _controller;
    if (controller == null) return;
    try {
      await controller.setFlashMode(_torchOn ? FlashMode.off : FlashMode.torch);
      if (mounted) setState(() => _torchOn = !_torchOn);
    } on CameraException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Este equipo no permite encender la linterna.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _capture() async {
    final controller = _controller;
    if (controller == null || _isCapturing) return;

    setState(() => _isCapturing = true);
    try {
      // El disparo con el stream activo falla en varios equipos Android.
      if (controller.value.isStreamingImages) {
        await controller.stopImageStream();
      }
      final photo = await controller.takePicture();
      if (!mounted) return;

      // Q-01: la foto es el cuadro completo del sensor; el visor solo mostró
      // la parte que cabía en pantalla. Se anota la región del marco para
      // que el OCR ignore todo lo demás. Sin medida del visor (no debería
      // pasar tras el primer build) se lee la foto completa.
      final viewport = _viewportSize;
      final region = viewport == null
          ? null
          : viewfinderRegion(
              viewport: viewport,
              frame: _frameSize,
              previewAspect: _portraitViewport
                  ? 1 / controller.value.aspectRatio
                  : controller.value.aspectRatio,
            );
      Navigator.of(context).pop(
        ReceiptCapture.single(
          photo.path,
          region: region,
          portraitViewport: _portraitViewport,
        ),
      );
    } on CameraException {
      if (!mounted) return;
      setState(() => _isCapturing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo tomar la foto. Intenta de nuevo.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: AppColors.onSurface,
        title: const Text('Escanear factura'),
        actions: [
          if (_controller != null)
            IconButton(
              key: const Key('torchButton'),
              tooltip: _torchOn ? 'Apagar linterna' : 'Encender linterna',
              onPressed: _toggleTorch,
              icon: Icon(
                _torchOn
                    ? Icons.flashlight_on_rounded
                    : Icons.flashlight_off_rounded,
                color: _torchOn ? AppColors.warning : AppColors.onSurface,
              ),
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: _cameraError != null
          ? _CameraErrorState(
              message: _cameraError!,
              onManual: () => Navigator.of(context).pop(),
            )
          : _buildViewfinder(),
    );
  }

  Widget _buildViewfinder() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.emerald),
      );
    }

    // Una orden de compra apaisada se fotografía con el teléfono en
    // horizontal: el marco sigue a la pantalla en vez de pedir girar la hoja.
    final landscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    final frame = landscape ? _kLandscapeFrame : _kPortraitFrame;
    final previewAspect = landscape
        ? controller.value.aspectRatio
        : 1 / controller.value.aspectRatio;

    return LayoutBuilder(
      builder: (context, constraints) {
        // Se anota lo que el usuario está viendo para que `_capture` pueda
        // limitar la lectura al marco (Q-01).
        _viewportSize = Size(constraints.maxWidth, constraints.maxHeight);
        _frameSize = frame;
        _portraitViewport = !landscape;

        return Stack(
          fit: StackFit.expand,
          children: [
            // La vista previa cubre el visor sin deformarse; lo que se
            // recorta por los lados es justo lo que `viewfinderRegion`
            // descuenta después.
            ClipRect(
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: 100 * previewAspect,
                  height: 100,
                  child: CameraPreview(controller),
                ),
              ),
            ),

            // Marco guía — verde solo cuando la toma se mantuvo estable.
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ScanCornerFrame(
                    color: _isReady ? AppColors.emerald : AppColors.warning,
                    size: frame,
                    animate: !_isReady,
                  ),
                  const SizedBox(height: 10),
                  const _FrameCaption(),
                ],
              ),
            ),

            Positioned(
              left: 16,
              right: 16,
              top: 16,
              child: Center(
                child: CaptureGuidance(
                  assessment: _assessment,
                  isReady: _isReady,
                ),
              ),
            ),

            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _CaptureBar(
                isReady: _isReady,
                isCapturing: _isCapturing,
                onCapture: _capture,
              ),
            ),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Leyenda del marco
// ---------------------------------------------------------------------------

/// Dice para qué es el marco. Es la instrucción más barata contra el ruido:
/// si el usuario encuadra solo la tabla de productos, la fecha, el RFC y el
/// teléfono del proveedor nunca llegan al OCR (Tarea 12.2, QA de ruido).
class _FrameCaption extends StatelessWidget {
  const _FrameCaption();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('frameCaption'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.darkSlate.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Text(
        'Encuadra solo la tabla de productos — lo de fuera no se lee',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 12,
          height: 1.3,
          color: AppColors.onSurfaceMuted,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Barra de disparo
// ---------------------------------------------------------------------------

class _CaptureBar extends StatelessWidget {
  const _CaptureBar({
    required this.isReady,
    required this.isCapturing,
    required this.onCapture,
  });

  final bool isReady;
  final bool isCapturing;
  final VoidCallback onCapture;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.black.withValues(alpha: 0.85)],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ShutterButton(
            isReady: isReady,
            isCapturing: isCapturing,
            onPressed: onCapture,
          ),
          const SizedBox(height: 12),
          // Salida siempre disponible: la revisión orienta, no encierra.
          // Una factura arrugada puede no pasarla nunca.
          if (!isReady && !isCapturing)
            TextButton(
              key: const Key('forceCaptureButton'),
              onPressed: onCapture,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.onSurfaceMuted,
              ),
              child: const Text('Tomar de todos modos'),
            ),
        ],
      ),
    );
  }
}

class _ShutterButton extends StatelessWidget {
  const _ShutterButton({
    required this.isReady,
    required this.isCapturing,
    required this.onPressed,
  });

  final bool isReady;
  final bool isCapturing;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final color = isReady ? AppColors.emerald : AppColors.surfaceVariant;

    return Semantics(
      button: true,
      label: isReady ? 'Tomar la foto' : 'Aún no se puede tomar la foto',
      child: SizedBox(
        width: 76,
        height: 76,
        child: Material(
          color: color,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: const Key('shutterButton'),
            onTap: isCapturing || !isReady ? null : onPressed,
            child: Center(
              child: isCapturing
                  ? const SizedBox(
                      width: 26,
                      height: 26,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.6,
                        color: AppColors.darkSlate,
                      ),
                    )
                  : Icon(
                      Icons.photo_camera_rounded,
                      size: 30,
                      color: isReady
                          ? AppColors.darkSlate
                          : AppColors.onSurfaceMuted,
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Cámara no disponible
// ---------------------------------------------------------------------------

class _CameraErrorState extends StatelessWidget {
  const _CameraErrorState({required this.message, required this.onManual});

  final String message;
  final VoidCallback onManual;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.no_photography_outlined,
                  size: 42, color: AppColors.warning),
            ),
            const SizedBox(height: 20),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                height: 1.5,
                color: AppColors.onSurface,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: onManual,
              child: const Text('Capturar a mano'),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Origen de la foto
// ---------------------------------------------------------------------------

/// De dónde sale la foto de la factura.
///
/// Existe para que los tests del flujo de compras puedan inyectar una ruta
/// fija: la pantalla de cámara necesita hardware y no se puede montar en
/// `flutter test`.
abstract interface class ReceiptPhotoSource {
  /// Foto tomada y región del marco guía, o `null` si el usuario canceló.
  Future<ReceiptCapture?> capture(BuildContext context);
}

class CameraReceiptPhotoSource implements ReceiptPhotoSource {
  const CameraReceiptPhotoSource();

  @override
  Future<ReceiptCapture?> capture(BuildContext context) =>
      Navigator.of(context).push<ReceiptCapture>(
        MaterialPageRoute(builder: (_) => const ReceiptCaptureScreen()),
      );
}
