// ignore_for_file: prefer_const_constructors
// Importación de utilidades matemáticas
import 'dart:math' show max;
// Importación de widgets de Flutter y servicios hápticos
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
// Importación de Riverpod para inyección de dependencias
import 'package:flutter_riverpod/flutter_riverpod.dart';
// Importación de GoRouter para navegación
import 'package:go_router/go_router.dart';
// Importación de la librería de escaneo de cámara
import 'package:mobile_scanner/mobile_scanner.dart';

// Importación del router del sistema
import '../../../../../../core/router/app_router.dart';
// Importación de la paleta de colores oficial
import '../../../../../../core/theme/app_colors.dart';
// Importación del repositorio de importación y catálogo semilla GS1
import '../../data/import_repository.dart';
// Importación del repositorio de inventario
import '../../data/inventory_repository.dart';
// Importación de la entidad Product
import '../../domain/product.dart';
// Importación del modal de alta de productos
import 'add_product_modal.dart';

// ---------------------------------------------------------------------------
// Función de conveniencia para abrir el modal de escaneo y búsqueda
// ---------------------------------------------------------------------------

/// Abre el modal de escaneo de código de barras desde la barra de búsqueda.
/// Retorna el código o término seleccionado para filtrar en la lista, o null si se cancela.
Future<String?> showBarcodeSearchModal(BuildContext context) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    backgroundColor: Colors.black,
    builder: (_) => const BarcodeSearchModal(),
  );
}

// ---------------------------------------------------------------------------
// Widget Principal del Modal
// ---------------------------------------------------------------------------

class BarcodeSearchModal extends ConsumerStatefulWidget {
  const BarcodeSearchModal({super.key});

  @override
  ConsumerState<BarcodeSearchModal> createState() => _BarcodeSearchModalState();
}

