import 'dart:math' show max;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../domain/warehouse.dart';
import '../management_provider.dart';

/// Alta y edición de almacén. Con [initial] abre en modo edición.
Future<void> showWarehouseFormModal(
  BuildContext context, {
  Warehouse? initial,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    backgroundColor: Colors.transparent,
    builder: (_) => WarehouseFormModal(initial: initial),
  );
}

class WarehouseFormModal extends ConsumerStatefulWidget {
  const WarehouseFormModal({super.key, this.initial});

  final Warehouse? initial;

  bool get isEditing => initial != null;

  @override
  ConsumerState<WarehouseFormModal> createState() => _WarehouseFormModalState();
}

class _WarehouseFormModalState extends ConsumerState<WarehouseFormModal> {
  final _nameController = TextEditingController();
  final _nameFocus = FocusNode();

  bool _isSaving = false;
  bool _isValid = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _nameController.text = widget.initial?.name ?? '';
    _nameController.addListener(_validate);
    _validate();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _nameFocus.requestFocus());
  }

  @override
  void dispose() {
    _nameController.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  void _validate() {
    final valid = _nameController.text.trim().length >= 3;
    if (valid != _isValid) setState(() => _isValid = valid);
  }

  Future<void> _submit() async {
    if (!_isValid || _isSaving) return;
    setState(() {
      _isSaving = true;
      _error = null;
    });

    final name = _nameController.text.trim();
    final notifier = ref.read(warehousesProvider.notifier);
    try {
      if (widget.isEditing) {
        await notifier.rename(id: widget.initial!.id, name: name);
      } else {
        await notifier.create(name);
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() {
        _isSaving = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final bottomInset = max(mq.viewInsets.bottom, mq.padding.bottom);

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(24, 12, 24, 24 + bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.isEditing ? 'Editar almacén' : 'Nuevo almacén',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.onSurface,
                  ),
                ),
              ),
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded,
                    size: 22, color: AppColors.onSurfaceMuted),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                tooltip: 'Cerrar',
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Text(
            'Nombre del almacén',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: AppColors.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          TextFormField(
            key: const Key('warehouseNameField'),
            controller: _nameController,
            focusNode: _nameFocus,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.done,
            style: const TextStyle(color: AppColors.onSurface, fontSize: 15),
            decoration: const InputDecoration(
              hintText: 'Ej: Bodega Norte',
              prefixIcon: Icon(Icons.warehouse_outlined, size: 18),
            ),
            onFieldSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 6),
          const Text(
            'Así lo verás al vender, ajustar stock y trasladar mercancía.',
            style: TextStyle(fontSize: 11, color: AppColors.onSurfaceMuted),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
                border:
                    Border.all(color: AppColors.error.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline_rounded,
                      size: 16, color: AppColors.error),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _error!,
                      key: const Key('warehouseFormError'),
                      style:
                          const TextStyle(fontSize: 13, color: AppColors.error),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 24),
          ElevatedButton(
            key: const Key('warehouseSaveButton'),
            onPressed: _isValid && !_isSaving ? _submit : null,
            child: _isSaving
                ? const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.5, color: AppColors.darkSlate),
                  )
                : Text(widget.isEditing ? 'Guardar cambios' : 'Crear almacén'),
          ),
        ],
      ),
    );
  }
}
