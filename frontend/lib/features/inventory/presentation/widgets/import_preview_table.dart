import 'package:flutter/material.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../data/import_repository.dart';

/// Tabla de previsualización de las primeras 5 filas del archivo importado.
///
/// Muestra un `DataTable` con scroll horizontal para archivos con muchas
/// columnas. Las cabeceras son los identificadores de columna (A, B, C…).
/// Usado en el Paso 2 del ImportScreen.
class ImportPreviewTable extends StatelessWidget {
  const ImportPreviewTable({
    super.key,
    required this.preview,
  });

  final FilePreview preview;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Info del archivo
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.emerald.withValues(alpha: 0.08),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            border: Border.all(
              color: AppColors.emerald.withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.insert_drive_file_outlined,
                size: 16,
                color: AppColors.emerald,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  preview.fileName,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.emerald,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.emerald.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${preview.totalRows} filas',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.emerald,
                  ),
                ),
              ),
            ],
          ),
        ),

        // Tabla de datos con scroll horizontal
        Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius:
                const BorderRadius.vertical(bottom: Radius.circular(12)),
            border: Border.all(color: AppColors.border),
          ),
          child: ClipRRect(
            borderRadius:
                const BorderRadius.vertical(bottom: Radius.circular(12)),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowColor: WidgetStateProperty.all(AppColors.surfaceVariant),
                dataRowColor: WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.selected)) {
                    return AppColors.emerald.withValues(alpha: 0.08);
                  }
                  return AppColors.surface;
                }),
                headingTextStyle: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.onSurfaceMuted,
                  letterSpacing: 0.5,
                ),
                dataTextStyle: const TextStyle(
                  fontSize: 12,
                  color: AppColors.onSurface,
                ),
                columnSpacing: 24,
                horizontalMargin: 16,
                dividerThickness: 1,
                columns: preview.headers
                    .map(
                      (h) => DataColumn(
                        label: Text('Col. $h'),
                      ),
                    )
                    .toList(),
                rows: preview.previewRows.asMap().entries.map((entry) {
                  final isEven = entry.key % 2 == 0;
                  return DataRow(
                    color: WidgetStateProperty.all(
                      isEven
                          ? AppColors.surface
                          : AppColors.surfaceVariant.withValues(alpha: 0.4),
                    ),
                    cells: entry.value
                        .map(
                          (cell) => DataCell(
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 140),
                              child: Text(
                                cell,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  );
                }).toList(),
              ),
            ),
          ),
        ),

        const SizedBox(height: 8),
        Text(
          'Mostrando 5 de ${preview.totalRows} filas',
          style: TextStyle(
            fontSize: 11,
            color: AppColors.onSurfaceMuted.withValues(alpha: 0.7),
          ),
        ),
      ],
    );
  }
}
