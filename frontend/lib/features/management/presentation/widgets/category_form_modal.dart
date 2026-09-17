import 'dart:math' show max;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../domain/category.dart';
import '../management_provider.dart';

/// Alta y renombrado de categoría. Con [initial] abre en modo edición.
Future<void> showCategoryFormModal(
  BuildContext context, {
  Category? initial,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    backgroundColor: Colors.transparent,
    builder: (_) => CategoryFormModal(initial: initial),
  );
}

class CategoryFormModal extends ConsumerStatefulWidget {
  const CategoryFormModal({super.key, this.initial});

  final Category? initial;

  bool get isEditing => initial != null;

  @override
  ConsumerState<CategoryFormModal> createState() => _CategoryFormModalState();
}

class _CategoryFormModalState extends ConsumerState<CategoryFormModal> {
  final _controller = TextEditingController();
  final _focus = FocusNode();

  bool _isSaving = false;
  bool _isValid = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller.text = widget.initial?.name ?? '';
    _controller.addListener(_validate);
    _validate();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _validate() {
    final valid = _controller.text.trim().length >= 3;
    if (valid != _isValid) setState(() => _isValid = valid);
  }

  Future<void> _submit() async {
    if (!_isValid || _isSaving) return;
    setState(() {
      _isSaving = true;
      _error = null;
    });

    final name = _controller.text.trim();
    final notifier = ref.read(categoriesProvider.notifier);
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
                  widget.isEditing ? 'Renombrar categoría' : 'Nueva categoría',
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
            'Nombre',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: AppColors.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          TextFormField(
            key: const Key('categoryNameField'),
            controller: _controller,
            focusNode: _focus,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.done,
            style: const TextStyle(color: AppColors.onSurface, fontSize: 15),
            decoration: const InputDecoration(
              hintText: 'Ej: Lácteos',
              prefixIcon: Icon(Icons.sell_outlined, size: 18),
            ),
            onFieldSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 6),
          const Text(
            'Así la verás al dar de alta y al filtrar productos.',
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
                      key: const Key('categoryFormError'),
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
            key: const Key('categorySaveButton'),
            onPressed: _isValid && !_isSaving ? _submit : null,
            child: _isSaving
                ? const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.5, color: AppColors.darkSlate),
                  )
                : Text(widget.isEditing ? 'Guardar' : 'Crear categoría'),
          ),
        ],
      ),
    );
  }
}
