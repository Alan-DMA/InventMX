import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../inventory/data/inventory_repository.dart';
import '../../../inventory/domain/product.dart';
import '../../domain/public_catalog.dart';
import '../../domain/store_order.dart';
import '../../domain/whatsapp_order.dart';
import '../catalog_theme.dart' show mxn;
import '../whatsapp_catalog_provider.dart';

/// Edición del pedido tras lo acordado por chat: cantidades, quitar, agregar
/// producto del catálogo, entrega/dirección y observaciones. Devuelve el
/// [StoreOrderEdit] a mandar, o `null` si se cerró sin guardar. El backend
/// conserva la versión anterior y recalcula los totales; aquí se muestran
/// en vivo como referencia.
///
/// Escena: el tendero con el teléfono en una mano, el chat del cliente en la
/// otra. Cada grupo (productos, entrega, observaciones) es un bloque con aire,
/// el total y "Guardar" viven en un pie que respeta la barra del sistema y
/// el teclado (QA 20 sep: quedaba debajo de los botones de Android).
Future<StoreOrderEdit?> showOrderEditSheet(
  BuildContext context, {
  required StoreOrder order,
}) =>
    showModalBottomSheet<StoreOrderEdit>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppColors.darkSlate,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => OrderEditSheet(order: order),
    );

class OrderEditSheet extends ConsumerStatefulWidget {
  const OrderEditSheet({super.key, required this.order});

  final StoreOrder order;

  @override
  ConsumerState<OrderEditSheet> createState() => _OrderEditSheetState();
}

class _OrderEditSheetState extends ConsumerState<OrderEditSheet> {
  late final List<CartLine> _lines = List.of(widget.order.order.draft.lines);
  late DeliveryMethod _delivery = widget.order.order.draft.deliveryMethod;
  late final _address = TextEditingController(
      text: widget.order.order.draft.deliveryAddress ?? '');
  late final _notes =
      TextEditingController(text: widget.order.order.draft.orderNotes ?? '');
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  Timer? _debounce;
  List<Product> _results = const [];
  bool _searching = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _address.dispose();
    _notes.dispose();
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  // ── Derivados ─────────────────────────────────────────────────────────────

  double get _subtotal => _lines.fold(0, (s, l) => s + l.subtotalMxn);

  /// Tarifa de envío de la tienda. Se observa en `build` (el provider carga
  /// aparte); mientras no llega, la que traía el pedido si ya era a domicilio.
  double _feeFor(double? storeFee) {
    if (_delivery != DeliveryMethod.delivery) return 0;
    final original = widget.order.order.draft.deliveryMethod ==
            DeliveryMethod.delivery
        ? widget.order.order.totals.deliveryFeeMxn
        : null;
    return storeFee ?? original ?? 0;
  }

  int get _pieces => _lines.fold(0, (n, l) => n + l.quantity);

  bool get _addressMissing =>
      _delivery == DeliveryMethod.delivery && _address.text.trim().length < 5;

  bool get _canSave => _lines.isNotEmpty && !_addressMissing;

  // ── Renglones ─────────────────────────────────────────────────────────────

  void _setQty(int index, int qty) {
    setState(() {
      if (qty <= 0) {
        _lines.removeAt(index);
      } else {
        _lines[index] = _lines[index].copyWith(quantity: qty);
      }
    });
  }