class _BarcodeSearchModalState extends ConsumerState<BarcodeSearchModal> {
  // Controlador de la cámara con detección sin duplicados
  final MobileScannerController _scanner = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    facing: CameraFacing.back,
  );

  // Controlador de texto para entrada manual de código de barras
  final TextEditingController _manualController = TextEditingController();

  // Estados del escaneo y búsqueda
  bool _isSearching = false;
  String? _scannedBarcode;
  Product? _foundProduct;
  EanLookupResult? _seedProduct;
  bool _notFound = false;
  String? _errorMessage;

  // Control de throttle para escaneo continuo
  String? _lastBarcode;
  DateTime? _lastScanTime;

  @override
  void dispose() {
    // Liberación del controlador de la cámara y de texto
    _scanner.dispose();
    _manualController.dispose();
    super.dispose();
  }

  /// Procesa el código de barras detectado por la cámara
  Future<void> _onBarcodeDetected(BarcodeCapture capture) async {
    if (_isSearching || _foundProduct != null || _seedProduct != null || _notFound) {
      return;
    }

    final rawCode = capture.barcodes.firstOrNull?.rawValue?.trim();
    if (rawCode == null || rawCode.isEmpty) return;

    // Throttle de 2 segundos para evitar rebotes
    final now = DateTime.now();
    if (_lastBarcode == rawCode &&
        _lastScanTime != null &&
        now.difference(_lastScanTime!) < const Duration(seconds: 2)) {
      return;
    }

    _lastBarcode = rawCode;
    _lastScanTime = now;

    // Ejecuta la búsqueda del código escaneado
    await _searchBarcode(rawCode);
  }

  /// Ejecuta la búsqueda del código en el catálogo local y en GS1 México
  Future<void> _searchBarcode(String barcode) async {
    final cleanCode = barcode.trim();
    if (cleanCode.isEmpty) return;

    // Cierra el foco del teclado antes de la transición
    FocusScope.of(context).unfocus();

    // Feedback háptico al escanear
    HapticFeedback.lightImpact();

    setState(() {
      _isSearching = true;
      _scannedBarcode = cleanCode;
      _foundProduct = null;
      _seedProduct = null;
      _notFound = false;
      _errorMessage = null;
    });

    try {
      // 1. Buscar en el catálogo de productos registrados del comercio
      final inventoryRepo = ref.read(inventoryRepositoryProvider);
      final productsRes = await inventoryRepo.getProducts(query: cleanCode, pageSize: 50);

      // Busca coincidencia exacta por código de barras o SKU
      final exact = productsRes.items.where((p) {
        final pBarcode = p.barcode?.trim();
        final pSku = p.sku.trim();
        return pBarcode == cleanCode ||
            pSku.toLowerCase() == cleanCode.toLowerCase() ||
            (pBarcode != null && pBarcode.contains(cleanCode));
      }).firstOrNull;

      if (exact != null) {
        // Encontrado en inventario registrado
        if (!mounted) return;
        HapticFeedback.mediumImpact();
        setState(() {
          _isSearching = false;
          _foundProduct = exact;
        });
        return;
      }

      // 2. Si no está registrado en el inventario local, buscar en el Catálogo Semilla GS1 México
      final importRepo = ref.read(importRepositoryProvider);
      final eanResult = await importRepo.lookupEan(cleanCode);

      if (eanResult != null) {
        // Encontrado en catálogo semilla GS1
        if (!mounted) return;
        HapticFeedback.lightImpact();
        setState(() {
          _isSearching = false;
          _seedProduct = eanResult;
        });
        return;
      }

      // 3. No encontrado en ninguna fuente
      if (!mounted) return;
      setState(() {
        _isSearching = false;
        _notFound = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSearching = false;
        _errorMessage = 'Error al consultar código: ${e.toString()}';
      });
    }
  }

  /// Reinicia el estado para permitir un nuevo escaneo
  void _resetScan() {
    setState(() {
      _isSearching = false;
      _scannedBarcode = null;
      _foundProduct = null;
      _seedProduct = null;
      _notFound = false;
      _errorMessage = null;
      _lastBarcode = null;
      _manualController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final isResultVisible = _foundProduct != null || _seedProduct != null || _notFound || _isSearching || _errorMessage != null;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // ── Vista de Cámara ───────────────────────────────────────────────
          Positioned.fill(
            child: MobileScanner(
              controller: _scanner,
              onDetect: _onBarcodeDetected,
            ),
          ),

          // ── Overlay Oscuro con Marco de Escaneo ──────────────────────────
          if (!isResultVisible)
            Positioned.fill(
              child: Center(
                child: _ScanFrame(isSearching: _isSearching),
              ),
            ),

          // ── Barra Superior con Controles ──────────────────────────────────
          Positioned(
            top: mq.padding.top + 8,
            left: 16,
            right: 16,
            child: Row(
              children: [
                // Botón Cerrar
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.close_rounded, color: Colors.white, size: 20),
                  ),
                ),
                const SizedBox(width: 8),
                // Título
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'Escanear Código de Barras',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Botón Linterna / Flash
                IconButton(
                  onPressed: () => _scanner.toggleTorch(),
                  icon: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.flash_on_rounded, color: Colors.white, size: 20),
                  ),
                ),
              ],
            ),
          ),

          // ── Panel Inferior (Resultado o Entrada Manual) ────────────────────
          Positioned(
            left: 16,
            right: 16,
            bottom: max(mq.viewInsets.bottom, mq.padding.bottom) + 16,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              layoutBuilder: (currentChild, previousChildren) {
                return Stack(
                  alignment: Alignment.bottomCenter,
                  fit: StackFit.passthrough,
                  children: <Widget>[
                    ...previousChildren,
                    if (currentChild != null) currentChild,
                  ],
                );
              },
              child: _buildBottomContent(context),
            ),
          ),
        ],
      ),
    );
  }

  /// Construye el contenido inferior dependiente del estado del escaneo
  Widget _buildBottomContent(BuildContext context) {
    if (_isSearching) {
      return _buildSearchingCard();
    }

    if (_foundProduct != null) {
      return _buildProductFoundCard(context, _foundProduct!);
    }

    if (_seedProduct != null) {
      return _buildSeedProductFoundCard(context, _seedProduct!, _scannedBarcode ?? '');
    }

    if (_notFound) {
      return _buildNotFoundCard(context, _scannedBarcode ?? '');
    }

    if (_errorMessage != null) {
      return _buildErrorCard(_errorMessage!);
    }

    // Estado inicial: Instrucción + Input Manual
    return _buildManualInputCard();
  }

  // ── Tarjeta: Buscando en catálogo ─────────────────────────────────────────

  Widget _buildSearchingCard() {
    return Container(
      key: const ValueKey('searching'),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.skyBlue.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.skyBlue),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              'Consultando código $_scannedBarcode en catálogo…',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Tarjeta: Producto Encontrado en Inventario Registrado ──────────────────

  Widget _buildProductFoundCard(BuildContext context, Product product) {
    return Container(
      key: ValueKey('found_${product.id}'),
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.emerald.withValues(alpha: 0.6), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Badge de estado registrado
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.emerald.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.emerald.withValues(alpha: 0.4)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_circle_rounded, size: 14, color: AppColors.emerald),
                    SizedBox(width: 5),
                    Text(
                      'EN TU INVENTARIO',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: AppColors.emerald,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              // SKU
              Text(
                product.sku,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.onSurfaceMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Nombre del producto
          Text(
            product.name,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          // Precio y Existencias
          Row(
            children: [
              // Precio en MXN
              Text(
                '\$${product.priceMxn.toStringAsFixed(2)} MXN',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppColors.emerald,
                ),
              ),
              const SizedBox(width: 16),
              // Stock disponible
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${product.availableStock} pzs disponibles',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.onSurfaceMuted,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          // Botones de Acción
          Row(
            children: [
              // Botón: Ver Ficha
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.emerald,
                    foregroundColor: AppColors.darkSlate,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () {
                    Navigator.of(context).pop();
                    context.push(AppRoutes.productDetailPath(product.id));
                  },
                  icon: const Icon(Icons.visibility_rounded, size: 18),
                  label: const Text('Ver Ficha', style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(width: 10),
              // Botón: Filtrar en Lista
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.onSurface,
                    side: const BorderSide(color: AppColors.border),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () {
                    Navigator.of(context).pop(product.barcode ?? product.name);
                  },
                  icon: const Icon(Icons.filter_list_rounded, size: 18),
                  label: const Text('Filtrar'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Botón Escanear Otro
          Center(
            child: TextButton(
              onPressed: _resetScan,
              child: const Text(
                'Escanear otro código',
                style: TextStyle(color: AppColors.onSurfaceMuted, fontSize: 13),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Tarjeta: Producto Encontrado en Catálogo Semilla GS1 México ───────────

  Widget _buildSeedProductFoundCard(
      BuildContext context, EanLookupResult seed, String barcode) {
    return Container(
      key: ValueKey('seed_$barcode'),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.skyBlue.withValues(alpha: 0.6), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Badge GS1 México
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.skyBlue.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.skyBlue.withValues(alpha: 0.4)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.auto_awesome_rounded, size: 14, color: AppColors.skyBlue),
                    SizedBox(width: 5),
                    Text(
                      'CATÁLOGO SEMILLA GS1 MÉXICO',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: AppColors.skyBlue,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            'No está registrado en tu inventario, pero identificamos este producto:',
            style: TextStyle(fontSize: 12, color: AppColors.onSurfaceMuted),
          ),
          const SizedBox(height: 8),
          // Nombre del producto en catálogo maestro
          Text(
            seed.name,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: AppColors.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          // Categoría y precio sugerido
          Row(
            children: [
              if (seed.category.isNotEmpty) ...[
                Text(
                  seed.category,
                  style: const TextStyle(fontSize: 13, color: AppColors.onSurfaceMuted),
                ),
                const Text(' · ', style: TextStyle(color: AppColors.onSurfaceMuted)),
              ],
              Text(
                'Sugerido: \$${(seed.suggestedPriceMxn ?? 0.0).toStringAsFixed(2)} MXN',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.skyBlue,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          // Botón Registrar en Inventario
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.skyBlue,
              foregroundColor: AppColors.darkSlate,
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () async {
              Navigator.of(context).pop();
              await showAddProductModal(
                context,
                initialBarcode: barcode,
                initialName: seed.name,
                initialPrice: seed.suggestedPriceMxn,
                initialCategory: seed.category,
              );
            },
            icon: const Icon(Icons.add_circle_outline_rounded, size: 18),
            label: const Text(
              'Registrar en mi Inventario',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
            ),
          ),
          const SizedBox(height: 6),
          Center(
            child: TextButton(
              onPressed: _resetScan,
              child: const Text(
                'Escanear otro código',
                style: TextStyle(color: AppColors.onSurfaceMuted, fontSize: 13),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Tarjeta: No Encontrado ────────────────────────────────────────────────

  Widget _buildNotFoundCard(BuildContext context, String barcode) {
    return Container(
      key: ValueKey('not_found_$barcode'),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.6), width: 1.5),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.info_outline_rounded, size: 14, color: AppColors.warning),
                    SizedBox(width: 5),
                    Text(
                      'PRODUCTO NO REGISTRADO',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: AppColors.warning,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'El código $barcode no existe en tu inventario ni en el catálogo semilla.',
            style: const TextStyle(fontSize: 14, color: AppColors.onSurface),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.emerald,
              foregroundColor: AppColors.darkSlate,
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () async {
              Navigator.of(context).pop();
              await showAddProductModal(
                context,
                initialBarcode: barcode,
              );
            },
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text(
              'Registrar Nuevo Producto',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
            ),
          ),
          const SizedBox(height: 6),
          Center(
            child: TextButton(
              onPressed: _resetScan,
              child: const Text(
                'Escanear otro código',
                style: TextStyle(color: AppColors.onSurfaceMuted, fontSize: 13),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Tarjeta: Error de Red ─────────────────────────────────────────────────

  Widget _buildErrorCard(String error) {
    return Container(
      key: const ValueKey('error'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.error),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(error, style: const TextStyle(color: AppColors.error, fontSize: 13)),
          const SizedBox(height: 10),
          TextButton(
            onPressed: _resetScan,
            child: const Text('Reintentar', style: TextStyle(color: AppColors.skyBlue)),
          ),
        ],
      ),
    );
  }

  // ── Tarjeta Inicial: Input Manual ─────────────────────────────────────────

  Widget _buildManualInputCard() {
    return Container(
      key: const ValueKey('manual_input'),
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
          const Text(
            'Apunta al código de barras o ingrésalo manualmente:',
            style: TextStyle(fontSize: 12, color: AppColors.onSurfaceMuted),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _manualController,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: AppColors.onSurface, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Ej. 7501055300075',
                    hintStyle: const TextStyle(color: AppColors.onSurfaceMuted, fontSize: 13),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    filled: true,
                    fillColor: AppColors.surfaceVariant,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onSubmitted: _searchBarcode,
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(80, 44),
                  backgroundColor: AppColors.skyBlue,
                  foregroundColor: AppColors.darkSlate,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () => _searchBarcode(_manualController.text),
                child: const Text('Buscar', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Marco animado de escaneo
// ---------------------------------------------------------------------------

class _ScanFrame extends StatefulWidget {
  const _ScanFrame({required this.isSearching});
  final bool isSearching;

  @override
  State<_ScanFrame> createState() => _ScanFrameState();
}

class _ScanFrameState extends State<_ScanFrame> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulse = Tween<double>(begin: 0.9, end: 1.0).animate(
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
        size: const Size(260, 140),
        painter: _FramePainter(
          color: widget.isSearching ? AppColors.warning : AppColors.emerald,
        ),
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

    // Esquina superior-izquierda
    canvas.drawLine(Offset(r, 0), Offset(cornerLen, 0), paint);
    canvas.drawLine(Offset(0, r), Offset(0, cornerLen), paint);
    canvas.drawArc(Rect.fromLTWH(0, 0, r * 2, r * 2), 3.14, -1.57, false, paint);

    // Esquina superior-derecha
    canvas.drawLine(Offset(w - cornerLen, 0), Offset(w - r, 0), paint);
    canvas.drawLine(Offset(w, r), Offset(w, cornerLen), paint);
    canvas.drawArc(Rect.fromLTWH(w - r * 2, 0, r * 2, r * 2), 4.71, -1.57, false, paint);

    // Esquina inferior-izquierda
    canvas.drawLine(Offset(0, h - cornerLen), Offset(0, h - r), paint);
    canvas.drawLine(Offset(r, h), Offset(cornerLen, h), paint);
    canvas.drawArc(Rect.fromLTWH(0, h - r * 2, r * 2, r * 2), 1.57, -1.57, false, paint);

    // Esquina inferior-derecha
    canvas.drawLine(Offset(w, h - cornerLen), Offset(w, h - r), paint);
    canvas.drawLine(Offset(w - cornerLen, h), Offset(w - r, h), paint);
    canvas.drawArc(Rect.fromLTWH(w - r * 2, h - r * 2, r * 2, r * 2), 0, -1.57, false, paint);
  }

  @override
  bool shouldRepaint(_FramePainter old) => old.color != color;
}
