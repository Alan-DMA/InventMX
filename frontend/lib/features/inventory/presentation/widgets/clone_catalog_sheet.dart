import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import '../../data/clone_catalog_repository.dart';
import '../../domain/clone_catalog.dart';
import '../../domain/product.dart';
import '../inventory_provider.dart';

// ---------------------------------------------------------------------------
// Apertura
// ---------------------------------------------------------------------------

/// Asistente de clonación de catálogo a otra tienda (Tarea 15.2.2 · RF-31).
///
/// Tres pasos en una sola hoja: destino y opciones → duplicando → resumen.
/// Solo se abre desde "Mi cuenta" cuando el plan es Corporativo; nunca se
/// muestra para luego negar.
Future<void> showCloneCatalogSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => const CloneCatalogSheet(),
  );
}

// ---------------------------------------------------------------------------
// Hoja
// ---------------------------------------------------------------------------

enum _Step { setup, cloning, done }

class CloneCatalogSheet extends ConsumerStatefulWidget {
  const CloneCatalogSheet({super.key});

  @override
  ConsumerState<CloneCatalogSheet> createState() => _CloneCatalogSheetState();
}

class _CloneCatalogSheetState extends ConsumerState<CloneCatalogSheet> {
  final _codeController = TextEditingController();

  _Step _step = _Step.setup;

  // Destino
  CloneTarget? _target;
  bool _lookingUp = false;
  bool _lookupFailed = false;
  String? _lookedUpCode;

  // Opciones
  bool _includePrices = true;
  bool _includeCategories = true;
  String? _filterCategory;

  // Avance y resultado
  CloneProgress? _progress;
  CloneCatalogResult? _result;
  String? _error;