  Future<void> _editNote(int index) async {
    final line = _lines[index];
    final controller = TextEditingController(text: line.notes ?? '');
    final note = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        title: Text(
          line.product.name,
          style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.onSurface),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 200,
          textCapitalization: TextCapitalization.sentences,
          style: const TextStyle(color: AppColors.onSurface),
          decoration: const InputDecoration(
              hintText: 'Nota del renglón (ej. bien fría)'),
        ),
        actions: [
          if (line.notes != null)
            TextButton(
              onPressed: () => Navigator.pop(ctx, ''),
              child: const Text('Quitar nota'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    if (note == null) return;
    setState(() {
      _lines[index] = _lines[index]
          .copyWith(notes: () => note.trim().isEmpty ? null : note.trim());
    });
  }

  void _onSearch(String text) {
    _debounce?.cancel();
    if (text.trim().length < 2) {
      setState(() => _results = const []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      setState(() => _searching = true);
      try {
        final page = await ref
            .read(inventoryRepositoryProvider)
            .getProducts(query: text.trim(), pageSize: 8);
        if (!mounted) return;
        setState(() => _results = page.items);
      } catch (_) {
        if (mounted) setState(() => _results = const []);
      } finally {
        if (mounted) setState(() => _searching = false);
      }
    });
  }

  void _add(Product product) {
    final existing = _lines.indexWhere((l) => l.product.id == product.id);
    setState(() {
      if (existing >= 0) {
        _lines[existing] =
            _lines[existing].copyWith(quantity: _lines[existing].quantity + 1);
      } else {
        _lines.add(CartLine(
          product: PublicCatalogProduct(
            id: product.id,
            name: product.name,
            sku: product.sku,
            priceMxn: product.priceMxn,
            categoryName: product.category,
            imageUrl: product.imageUrl,
            inStock: product.availableStock > 0,
            availableStock: product.availableStock.toDouble(),
          ),
          quantity: 1,
        ));
      }
      _search.clear();
      _results = const [];
    });
    _searchFocus.unfocus();
  }

  void _save() {
    Navigator.of(context).pop(StoreOrderEdit(
      lines: _lines,
      deliveryMethod: _delivery,
      deliveryAddress: _delivery == DeliveryMethod.delivery
          ? _address.text.trim()
          : null,
      orderNotes: _notes.text.trim(),
      expectedUpdatedAt: widget.order.order.updatedAt,
    ));
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final storeFee = ref.watch(catalogSettingsProvider).valueOrNull?.deliveryFeeMxn;
    final fee = _feeFor(storeFee);
    // Teclado abierto → el pie sube con él; sin teclado → respeta la barra
    // de gestos/botones del sistema. `useSafeArea` sólo cubre la parte alta.
    final bottomInset = media.viewInsets.bottom > 0
        ? media.viewInsets.bottom
        : media.viewPadding.bottom;

    return SizedBox(
      height: media.size.height * 0.92,
      child: Column(
        children: [
          _Header(folio: widget.order.folio),
          const Divider(height: 1, color: AppColors.border),
          Expanded(
            child: ListView(
              keyboardDismissBehavior:
                  ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
              children: [
                _GroupLabel('Productos', trailing: '$_pieces pzas'),
                const SizedBox(height: 8),
                _Panel(
                  child: Column(
                    children: [
                      if (_lines.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 14),
                          child: Text(
                            'Sin productos — agrega al menos uno abajo.',
                            style: TextStyle(
                                fontSize: 13, color: AppColors.warning),
                          ),
                        ),
                      for (var i = 0; i < _lines.length; i++) ...[
                        if (i > 0)
                          const Divider(height: 1, color: AppColors.border),
                        _LineEditor(
                          line: _lines[i],
                          onQty: (q) => _setQty(i, q),
                          onNote: () => _editNote(i),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                _AddProductField(
                  controller: _search,
                  focusNode: _searchFocus,
                  searching: _searching,
                  results: _results,
                  onChanged: _onSearch,
                  onPick: _add,
                ),
                const SizedBox(height: 26),
                const _GroupLabel('Entrega'),
                const SizedBox(height: 8),
                SegmentedButton<DeliveryMethod>(
                  key: const Key('orderEditDelivery'),
                  style: ButtonStyle(
                    visualDensity: VisualDensity.standard,
                    padding: const WidgetStatePropertyAll(
                        EdgeInsets.symmetric(vertical: 12)),
                    backgroundColor: WidgetStateProperty.resolveWith(
                      (s) => s.contains(WidgetState.selected)
                          ? AppColors.emerald.withValues(alpha: 0.18)
                          : AppColors.surface,
                    ),
                    foregroundColor: WidgetStateProperty.resolveWith(
                      (s) => s.contains(WidgetState.selected)
                          ? AppColors.emerald
                          : AppColors.onSurfaceMuted,
                    ),
                    side: const WidgetStatePropertyAll(
                        BorderSide(color: AppColors.border)),
                  ),
                  segments: const [
                    ButtonSegment(
                        value: DeliveryMethod.pickup,
                        icon: Icon(Icons.storefront_rounded, size: 18),
                        label: Text('Recoger')),
                    ButtonSegment(
                        value: DeliveryMethod.delivery,
                        icon: Icon(Icons.delivery_dining_rounded, size: 18),
                        label: Text('A domicilio')),
                  ],
                  selected: {_delivery},
                  onSelectionChanged: (s) =>
                      setState(() => _delivery = s.first),
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  alignment: Alignment.topCenter,
                  child: _delivery == DeliveryMethod.delivery
                      ? Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: TextField(
                            key: const Key('orderEditAddress'),
                            controller: _address,
                            onChanged: (_) => setState(() {}),
                            textCapitalization: TextCapitalization.sentences,
                            style:
                                const TextStyle(color: AppColors.onSurface),
                            decoration: InputDecoration(
                              labelText: 'Dirección de entrega',
                              prefixIcon: const Icon(Icons.place_outlined),
                              // El botón se apaga sin dirección: aquí se
                              // dice por qué, junto al campo que lo resuelve.
                              helperText: _address.text.trim().isEmpty
                                  ? 'Necesaria para guardar un pedido a domicilio'
                                  : null,
                              errorText: _addressMissing &&
                                      _address.text.isNotEmpty
                                  ? 'Escribe calle y número'
                                  : null,
                            ),
                          ),
                        )
                      : const SizedBox(width: double.infinity),
                ),
                const SizedBox(height: 26),
                const _GroupLabel('Observaciones'),
                const SizedBox(height: 8),
                TextField(
                  key: const Key('orderEditNotes'),
                  controller: _notes,
                  maxLines: 3,
                  minLines: 2,
                  textCapitalization: TextCapitalization.sentences,
                  style: const TextStyle(color: AppColors.onSurface),
                  decoration: const InputDecoration(
                    hintText: 'Lo que acordaron por el chat',
                    alignLabelWithHint: true,
                  ),
                ),
              ],
            ),
          ),
          _Footer(
            total: _subtotal + fee,
            fee: fee,
            pieces: _pieces,
            bottomInset: bottomInset,
            canSave: _canSave,
            onSave: _save,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Piezas
// ---------------------------------------------------------------------------

class _Header extends StatelessWidget {
  const _Header({required this.folio});

  final String folio;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 8, 12),
        child: Column(
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Editar $folio',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: AppColors.onSurface,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 3),
                      const Text(
                        'Lo que cambies lo verá el cliente en su enlace. '
                        'La versión anterior se conserva.',
                        style: TextStyle(
                            fontSize: 12.5,
                            height: 1.35,
                            color: AppColors.onSurfaceMuted),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Cerrar sin guardar',
                  icon: const Icon(Icons.close_rounded,
                      color: AppColors.onSurfaceMuted),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ],
        ),
      );
}

class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.text, {this.trailing});

  final String text;
  final String? trailing;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Text(
            text.toUpperCase(),
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.9,
              color: AppColors.onSurfaceMuted.withValues(alpha: 0.85),
            ),
          ),
          if (trailing != null) ...[
            const Spacer(),
            Text(
              trailing!,
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.onSurfaceMuted),
            ),
          ],
        ],
      );
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: child,
      );
}

/// Renglón: nombre y precio a la izquierda, subtotal y stepper a la derecha,
/// nota como tercera línea tocable (no un icono suelto compitiendo con el
/// stepper).
class _LineEditor extends StatelessWidget {
  const _LineEditor({
    required this.line,
    required this.onQty,
    required this.onNote,
  });

  final CartLine line;
  final ValueChanged<int> onQty;
  final VoidCallback onNote;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        line.product.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w600,
                            height: 1.25,
                            color: AppColors.onSurface),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${mxn(line.product.priceMxn)} c/u · ${mxn(line.subtotalMxn)}',
                        style: const TextStyle(
                            fontSize: 12.5,
                            color: AppColors.onSurfaceMuted),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                _Stepper(
                  productId: line.product.id,
                  quantity: line.quantity,
                  onChanged: onQty,
                ),
              ],
            ),
            const SizedBox(height: 6),
            InkWell(
              key: Key('orderEditNote-${line.product.id}'),
              onTap: onNote,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Icon(
                      line.notes != null
                          ? Icons.sticky_note_2_rounded
                          : Icons.add_comment_outlined,
                      size: 15,
                      color: line.notes != null
                          ? AppColors.skyBlue
                          : AppColors.onSurfaceMuted,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        line.notes ?? 'Agregar nota',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: line.notes != null
                              ? AppColors.onSurface
                              : AppColors.onSurfaceMuted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
}

/// Stepper de 44 px de alto: dedos, no cursores. En 1, el "−" se vuelve
/// papelera para que quitar el renglón sea explícito.
class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.productId,
    required this.quantity,
    required this.onChanged,
  });

  final String productId;
  final int quantity;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final removing = quantity <= 1;
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _StepButton(
            key: Key('orderEditMinus-$productId'),
            icon: removing ? Icons.delete_outline_rounded : Icons.remove_rounded,
            color: removing ? AppColors.error : AppColors.onSurface,
            onTap: () => onChanged(quantity - 1),
          ),
          SizedBox(
            width: 34,
            child: Text(
              '$quantity',
              key: Key('orderEditQty-$productId'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: AppColors.onSurface),
            ),
          ),
          _StepButton(
            key: Key('orderEditPlus-$productId'),
            icon: Icons.add_rounded,
            color: AppColors.emerald,
            onTap: () => onChanged(quantity + 1),
          ),
        ],
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({
    super.key,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(icon, size: 20, color: color),
        ),
      );
}

