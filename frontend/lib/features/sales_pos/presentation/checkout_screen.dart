import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import '../../analytics/presentation/employee_performance_screen.dart';
import '../domain/cart_item.dart';
import 'cart_provider.dart';
import 'sale_receipt_screen.dart';
import 'widgets/cart_item_tile.dart';
import 'widgets/cart_totals_bar.dart';
import 'widgets/on_the_fly_modal.dart';
import 'widgets/payment_modal.dart';
import 'widgets/product_search_results.dart';

/// Pantalla principal del Punto de Venta (POS) — Tarea 6.2
///
/// Layout fiel a la referencia visual:
///   AppBar: "Ventas" + folio VTA-XXXXXX
///   Barra de búsqueda píldora con ícono cámara
///   Panel desplegable de resultados (visible al escribir)
///   Lista de ítems del carrito con controles +/−
///   Botón "+ Agregar producto al vuelo"
///   Barra fija inferior: SUBTOTAL + botón Cobrar
///
/// Trazabilidad: Constitución Art. I (1.2.8 Rapidez), Art. VII (7.3)
///              Doc. Maestro RF-09, SR-04 · HU-11 / CU-12
class CheckoutScreen extends ConsumerStatefulWidget {
  const CheckoutScreen({super.key});

  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  bool _showResults = false;

  // Folio de sesión de venta — se renueva con cada checkout exitoso
  String _sessionFolio = _generateFolio();

