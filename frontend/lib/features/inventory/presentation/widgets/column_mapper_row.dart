import 'package:flutter/material.dart';
import '../../../../../core/theme/app_colors.dart';

/// Fila de mapeo de columna: muestra el nombre del campo obligatorio a la
/// izquierda y un dropdown para seleccionar la columna del archivo a la derecha.
///
/// Usado en el Paso 3 del ImportScreen (Mapeo de columnas).
class ColumnMapperRow extends StatelessWidget {
  const ColumnMapperRow({
    super.key,
    required this.fieldLabel,
    required this.fieldIcon,
    required this.isRequired,
    required this.columns,
    required this.selectedColumn,
    required this.onChanged,
  });

  /// Nombre del campo destino (ej. "Nombre", "Precio", "Stock").
  final String fieldLabel;

  /// Ícono representativo del campo.
  final IconData fieldIcon;

  /// Si es true muestra un asterisco rojo.
  final bool isRequired;

  /// Lista de cabeceras/columnas disponibles del archivo (ej. ['A','B','C','D']).
  final List<String> columns;

  /// Columna actualmente seleccionada, null si no se ha elegido.
  final String? selectedColumn;

  /// Callback cuando el usuario selecciona una columna.
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: selectedColumn != null ? AppColors.emerald.withValues(alpha: 0.5) : AppColors.border,
        ),
      ),
      child: Row(
        children: [
          // Ícono del campo
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(fieldIcon, size: 18, color: AppColors.onSurfaceMuted),
          ),
          const SizedBox(width: 12),

          // Label del campo
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RichText(
                  text: TextSpan(
                    children: [
                      TextSpan(
                        text: fieldLabel,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.onSurface,
                        ),
                      ),
                      if (isRequired)
                        const TextSpan(
                          text: ' *',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppColors.error,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  isRequired ? 'Campo obligatorio' : 'Campo opcional',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.onSurfaceMuted.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),

          // Dropdown de columna
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: selectedColumn != null ? AppColors.emerald : AppColors.border,
              ),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: selectedColumn,
                hint: const Text(
                  'Columna',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.onSurfaceMuted,
                  ),
                ),
                dropdownColor: AppColors.surface,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.onSurface,
                ),
                icon: const Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 18,
                  color: AppColors.onSurfaceMuted,
                ),
                items: [
                  const DropdownMenuItem<String>(
                    value: null,
                    child: Text(
                      '—',
                      style: TextStyle(color: AppColors.onSurfaceMuted),
                    ),
                  ),
                  ...columns.map(
                    (col) => DropdownMenuItem<String>(
                      value: col,
                      child: Text('Col. $col'),
                    ),
                  ),
                ],
                onChanged: onChanged,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
