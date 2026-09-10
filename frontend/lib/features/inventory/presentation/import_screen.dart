import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import '../data/import_repository.dart';
import 'widgets/column_mapper_row.dart';
import 'widgets/import_preview_table.dart';

/// Wizard de importación de productos desde archivo Excel/CSV.
///
/// Flujo de 4 pasos:
///   Paso 0 — Selección de archivo
///   Paso 1 — Previsualización de las primeras 5 filas
///   Paso 2 — Mapeo de columnas (Nombre*, Precio*, Stock)
///   Paso 3 — Resultado de la importación
///
/// Trazabilidad: Constitución Art. VII (7.5 Catálogo Semilla)
///              Doc. Maestro RF-01 (Importación con Mapeo Visual Flexible)
///              HU-09 / CU-09
class ImportScreen extends ConsumerStatefulWidget {
  const ImportScreen({super.key});

  @override
  ConsumerState<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends ConsumerState<ImportScreen> {
  // ── Estado del wizard ────────────────────────────────────────────────────
  int _step = 0;
  bool _isLoading = false;
  String? _errorMessage;

  // Paso 0 — archivo seleccionado
  String? _filePath;

  // Paso 1 — previsualización
  FilePreview? _preview;

  // Paso 2 — mapeo de columnas
  String? _colName;
  String? _colPrice;
  String? _colStock;

  // Paso 3 — resultado
  ImportResult? _result;

  // ── Validaciones por paso ────────────────────────────────────────────────

  bool get _step0Valid => _filePath != null;

  bool get _step2Valid => _colName != null && _colPrice != null;

  // ── Handlers ─────────────────────────────────────────────────────────────

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'xls', 'csv'],
      allowMultiple: false,
    );
    if (result != null && result.files.isNotEmpty) {
      setState(() {
        _filePath = result.files.first.path ?? result.files.first.name;
        _errorMessage = null;
      });
    }
  }

  Future<void> _loadPreview() async {
    if (_filePath == null) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final preview =
          await ref.read(importRepositoryProvider).previewFile(_filePath!);
      setState(() {
        _preview = preview;
        // Intenta auto-mapear columnas si solo hay 3 o 4
        if (preview.headers.length >= 3) {
          _colName = preview.headers[0];
          _colPrice = preview.headers[2];
          _colStock = preview.headers.length >= 4 ? preview.headers[3] : null;
        }
        _step = 1;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage =
            'No se pudo leer el archivo. Verifica que sea un Excel o CSV válido.';
      });
    }
  }

  Future<void> _runImport() async {
    if (!_step2Valid || _filePath == null) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final result = await ref.read(importRepositoryProvider).importFile(
            filePath: _filePath!,
            colName: _colName!,
            colPrice: _colPrice!,
            colStock: _colStock ?? '',
          );
      setState(() {
        _result = result;
        _step = 3;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage =
            'Error al importar. Verifica tu conexión e intenta de nuevo.';
      });
    }
  }

  void _reset() {
    setState(() {
      _step = 0;
      _filePath = null;
      _preview = null;
      _colName = null;
      _colPrice = null;
      _colStock = null;
      _result = null;
      _errorMessage = null;
    });
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkSlate,
      appBar: AppBar(
        backgroundColor: AppColors.darkSlate,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              size: 20, color: AppColors.onSurface),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Importar productos',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppColors.onSurface,
          ),
        ),
        bottom: _step < 3
            ? PreferredSize(
                preferredSize: const Size.fromHeight(4),
                child: _StepProgressBar(step: _step),
              )
            : null,
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                transitionBuilder: (child, anim) => FadeTransition(
                  opacity: anim,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0.04, 0),
                      end: Offset.zero,
                    ).animate(anim),
                    child: child,
                  ),
                ),
                child: KeyedSubtree(
                  key: ValueKey(_step),
                  child: _buildStep(),
                ),
              ),
            ),
          ),

          // Error banner
          if (_errorMessage != null) _ErrorBanner(message: _errorMessage!),

          // Barra de acciones inferior
          if (_step < 3) _buildActionBar(),
        ],
      ),
    );
  }

  Widget _buildStep() {
    switch (_step) {
      case 0:
        return _Step0FileSelect(
          filePath: _filePath,
          onPickFile: _pickFile,
          isLoading: _isLoading,
        );
      case 1:
        return _Step1Preview(preview: _preview);
      case 2:
        return _Step2Mapping(
          preview: _preview!,
          colName: _colName,
          colPrice: _colPrice,
          colStock: _colStock,
          onNameChanged: (v) => setState(() => _colName = v),
          onPriceChanged: (v) => setState(() => _colPrice = v),
          onStockChanged: (v) => setState(() => _colStock = v),
        );
      case 3:
        return _Step3Result(
          result: _result!,
          onImportMore: _reset,
          onClose: () => Navigator.of(context).pop(),
        );
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildActionBar() {
    final bool canAdvance = switch (_step) {
      0 => _step0Valid && !_isLoading,
      1 => true,
      2 => _step2Valid && !_isLoading,
      _ => false,
    };

    final String nextLabel = switch (_step) {
      0 => 'Previsualizar',
      1 => 'Configurar mapeo',
      2 => 'Importar ${_preview?.totalRows ?? ''} productos',
      _ => '',
    };

    return Container(
      padding: EdgeInsets.fromLTRB(
          16, 12, 16, MediaQuery.of(context).padding.bottom + 12),
      decoration: const BoxDecoration(
        color: AppColors.darkSlate,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          // Botón Atrás
          if (_step > 0)
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: OutlinedButton(
                onPressed: _isLoading ? null : () => setState(() => _step--),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 50),
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  foregroundColor: AppColors.onSurfaceMuted,
                  side: const BorderSide(color: AppColors.border),
                ),
                child: const Text('Atrás'),
              ),
            ),

          // Botón Siguiente / Importar
          Expanded(
            child: ElevatedButton(
              onPressed: canAdvance
                  ? () async {
                      if (_step == 0) {
                        await _loadPreview();
                      } else if (_step == 2) {
                        await _runImport();
                      } else {
                        setState(() => _step++);
                      }
                    }
                  : null,
              child: _isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.darkSlate,
                      ),
                    )
                  : Text(nextLabel),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Paso 0 — Selección de archivo
// ---------------------------------------------------------------------------

class _Step0FileSelect extends StatelessWidget {
  const _Step0FileSelect({
    required this.filePath,
    required this.onPickFile,
    required this.isLoading,
  });

  final String? filePath;
  final VoidCallback onPickFile;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final hasFile = filePath != null;
    final fileName = filePath?.split('/').last.split('\\').last ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _StepTitle(
          icon: Icons.upload_file_rounded,
          title: 'Selecciona tu archivo',
          subtitle:
              'Acepta archivos Excel (.xlsx, .xls) o CSV (.csv) de cualquier proveedor.',
        ),
        const SizedBox(height: 24),

        // Zona de drop / selección
        GestureDetector(
          onTap: onPickFile,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
            decoration: BoxDecoration(
              color: hasFile
                  ? AppColors.emerald.withValues(alpha: 0.07)
                  : AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: hasFile ? AppColors.emerald : AppColors.border,
                width: hasFile ? 1.5 : 1,
                strokeAlign: BorderSide.strokeAlignOutside,
              ),
            ),
            child: Column(
              children: [
                Icon(
                  hasFile
                      ? Icons.insert_drive_file_rounded
                      : Icons.upload_file_outlined,
                  size: 48,
                  color: hasFile ? AppColors.emerald : AppColors.onSurfaceMuted,
                ),
                const SizedBox(height: 12),
                Text(
                  hasFile ? fileName : 'Toca para seleccionar un archivo',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: hasFile ? FontWeight.w600 : FontWeight.w400,
                    color:
                        hasFile ? AppColors.emerald : AppColors.onSurfaceMuted,
                  ),
                ),
                if (!hasFile) ...[
                  const SizedBox(height: 6),
                  const Text(
                    '.xlsx · .xls · .csv',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.onSurfaceMuted,
                    ),
                  ),
                ],
                if (hasFile) ...[
                  const SizedBox(height: 10),
                  TextButton.icon(
                    onPressed: onPickFile,
                    icon: const Icon(Icons.swap_horiz_rounded, size: 16),
                    label: const Text('Cambiar archivo'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.onSurfaceMuted,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),

        const SizedBox(height: 24),

        // Tips
        const _InfoTip(
          icon: Icons.lightbulb_outline_rounded,
          text: 'No necesitas adaptar tu archivo a ninguna plantilla. '
              'En el siguiente paso podrás indicar qué columna contiene '
              'el nombre, precio y cantidad de cada producto.',
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Paso 1 — Previsualización
// ---------------------------------------------------------------------------

class _Step1Preview extends StatelessWidget {
  const _Step1Preview({required this.preview});

  final FilePreview? preview;

  @override
  Widget build(BuildContext context) {
    if (preview == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _StepTitle(
          icon: Icons.table_rows_rounded,
          title: 'Previsualización',
          subtitle:
              'Así se ve tu archivo. Confirma que los datos se ven correctos antes de continuar.',
        ),
        const SizedBox(height: 20),
        ImportPreviewTable(preview: preview!),
        const SizedBox(height: 20),
        const _InfoTip(
          icon: Icons.info_outline_rounded,
          text: 'En el siguiente paso podrás indicar qué columna corresponde '
              'a Nombre, Precio y Cantidad.',
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Paso 2 — Mapeo de columnas
// ---------------------------------------------------------------------------

class _Step2Mapping extends StatelessWidget {
  const _Step2Mapping({
    required this.preview,
    required this.colName,
    required this.colPrice,
    required this.colStock,
    required this.onNameChanged,
    required this.onPriceChanged,
    required this.onStockChanged,
  });

  final FilePreview preview;
  final String? colName;
  final String? colPrice;
  final String? colStock;
  final ValueChanged<String?> onNameChanged;
  final ValueChanged<String?> onPriceChanged;
  final ValueChanged<String?> onStockChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _StepTitle(
          icon: Icons.settings_ethernet_rounded,
          title: 'Mapeo de columnas',
          subtitle: 'Indica qué columna de tu archivo contiene cada dato.',
        ),
        const SizedBox(height: 20),

        ColumnMapperRow(
          fieldLabel: 'Nombre del producto',
          fieldIcon: Icons.label_outline_rounded,
          isRequired: true,
          columns: preview.headers,
          selectedColumn: colName,
          onChanged: onNameChanged,
        ),
        const SizedBox(height: 10),
        ColumnMapperRow(
          fieldLabel: 'Precio de venta (MXN)',
          fieldIcon: Icons.attach_money_rounded,
          isRequired: true,
          columns: preview.headers,
          selectedColumn: colPrice,
          onChanged: onPriceChanged,
        ),
        const SizedBox(height: 10),
        ColumnMapperRow(
          fieldLabel: 'Stock inicial',
          fieldIcon: Icons.inventory_2_outlined,
          isRequired: false,
          columns: preview.headers,
          selectedColumn: colStock,
          onChanged: onStockChanged,
        ),

        const SizedBox(height: 20),

        // Mini-previsualización con el mapeo aplicado
        if (colName != null && colPrice != null) ...[
          _MappingPreview(
            preview: preview,
            colName: colName!,
            colPrice: colPrice!,
            colStock: colStock,
          ),
        ],
        const SizedBox(height: 16),
      ],
    );
  }
}

/// Vista previa de las 3 primeras filas con el mapeo ya aplicado.
class _MappingPreview extends StatelessWidget {
  const _MappingPreview({
    required this.preview,
    required this.colName,
    required this.colPrice,
    this.colStock,
  });

  final FilePreview preview;
  final String colName;
  final String colPrice;
  final String? colStock;

  int _colIndex(String col) => preview.headers.indexOf(col);

  @override
  Widget build(BuildContext context) {
    final nameIdx = _colIndex(colName);
    final priceIdx = _colIndex(colPrice);
    final stockIdx = colStock != null ? _colIndex(colStock!) : -1;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
            child: Text(
              'VISTA PREVIA CON EL MAPEO APLICADO',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: AppColors.onSurfaceMuted.withValues(alpha: 0.7),
                letterSpacing: 0.8,
              ),
            ),
          ),
          const Divider(height: 1, color: AppColors.border),
          ...preview.previewRows.take(3).map((row) {
            final name =
                nameIdx >= 0 && nameIdx < row.length ? row[nameIdx] : '—';
            final price =
                priceIdx >= 0 && priceIdx < row.length ? row[priceIdx] : '—';
            final stock =
                stockIdx >= 0 && stockIdx < row.length ? row[stockIdx] : '0';

            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: AppColors.border)),
              ),
              child: Row(
                children: [
                  Expanded(
                    flex: 5,
                    child: Text(
                      name,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: AppColors.onSurface,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    '\$$price',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.emerald,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '$stock pzs',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.onSurfaceMuted,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Paso 3 — Resultado
// ---------------------------------------------------------------------------

class _Step3Result extends StatelessWidget {
  const _Step3Result({
    required this.result,
    required this.onImportMore,
    required this.onClose,
  });

  final ImportResult result;
  final VoidCallback onImportMore;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final bool success = result.imported > 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Resultado global
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: success
                ? AppColors.emerald.withValues(alpha: 0.08)
                : AppColors.warning.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: success
                  ? AppColors.emerald.withValues(alpha: 0.4)
                  : AppColors.warning.withValues(alpha: 0.4),
            ),
          ),
          child: Column(
            children: [
              Icon(
                success
                    ? Icons.check_circle_outline_rounded
                    : Icons.warning_amber_rounded,
                size: 52,
                color: success ? AppColors.emerald : AppColors.warning,
              ),
              const SizedBox(height: 12),
              Text(
                success
                    ? '¡Importación completada!'
                    : 'Importación con advertencias',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: success ? AppColors.emerald : AppColors.warning,
                ),
              ),
              const SizedBox(height: 16),
              // Métricas
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _ResultMetric(
                    value: '${result.imported}',
                    label: 'Importados',
                    color: AppColors.emerald,
                  ),
                  _ResultMetric(
                    value: '${result.totalRows}',
                    label: 'Total filas',
                    color: AppColors.onSurface,
                  ),
                  _ResultMetric(
                    value: '${result.skipped}',
                    label: 'Omitidos',
                    color: result.skipped > 0
                        ? AppColors.warning
                        : AppColors.onSurfaceMuted,
                  ),
                ],
              ),
            ],
          ),
        ),

        // Lista de errores
        if (result.hasErrors) ...[
          const SizedBox(height: 20),
          Text(
            'FILAS CON ERRORES (${result.errors.length})',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: AppColors.onSurfaceMuted.withValues(alpha: 0.7),
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              children: result.errors.map((e) {
                final isLast = e == result.errors.last;
                return Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    border: isLast
                        ? null
                        : const Border(
                            bottom: BorderSide(color: AppColors.border)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.error.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'Fila ${e.row}',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppColors.error,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          e.issue,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.onSurfaceMuted,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],

        const SizedBox(height: 24),

        // Botones
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: onClose,
            child: const Text('Ver inventario'),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: onImportMore,
            child: const Text('Importar otro archivo'),
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

class _ResultMetric extends StatelessWidget {
  const _ResultMetric({
    required this.value,
    required this.label,
    required this.color,
  });

  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: AppColors.onSurfaceMuted,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Barra de progreso de pasos
// ---------------------------------------------------------------------------

class _StepProgressBar extends StatelessWidget {
  const _StepProgressBar({required this.step});

  final int step;

  @override
  Widget build(BuildContext context) {
    // 3 segmentos para pasos 0→1→2 (el paso 3 es resultado, sin barra)
    const totalSteps = 3;
    final progress = (step / totalSteps).clamp(0.0, 1.0);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: List.generate(totalSteps, (i) {
              final labels = ['Archivo', 'Previsualizar', 'Mapear'];
              final active = i <= step;
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: i < totalSteps - 1 ? 4 : 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        labels[i],
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight:
                              active ? FontWeight.w700 : FontWeight.w400,
                          color: active
                              ? AppColors.emerald
                              : AppColors.onSurfaceMuted,
                        ),
                      ),
                      const SizedBox(height: 3),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          value: i < step
                              ? 1.0
                              : (i == step
                                  ? progress * totalSteps - i.toDouble()
                                  : 0.0),
                          backgroundColor: AppColors.surfaceVariant,
                          valueColor:
                              const AlwaysStoppedAnimation(AppColors.emerald),
                          minHeight: 3,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Helpers de UI
// ---------------------------------------------------------------------------

class _StepTitle extends StatelessWidget {
  const _StepTitle({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.emerald.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 20, color: AppColors.emerald),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.onSurface,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.onSurfaceMuted,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _InfoTip extends StatelessWidget {
  const _InfoTip({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.skyBlue.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.skyBlue.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: AppColors.skyBlue),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.onSurfaceMuted,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded,
              size: 16, color: AppColors.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(fontSize: 12, color: AppColors.error),
            ),
          ),
        ],
      ),
    );
  }
}