  @override
  void initState() {
    super.initState();
    _codeController.addListener(() {
      // Al editar el código, el destino anterior deja de ser válido.
      if (_target != null && _codeController.text.trim() != _target!.code) {
        setState(() {
          _target = null;
          _lookupFailed = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  // ── Lógica ────────────────────────────────────────────────────────────────

  List<Product> get _sourceProducts {
    final all = ref.read(inventoryProvider).products.where((p) => p.isActive);
    if (_filterCategory == null) return all.toList();
    return all.where((p) => p.category == _filterCategory).toList();
  }

  Future<void> _lookupTarget() async {
    final code = _codeController.text.trim();
    if (code.isEmpty || _lookingUp) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _lookingUp = true;
      _lookupFailed = false;
      _lookedUpCode = code;
    });
    try {
      final target = await ref.read(cloneCatalogRepositoryProvider).findTargetByCode(code);
      if (!mounted) return;
      setState(() {
        _target = target;
        _lookupFailed = target == null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _lookupFailed = true);
    } finally {
      if (mounted) setState(() => _lookingUp = false);
    }
  }

  Future<void> _clone() async {
    final target = _target;
    if (target == null) return;
    final source = _sourceProducts;
    setState(() {
      _step = _Step.cloning;
      _progress = null;
      _error = null;
    });
    try {
      final result = await ref.read(cloneCatalogRepositoryProvider).cloneCatalog(
            CloneCatalogRequest(
              targetTenantId: target.tenantId,
              includePrices: _includePrices,
              includeCategories: _includeCategories,
              filterCategory: _filterCategory,
            ),
            sourceProducts: source,
            onProgress: (p) {
              if (mounted) setState(() => _progress = p);
            },
          );
      if (!mounted) return;
      setState(() {
        _result = result;
        _step = _Step.done;
      });
    } on CloneCatalogException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _step = _Step.setup;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudo clonar el catálogo. Revisa tu conexión e intenta de nuevo.';
        _step = _Step.setup;
      });
    }
  }

  // ── UI ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return AnimatedPadding(
      duration: const Duration(milliseconds: 150),
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              switch (_step) {
                _Step.setup => _buildSetup(context),
                _Step.cloning => _buildCloning(),
                _Step.done => _buildDone(context),
              },
            ],
          ),
        ),
      ),
    );
  }

  // ── Paso 1: destino y opciones ────────────────────────────────────────────

  Widget _buildSetup(BuildContext context) {
    final categories = ref.watch(inventoryProvider).availableCategories;
    final count = _sourceProducts.length;
    final canClone = _target != null && count > 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'Clonar catálogo a otra tienda',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: AppColors.onSurface,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Se copian nombres, categorías, códigos de barras y precios. '
          'El stock, el kardex y los costos no se copian: la otra tienda '
          'empieza en cero.',
          style: TextStyle(fontSize: 13, color: AppColors.onSurfaceMuted, height: 1.4),
        ),
        const SizedBox(height: 20),

        // Código de la tienda destino
        const Text(
          'Código de la tienda destino',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.onSurface),
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                key: const Key('cloneTargetCodeField'),
                controller: _codeController,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _lookupTarget(),
                style: const TextStyle(
                  fontSize: 16,
                  color: AppColors.onSurface,
                  fontFeatures: [FontFeature.tabularFigures()],
                  letterSpacing: 1.5,
                ),
                decoration: const InputDecoration(
                  hintText: 'Ej. 220118',
                  helperText: 'Pídeselo al dueño de la otra tienda.',
                  helperMaxLines: 2,
                  helperStyle: TextStyle(fontSize: 11, color: AppColors.onSurfaceMuted),
                ),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              height: 52,
              child: OutlinedButton(
                key: const Key('cloneLookupButton'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(88, 52),
                  foregroundColor: AppColors.onSurface,
                  side: const BorderSide(color: AppColors.border),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: _lookingUp ? null : _lookupTarget,
                child: _lookingUp
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onSurfaceMuted),
                      )
                    : const Text('Buscar', style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),

        // Resultado de la búsqueda
        if (_target != null) ...[
          const SizedBox(height: 10),
          _TargetCard(target: _target!),
        ] else if (_lookupFailed) ...[
          const SizedBox(height: 10),
          Text(
            'No encontramos ninguna tienda con el código $_lookedUpCode. '
            'Revísalo con su dueño.',
            key: const Key('cloneTargetNotFound'),
            style: const TextStyle(fontSize: 13, color: AppColors.error, height: 1.35),
          ),
        ],

        const SizedBox(height: 20),
        const Divider(height: 1, color: AppColors.border),
        const SizedBox(height: 8),

        // Opciones
        _OptionRow(
          key: const Key('cloneIncludePrices'),
          title: 'Copiar precios',
          subtitle: _includePrices
              ? 'La otra tienda arranca con tus precios de venta.'
              : 'Los productos se clonan en \$0.00; la otra tienda pone los suyos.',
          value: _includePrices,
          onChanged: (v) => setState(() => _includePrices = v),
        ),
        _OptionRow(
          key: const Key('cloneIncludeCategories'),
          title: 'Copiar categorías',
          subtitle: _includeCategories
              ? 'Mismas categorías que aquí.'
              : 'Todo cae en "General".',
          value: _includeCategories,
          onChanged: (v) => setState(() => _includeCategories = v),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String?>(
          key: const Key('cloneFilterCategory'),
          initialValue: _filterCategory,
          dropdownColor: AppColors.surface,
          style: const TextStyle(fontSize: 14, color: AppColors.onSurface),
          decoration: const InputDecoration(labelText: 'Qué clonar'),
          items: [
            const DropdownMenuItem<String?>(value: null, child: Text('Todo el catálogo')),
            for (final c in categories)
              DropdownMenuItem<String?>(value: c, child: Text('Solo $c')),
          ],
          onChanged: (v) => setState(() => _filterCategory = v),
        ),

        if (_error != null) ...[
          const SizedBox(height: 14),
          Text(
            _error!,
            key: const Key('cloneError'),
            style: const TextStyle(fontSize: 13, color: AppColors.error, height: 1.35),
          ),
        ],

        const SizedBox(height: 20),

        // Resumen + acción primaria: dice exactamente qué va a pasar
        Text(
          _target == null
              ? '$count ${count == 1 ? 'producto' : 'productos'} por clonar · falta la tienda destino'
              : 'Se clonarán $count ${count == 1 ? 'producto' : 'productos'} a ${_target!.name}',
          key: const Key('cloneSummary'),
          style: const TextStyle(
            fontSize: 13,
            color: AppColors.onSurfaceMuted,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: FilledButton(
            key: const Key('cloneConfirmButton'),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.emerald,
              foregroundColor: AppColors.darkSlate,
              disabledBackgroundColor: AppColors.surfaceVariant,
              disabledForegroundColor: AppColors.onSurfaceMuted,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            onPressed: canClone ? _clone : null,
            child: Text(
              count == 0 ? 'Nada que clonar' : 'Clonar $count ${count == 1 ? 'producto' : 'productos'}',
            ),
          ),
        ),
      ],
    );
  }

  // ── Paso 2: duplicando ────────────────────────────────────────────────────

  Widget _buildCloning() {
    final p = _progress;
    return Column(
      key: const Key('cloneProgress'),
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Clonando a ${_target?.name ?? 'la tienda destino'}…',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.onSurface),
        ),
        const SizedBox(height: 18),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: p?.fraction,
            minHeight: 8,
            backgroundColor: AppColors.surfaceVariant,
            color: AppColors.emerald,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          p == null
              ? 'Preparando…'
              : '${p.done} de ${p.total}${p.currentName == null ? '' : ' · ${p.currentName}'}',
          style: const TextStyle(
            fontSize: 13,
            color: AppColors.onSurfaceMuted,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  // ── Paso 3: resumen ───────────────────────────────────────────────────────

  Widget _buildDone(BuildContext context) {
    final r = _result!;
    final n = r.productsCloned;
    return Column(
      key: const Key('cloneDone'),
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            const Icon(Icons.check_circle_outline_rounded, color: AppColors.emerald, size: 26),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '$n ${n == 1 ? 'producto clonado' : 'productos clonados'} a ${_target?.name ?? 'la tienda destino'}',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.onSurface,
                  height: 1.25,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          _includePrices
              ? 'Con tus precios de venta y ${_includeCategories ? 'tus categorías' : 'todo en "General"'}. '
                  'Stock, kardex y costos no se copiaron: la tienda arranca en cero.'
              : 'Precios en \$0.00 para que la tienda ponga los suyos. '
                  'Stock, kardex y costos no se copiaron: la tienda arranca en cero.',
          style: const TextStyle(fontSize: 13, color: AppColors.onSurfaceMuted, height: 1.4),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: FilledButton(
            key: const Key('cloneCloseButton'),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.emerald,
              foregroundColor: AppColors.darkSlate,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Listo'),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Piezas
// ---------------------------------------------------------------------------

class _TargetCard extends StatelessWidget {
  const _TargetCard({required this.target});
  final CloneTarget target;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('cloneTargetCard'),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.darkSlate,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          const Icon(Icons.storefront_rounded, color: AppColors.onSurface, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  target.name,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.onSurface),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  target.productCount == 0
                      ? 'Código ${target.code} · sin productos todavía'
                      : 'Código ${target.code} · ya tiene ${target.productCount} productos',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.onSurfaceMuted,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OptionRow extends StatelessWidget {
  const _OptionRow({
    super.key,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.onSurface),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(fontSize: 12, color: AppColors.onSurfaceMuted, height: 1.3),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Switch(
              value: value,
              activeThumbColor: AppColors.emerald,
              onChanged: onChanged,
            ),
          ],
        ),
      ),
    );
  }
}
