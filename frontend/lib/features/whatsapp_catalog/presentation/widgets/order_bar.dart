import 'package:flutter/material.dart';

import '../catalog_theme.dart';

/// Barra inferior del pedido — Tarea 13.2.2.
///
/// Aparece con el primer "+" y crece con cada toque: conteo y total a la
/// izquierda, la acción a la derecha. Es la única superficie esmeralda de la
/// pantalla, así que el ojo sabe a dónde ir cuando termina de elegir.
class OrderBar extends StatelessWidget {
  const OrderBar({
    super.key,
    required this.itemCount,
    required this.subtotalMxn,
    required this.onOpen,
  });

  final int itemCount;
  final double subtotalMxn;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final visible = itemCount > 0;
    return AnimatedSlide(
      offset: visible ? Offset.zero : const Offset(0, 1.2),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: const Duration(milliseconds: 180),
        child: IgnorePointer(
          ignoring: !visible,
          // Respaldo blanco a todo lo ancho: lo que la barra tapa queda
          // tapado limpio, sin un "+" asomando por la esquina de la píldora.
          child: Container(
            decoration: const BoxDecoration(
              color: CatalogColors.ground,
              border: Border(top: BorderSide(color: CatalogColors.line)),
            ),
            child: SafeArea(
              top: false,
              minimum: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Semantics(
                button: true,
                label:
                    '$itemCount artículos, ${mxn(subtotalMxn)}. Ver mi pedido',
                child: Material(
                  key: const Key('orderBar'),
                  color: CatalogColors.accent,
                  borderRadius: BorderRadius.circular(16),
                  elevation: 3,
                  shadowColor: CatalogColors.ink.withValues(alpha: 0.18),
                  child: InkWell(
                    onTap: onOpen,
                    borderRadius: BorderRadius.circular(16),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 14, 12),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 9, vertical: 3),
                            decoration: BoxDecoration(
                              color:
                                  CatalogColors.onAccent.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '$itemCount',
                              style: const TextStyle(
                                color: CatalogColors.onAccent,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                fontFeatures: CatalogTheme.tabular,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          // El conteo ya lo dice el badge; el total es lo que
                          // el cliente quiere ver. A 390 px no cabe más sin
                          // achicar la acción.
                          Expanded(
                            child: Text(
                              mxn(subtotalMxn),
                              key: const Key('orderBarTotal'),
                              style: const TextStyle(
                                color: CatalogColors.onAccent,
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                fontFeatures: CatalogTheme.tabular,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Text(
                            'Ver mi pedido',
                            style: TextStyle(
                              color: CatalogColors.onAccent,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(width: 2),
                          const Icon(Icons.chevron_right_rounded,
                              color: CatalogColors.onAccent),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
