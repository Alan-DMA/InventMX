import 'package:flutter/material.dart';
import '../../../../../../core/theme/app_colors.dart';

/// Barra de búsqueda píldora con ícono de cámara.
///
/// - Fondo: AppColors.surfaceVariant (igual que los inputs del design system)
/// - Border radius: 28 (píldora completa)
/// - Ícono cámara: placeholder visual — se conecta en Tarea 5.2
class InventorySearchBar extends StatefulWidget {
  const InventorySearchBar({
    super.key,
    required this.onChanged,
    this.hintText = 'Buscar producto o escanear...',
  });

  final ValueChanged<String> onChanged;
  final String hintText;

  @override
  State<InventorySearchBar> createState() => _InventorySearchBarState();
}

class _InventorySearchBarState extends State<InventorySearchBar> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _clear() {
    _controller.clear();
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
              controller: _controller,
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
            valueListenable: _controller,
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
          // Ícono cámara — placeholder Tarea 5.2
          Tooltip(
            message: 'Escanear (disponible en Tarea 5.2)',
            child: Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Icon(
                Icons.photo_camera_rounded,
                size: 20,
                color: AppColors.onSurfaceMuted.withValues(alpha: 0.6),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
