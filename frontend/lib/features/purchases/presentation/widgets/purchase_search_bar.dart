import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';

/// Barra de búsqueda fija sobre los chips de estado del tab "Compras" —
/// ajuste de QA de Eduardo: reemplaza el ícono de lupa expandible por una
/// barra persistente en este tab, igual patrón visual que
/// `InventorySearchBar` (píldora, fondo `surfaceVariant`, radio 28).
class PurchaseSearchBar extends StatefulWidget {
  const PurchaseSearchBar({
    super.key,
    required this.onChanged,
    this.hintText = 'Buscar por folio o proveedor...',
  });

  final ValueChanged<String> onChanged;
  final String hintText;

  @override
  State<PurchaseSearchBar> createState() => _PurchaseSearchBarState();
}

class _PurchaseSearchBarState extends State<PurchaseSearchBar> {
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
          const Icon(Icons.search_rounded, size: 20, color: AppColors.onSurfaceMuted),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _controller,
              onChanged: widget.onChanged,
              style: const TextStyle(color: AppColors.onSurface, fontSize: 14),
              decoration: InputDecoration(
                hintText: widget.hintText,
                hintStyle: const TextStyle(color: AppColors.onSurfaceMuted, fontSize: 14),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: _controller,
            builder: (_, value, __) {
              return Padding(
                padding: const EdgeInsets.only(right: 14),
                child: value.text.isEmpty
                    ? const SizedBox(width: 18)
                    : GestureDetector(
                        onTap: _clear,
                        child: const Icon(Icons.close_rounded, size: 18, color: AppColors.onSurfaceMuted),
                      ),
              );
            },
          ),
        ],
      ),
    );
  }
}
