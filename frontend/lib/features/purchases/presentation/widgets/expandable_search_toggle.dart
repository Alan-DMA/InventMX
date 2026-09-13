import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';

/// Ícono de lupa que se expande a un campo de texto inline — colocado junto
/// al botón de filtros (▤) en las 3 tabs del hub de Compras.
///
/// Decisión de diseño (aprobada por Eduardo, Tarea 11.2): en vez de una
/// barra de búsqueda persistente (como `InventorySearchBar`), un ícono
/// expandible ahorra espacio vertical cuando ya conviven chips de estado +
/// botón de filtros en el mismo renglón.
class ExpandableSearchToggle extends StatefulWidget {
  const ExpandableSearchToggle({
    super.key,
    required this.onChanged,
    required this.hintText,
  });

  final ValueChanged<String> onChanged;
  final String hintText;

  @override
  State<ExpandableSearchToggle> createState() =>
      _ExpandableSearchToggleState();
}

class _ExpandableSearchToggleState extends State<ExpandableSearchToggle> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() {
      if (!_focusNode.hasFocus && _controller.text.isEmpty) {
        setState(() => _expanded = false);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _open() {
    setState(() => _expanded = true);
    _focusNode.requestFocus();
  }

  void _close() {
    _controller.clear();
    widget.onChanged('');
    setState(() => _expanded = false);
    _focusNode.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    if (!_expanded) {
      return IconButton(
        onPressed: _open,
        tooltip: 'Buscar',
        icon: const Icon(Icons.search_rounded, color: AppColors.onSurfaceMuted),
      );
    }

    return SizedBox(
      width: 200,
      height: 36,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.borderFocus),
        ),
        child: Row(
          children: [
            const Icon(Icons.search_rounded, size: 18, color: AppColors.onSurfaceMuted),
            const SizedBox(width: 6),
            Expanded(
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                onChanged: widget.onChanged,
                style: const TextStyle(color: AppColors.onSurface, fontSize: 13),
                decoration: InputDecoration(
                  hintText: widget.hintText,
                  hintStyle: const TextStyle(
                    color: AppColors.onSurfaceMuted,
                    fontSize: 13,
                  ),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
            GestureDetector(
              onTap: _close,
              child: const Icon(
                Icons.close_rounded,
                size: 16,
                color: AppColors.onSurfaceMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
