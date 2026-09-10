import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/theme/app_colors.dart';
import '../cart_provider.dart';

/// Modal para agregar un producto al vuelo (sin registro previo).
///
/// Campos: Nombre*, Precio MXN*, Cantidad.
/// Estado 100% local — mismo patrón que AddProductModal.
///
/// Trazabilidad: Constitución Art. VII (7.3 Lazy Loading Just-in-Time)
///              Doc. Maestro RF-09, Sección 2.4 · HU-11 / CU-12
class OnTheFlyModal extends ConsumerStatefulWidget {
  const OnTheFlyModal({super.key});

  @override
  ConsumerState<OnTheFlyModal> createState() => _OnTheFlyModalState();
}

class _OnTheFlyModalState extends ConsumerState<OnTheFlyModal> {
  late final TextEditingController _nameCon;
  late final TextEditingController _priceCon;
  late final TextEditingController _qtyCon;
  late final FocusNode _nameFocus;
  late final FocusNode _priceFocus;

  bool get _isValid {
    final name = _nameCon.text.trim();
    final price = double.tryParse(_priceCon.text.replaceAll(',', '.')) ?? 0;
    return name.length >= 2 && price > 0;
  }

  @override
  void initState() {
    super.initState();
    _nameCon = TextEditingController();
    _priceCon = TextEditingController();
    _qtyCon = TextEditingController(text: '1');
    _nameFocus = FocusNode();
    _priceFocus = FocusNode();

    for (final c in [_nameCon, _priceCon]) {
      c.addListener(() => setState(() {}));
    }

    // Auto-foco en nombre al abrir
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _nameFocus.requestFocus(),
    );
  }

  @override
  void dispose() {
    _nameCon.dispose();
    _priceCon.dispose();
    _qtyCon.dispose();
    _nameFocus.dispose();
    _priceFocus.dispose();
    super.dispose();
  }

  void _confirm() {
    if (!_isValid) return;
    final price = double.tryParse(_priceCon.text.replaceAll(',', '.')) ?? 0;
    final qty = int.tryParse(_qtyCon.text) ?? 1;

    ref.read(cartProvider.notifier).addOnTheFly(
          name: _nameCon.text.trim(),
          priceMxn: price,
          qty: qty.clamp(1, 999),
        );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),

            // Header
            Row(
              children: [
                const Text(
                  'Producto al vuelo',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: AppColors.onSurface,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close_rounded,
                      size: 20, color: AppColors.onSurfaceMuted),
                  onPressed: () => Navigator.of(context).pop(),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            const SizedBox(height: 18),

            // Campo nombre
            TextFormField(
              controller: _nameCon,
              focusNode: _nameFocus,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.next,
              onFieldSubmitted: (_) => _priceFocus.requestFocus(),
              decoration: const InputDecoration(
                labelText: 'Nombre del producto *',
                hintText: 'Ej: Frituras caseras',
              ),
            ),
            const SizedBox(height: 12),

            // Precio + Cantidad en fila
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Precio
                Expanded(
                  flex: 3,
                  child: TextFormField(
                    controller: _priceCon,
                    focusNode: _priceFocus,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Precio (MXN) *',
                      prefixText: '\$ ',
                      prefixStyle: TextStyle(
                        color: AppColors.emerald,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                // Cantidad
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    controller: _qtyCon,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                    ],
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _confirm(),
                    decoration: const InputDecoration(
                      labelText: 'Cantidad',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Botón agregar
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _isValid ? _confirm : null,
                child: const Text(
                  'Agregar al carrito',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Función helper para mostrar el modal.
Future<void> showOnTheFlyModal(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const OnTheFlyModal(),
  );
}
