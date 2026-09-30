import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../core/admin_colors.dart';
import '../../core/admin_http.dart';
import '../../core/store_status.dart';
import '../data/tenants_repository.dart';
import '../domain/tenant_models.dart';

/// Buscador de tiendas (Ctrl K o el campo de Hoy): nombre, slug o correo del
/// dueño. Devuelve la tienda elegida; quien lo abre muestra su ficha.
Future<TenantSummary?> showStoreSearch(BuildContext context) => showDialog<TenantSummary>(
      context: context,
      barrierColor: Colors.black54,
      builder: (_) => const StoreSearchDialog(),
    );

class StoreSearchDialog extends ConsumerStatefulWidget {
  const StoreSearchDialog({super.key});

  static const minChars = 2;

  @override
  ConsumerState<StoreSearchDialog> createState() => _StoreSearchDialogState();
}

class _StoreSearchDialogState extends ConsumerState<StoreSearchDialog> {
  final _query = TextEditingController();
  Timer? _debounce;
  List<TenantSummary>? _results;
  String? _error;
  bool _loading = false;
  int _selected = 0;
  int _request = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    if (value.trim().length < StoreSearchDialog.minChars) {
      setState(() {
        _results = null;
        _error = null;
        _loading = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () => _search(value.trim()));
  }

  Future<void> _search(String q) async {
    final request = ++_request;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await ref.read(tenantsRepositoryProvider).search(q);
      if (!mounted || request != _request) return;
      setState(() {
        _results = results;
        _selected = 0;
        _loading = false;
      });
    } on AdminApiException catch (e) {
      if (!mounted || request != _request) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  void _move(int delta) {
    final n = _results?.length ?? 0;
    if (n == 0) return;
    setState(() => _selected = (_selected + delta).clamp(0, n - 1));
  }

  void _choose([TenantSummary? t]) {
    final pick = t ?? ((_results?.isNotEmpty ?? false) ? _results![_selected] : null);
    if (pick != null) Navigator.of(context).pop(pick);
  }

  @override
  Widget build(BuildContext context) {
    final results = _results;
    return Dialog(
      backgroundColor: AppColors.surface,
      alignment: const Alignment(0, -0.6),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AppColors.border),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 520),
        child: Column(
          key: const Key('storeSearchDialog'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: CallbackShortcuts(
                bindings: {
                  const SingleActivator(LogicalKeyboardKey.arrowDown): () => _move(1),
                  const SingleActivator(LogicalKeyboardKey.arrowUp): () => _move(-1),
                },
                child: TextField(
                  key: const Key('storeSearchField'),
                  controller: _query,
                  autofocus: true,
                  onChanged: _onChanged,
                  onSubmitted: (_) => _choose(),
                  decoration: const InputDecoration(
                    hintText: 'Nombre de la tienda, slug o correo del dueño',
                    prefixIcon: Icon(Icons.search_rounded, size: 20),
                  ),
                ),
              ),
            ),
            const Divider(height: 1),
            Flexible(child: _body(results)),
            const Divider(height: 1),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 10),
              child: Text(
                '↑ ↓ para elegir · Enter abre la ficha · Esc cierra',
                style: TextStyle(fontSize: 12, color: AppColors.onSurfaceMuted),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body(List<TenantSummary>? results) {
    Widget note(String text, {Color color = AppColors.onSurfaceMuted}) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          child: Text(text, style: TextStyle(fontSize: 13.5, color: color, height: 1.45)),
        );
    if (_error != null) return note(_error!, color: AppColors.error);
    if (_loading && results == null) return note('Buscando…');
    if (results == null) return note('Escribe al menos ${StoreSearchDialog.minChars} letras.');
    if (results.isEmpty) {
      return note('Sin resultados. Prueba con parte del nombre, el slug (la dirección de su catálogo) o el '
          'correo con el que entra el dueño.');
    }
    return ListView.builder(
      key: const Key('storeSearchResults'),
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(vertical: 6),
      itemCount: results.length,
      itemBuilder: (context, i) {
        final t = results[i];
        final (label, color) = storeStatus(t.status, t.lockReason);
        final selected = i == _selected;
        return Material(
          color: selected ? AdminColors.indigoSoft : Colors.transparent,
          child: InkWell(
            key: Key('storeResult_${t.id}'),
            onTap: () => _choose(t),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: AppColors.onSurface),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          [t.slug, if (t.ownerEmail != null) t.ownerEmail!].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12.5, color: AppColors.onSurfaceMuted),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(label, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: color)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