/// "Agregar producto": campo + resultados en el mismo bloque, para que quede
/// claro qué lista alimenta y que un toque los mete al pedido.
class _AddProductField extends StatelessWidget {
  const _AddProductField({
    required this.controller,
    required this.focusNode,
    required this.searching,
    required this.results,
    required this.onChanged,
    required this.onPick,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool searching;
  final List<Product> results;
  final ValueChanged<String> onChanged;
  final ValueChanged<Product> onPick;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const Key('orderEditSearch'),
            controller: controller,
            focusNode: focusNode,
            onChanged: onChanged,
            textInputAction: TextInputAction.search,
            style: const TextStyle(color: AppColors.onSurface),
            decoration: InputDecoration(
              hintText: 'Agregar producto del catálogo',
              prefixIcon: const Icon(Icons.add_circle_outline_rounded,
                  color: AppColors.emerald),
              suffixIcon: searching
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2)),
                    )
                  : controller.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close_rounded, size: 18),
                          onPressed: () {
                            controller.clear();
                            onChanged('');
                          },
                        ),
            ),
          ),
          if (results.isNotEmpty) ...[
            const SizedBox(height: 6),
            _Panel(
              child: Column(
                children: [
                  for (var i = 0; i < results.length; i++) ...[
                    if (i > 0)
                      const Divider(height: 1, color: AppColors.border),
                    _ResultRow(product: results[i], onTap: () => onPick(results[i])),
                  ],
                ],
              ),
            ),
          ] else if (controller.text.trim().length >= 2 && !searching) ...[
            const SizedBox(height: 8),
            const Text(
              'Nada con ese nombre en tu inventario.',
              style: TextStyle(fontSize: 12.5, color: AppColors.onSurfaceMuted),
            ),
          ],
        ],
      );
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({required this.product, required this.onTap});

  final Product product;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final out = product.availableStock <= 0;
    return InkWell(
      key: Key('orderEditResult-${product.id}'),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 11, 12, 11),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(product.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.onSurface)),
                  const SizedBox(height: 2),
                  Text(
                    '${mxn(product.priceMxn)} · ${out ? 'agotado' : 'quedan ${product.availableStock}'}',
                    style: TextStyle(
                        fontSize: 12,
                        color: out ? AppColors.warning : AppColors.onSurfaceMuted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.add_rounded, color: AppColors.emerald),
          ],
        ),
      ),
    );
  }
}

