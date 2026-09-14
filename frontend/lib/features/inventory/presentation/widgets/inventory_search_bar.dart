import 'package:flutter/material.dart';
import '../../../../../../core/theme/app_colors.dart';

/// Barra de búsqueda píldora con ícono de cámara y escaneo de código de barras.
///
/// - Fondo: AppColors.surfaceVariant (igual que los inputs del design system)
/// - Border radius: 28 (píldora completa)
/// - Ícono cámara: abre el escáner de códigos de barras en tiempo real
class InventorySearchBar extends StatefulWidget {
  const InventorySearchBar({
    super.key,
    required this.onChanged,
    this.onScanPressed,
    this.controller,
    this.hintText = 'Buscar producto o escanear...',
  });

  final ValueChanged<String> onChanged;
  final VoidCallback? onScanPressed;
  final TextEditingController? controller;
  final String hintText;

  @override
  State<InventorySearchBar> createState() => _InventorySearchBarState();
}

class _InventorySearchBarState extends State<InventorySearchBar> {
  late final TextEditingController _effectiveController;

  @override
  void initState() {
    super.initState();
    _effectiveController = widget.controller ?? TextEditingController();
  }

  @override
  void dispose() {
    if (widget.controller == null) {
      _effectiveController.dispose();
    }
    super.dispose();
  }

  void _clear() {
    _effectiveController.clear();
    widget.onChanged('');
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 46,
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          const SizedBox(width: 14),
          const Icon(
            Icons.search_rounded,
            size: 20,
            color: AppColors.onSurfaceMuted,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _effectiveController,
              onChanged: widget.onChanged,
              style: const TextStyle(
                color: AppColors.onSurface,
                fontSize: 14,
              ),
              decoration: InputDecoration(
                hintText: widget.hintText,
                hintStyle: const TextStyle(
                  color: AppColors.onSurfaceMuted,
                  fontSize: 14,
                ),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          // Botón limpiar — visible solo cuando hay texto
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: _effectiveController,
            builder: (_, value, __) {
              if (value.text.isEmpty) return const SizedBox.shrink();
              return GestureDetector(
                onTap: _clear,
                child: const Icon(
                  Icons.close_rounded,
                  size: 18,
                  color: AppColors.onSurfaceMuted,
                ),
              );
            },
          ),
          const SizedBox(width: 8),
          // Ícono cámara — botón interactivo de escáner de código de barras
          GestureDetector(
            onTap: widget.onScanPressed,
            behavior: HitTestBehavior.opaque,
            child: Tooltip(
              message: 'Escanear código de barras',
              child: Padding(
                padding: const EdgeInsets.only(right: 14),
                child: Icon(
                  Icons.photo_camera_rounded,
                  size: 20,
                  color: widget.onScanPressed != null
                      ? AppColors.skyBlue
                      : AppColors.onSurfaceMuted.withValues(alpha: 0.6),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