  static String _generateFolio() {
    final n = DateTime.now().millisecondsSinceEpoch % 100000;
    return 'VTA-${n.toString().padLeft(6, '0')}';
  }

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _searchFocus.addListener(() {
      if (!_searchFocus.hasFocus) {
        setState(() => _showResults = false);
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final q = _searchController.text;
    ref.read(cartProvider.notifier).setSearchQuery(q);
    setState(() => _showResults = q.trim().isNotEmpty);
  }

  void _clearSearch() {
    _searchController.clear();
    ref.read(cartProvider.notifier).clearSearch();
    setState(() => _showResults = false);
    _searchFocus.unfocus();
  }

  Future<void> _onCobrar() async {
    final cart = ref.read(cartProvider);
    if (cart.isEmpty) return;

    // Tarea 7.2 — Modal de cobro con métodos de pago mixtos.
    final payments = await showPaymentModal(context, totalMxn: cart.totalMxn);
    if (payments == null) return; // Cancelado — el carrito no se modifica.
    if (!mounted) return;

    try {
      final result =
          await ref.read(cartProvider.notifier).checkout(payments: payments);
      if (!mounted) return;

      setState(() => _sessionFolio = _generateFolio());

      // Tarea 8.2 — el ticket de venta reemplaza el aviso puntual: muestra
      // el comprobante completo con opción de compartir por WhatsApp.
      // Usa el rootNavigator para que la pantalla cubra también la barra de
      // navegación inferior del ShellRoute (si no, queda visible detrás).
      await Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute(builder: (_) => SaleReceiptScreen(result: result)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al procesar el cobro: $e'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _confirmClear() async {
    final cart = ref.read(cartProvider);
    if (cart.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Limpiar carrito',
          style: TextStyle(
            color: AppColors.onSurface,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Text(
          '¿Eliminar los ${cart.lineCount} productos del carrito?',
          style: const TextStyle(color: AppColors.onSurfaceMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar',
                style: TextStyle(color: AppColors.onSurfaceMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child:
                const Text('Limpiar', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      ref.read(cartProvider.notifier).clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider);

    return GestureDetector(
      onTap: () {
        _searchFocus.unfocus();
        setState(() => _showResults = false);
      },
      child: Scaffold(
        backgroundColor: AppColors.darkSlate,
        // Evita que el Scaffold redimensione el body cuando aparece el teclado.
        // El body maneja su propio padding con MediaQuery.viewInsets.
        resizeToAvoidBottomInset: false,
        appBar: _buildAppBar(cart),
        body: Column(
          children: [
            // ── Barra de búsqueda ────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: _SearchBar(
                controller: _searchController,
                focusNode: _searchFocus,
                onClear: _clearSearch,
              ),
            ),

            // ── Resultados desplegables scrolleables ─────────────────────
            if (_showResults)
              Flexible(
                child: ProductSearchResults(
                  query: _searchController.text,
                  onProductAdded: _clearSearch,
                ),
              ),

            // ── Contenido principal (lista o empty state) ────────────────
            if (!_showResults)
              Expanded(
                child: cart.isEmpty
                    ? const _EmptyCartState()
                    : _CartList(items: cart.items),
              ),

            // ── Barra inferior ───────────────────────────────────────────
            CartTotalsBar(
              totalMxn: cart.totalMxn,
              isEnabled: !cart.isEmpty,
              isProcessing: cart.isProcessing,
              onCobrar: _onCobrar,
            ),

            // Padding para el teclado — evita que la barra inferior quede tapada
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              height: MediaQuery.of(context).viewInsets.bottom > 0
                  ? MediaQuery.of(context).viewInsets.bottom
                  : 0,
            ),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(cartState) {
    return AppBar(
      backgroundColor: AppColors.darkSlate,
      elevation: 0,
      scrolledUnderElevation: 0,
      automaticallyImplyLeading: false,
      title: const Text(
        'Ventas',
        style: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w800,
          color: AppColors.onSurface,
        ),
      ),
      actions: [
        // Folio de sesión
        Center(
          child: Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Text(
              _sessionFolio,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.onSurfaceMuted,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
        // Botón "Mis comisiones" — Tarea 8.2.3
        IconButton(
          tooltip: 'Mis comisiones',
          icon: const Icon(
            Icons.military_tech_rounded,
            size: 22,
            color: AppColors.skyBlue,
          ),
          onPressed: () => Navigator.of(context, rootNavigator: true).push(
            MaterialPageRoute(builder: (_) => const EmployeePerformanceScreen()),
          ),
        ),
        // Botón limpiar carrito
        IconButton(
          tooltip: 'Limpiar carrito',
          icon: Icon(
            Icons.delete_outline_rounded,
            size: 22,
            color: cartState.isEmpty
                ? AppColors.onSurfaceMuted.withValues(alpha: 0.3)
                : AppColors.onSurfaceMuted,
          ),
          onPressed: cartState.isEmpty ? null : _confirmClear,
        ),
        const SizedBox(width: 4),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Barra de búsqueda
// ---------------------------------------------------------------------------

class _SearchBar extends StatelessWidget {
  const _SearchBar({
    required this.controller,
    required this.focusNode,
    required this.onClear,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 46,
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(23),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          const SizedBox(width: 14),
          const Icon(Icons.search_rounded,
              size: 20, color: AppColors.onSurfaceMuted),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.onSurface,
              ),
              decoration: const InputDecoration(
                hintText: 'Buscar producto o escanear...',
                hintStyle: TextStyle(
                  fontSize: 14,
                  color: AppColors.onSurfaceMuted,
                ),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
              textInputAction: TextInputAction.search,
            ),
          ),
          // Botón limpiar o cámara
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (_, value, __) {
              if (value.text.isNotEmpty) {
                return IconButton(
                  icon: const Icon(Icons.close_rounded,
                      size: 18, color: AppColors.onSurfaceMuted),
                  onPressed: onClear,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 40,
                    minHeight: 40,
                  ),
                );
              }
              return IconButton(
                icon: const Icon(Icons.photo_camera_outlined,
                    size: 20, color: AppColors.onSurfaceMuted),
                tooltip: 'Escanear código',
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content:
                          Text('Escáner en POS — disponible en Tarea 12.2'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(
                  minWidth: 40,
                  minHeight: 40,
                ),
              );
            },
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Lista del carrito con botón "al vuelo"
// ---------------------------------------------------------------------------

class _CartList extends StatelessWidget {
  const _CartList({required this.items});

  final List<CartItem> items;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      children: [
        ...items.map<Widget>((item) => CartItemTile(item: item)),

        const SizedBox(height: 8),

        // Botón "al vuelo" centrado
        Center(
          child: GestureDetector(
            onTap: () => showOnTheFlyModal(context),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                border: Border.all(
                  color: AppColors.skyBlue.withValues(alpha: 0.5),
                  width: 1.5,
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.add_circle_outline_rounded,
                    size: 18,
                    color: AppColors.skyBlue,
                  ),
                  SizedBox(width: 8),
                  Text(
                    '+ Agregar producto al vuelo',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: AppColors.skyBlue,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Empty state
// ---------------------------------------------------------------------------

class _EmptyCartState extends StatelessWidget {
  const _EmptyCartState();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      child: ConstrainedBox(
        // Ocupa el espacio disponible sin desbordarse cuando aparece el teclado
        constraints: BoxConstraints(
          minHeight: MediaQuery.of(context).size.height * 0.38,
        ),
        child: IntrinsicHeight(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: 24),
              Icon(
                Icons.shopping_cart_outlined,
                size: 64,
                color: AppColors.onSurfaceMuted.withValues(alpha: 0.25),
              ),
              const SizedBox(height: 16),
              const Text(
                'Carrito vacío',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: AppColors.onSurfaceMuted,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Busca un producto o escanea\nun código de barras para empezar',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.onSurfaceMuted,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),
              // Botón "al vuelo"
              GestureDetector(
                onTap: () => showOnTheFlyModal(context),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: AppColors.skyBlue.withValues(alpha: 0.5),
                      width: 1.5,
                    ),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add_circle_outline_rounded,
                          size: 18, color: AppColors.skyBlue),
                      SizedBox(width: 8),
                      Text(
                        '+ Agregar producto al vuelo',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: AppColors.skyBlue,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