/// Total grande a la izquierda, "Guardar" a la derecha; el padding inferior
/// es el del teclado si está abierto o el de la barra del sistema si no.
class _Footer extends StatelessWidget {
  const _Footer({
    required this.total,
    required this.fee,
    required this.pieces,
    required this.bottomInset,
    required this.canSave,
    required this.onSave,
  });

  final double total;
  final double fee;
  final int pieces;
  final double bottomInset;
  final bool canSave;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) => Container(
        padding: EdgeInsets.fromLTRB(20, 12, 20, 12 + bottomInset),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Total',
                    style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.4,
                        color: AppColors.onSurfaceMuted),
                  ),
                  Text(
                    mxn(total),
                    key: const Key('orderEditTotal'),
                    style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                        color: AppColors.emerald),
                  ),
                  Text(
                    fee > 0
                        ? '$pieces pzas · incluye envío ${mxn(fee)}'
                        : '$pieces pzas',
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.onSurfaceMuted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              height: 50,
              child: FilledButton.icon(
                key: const Key('orderEditSave'),
                onPressed: canSave ? onSave : null,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.emerald,
                  foregroundColor: AppColors.darkSlate,
                  disabledBackgroundColor:
                      AppColors.emerald.withValues(alpha: 0.25),
                  disabledForegroundColor:
                      AppColors.darkSlate.withValues(alpha: 0.6),
                  padding: const EdgeInsets.symmetric(horizontal: 22),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                icon: const Icon(Icons.check_rounded, size: 20),
                label: const Text('Guardar',
                    style:
                        TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
              ),
            ),
          ],
        ),
      );
}
