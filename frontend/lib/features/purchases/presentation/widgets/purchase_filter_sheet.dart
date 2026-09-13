import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';

/// Bottom sheet del ícono ▤ ("Abrir filtros", Figma nodo `1:39`) — rango de
/// fechas alineado con `DateFromParam`/`DateToParam` de
/// `docs/api/purchases.yaml`.
class PurchaseFilterResult {
  const PurchaseFilterResult({this.dateFrom, this.dateTo});

  final DateTime? dateFrom;
  final DateTime? dateTo;
}

Future<PurchaseFilterResult?> showPurchaseFilterSheet(
  BuildContext context, {
  DateTime? initialFrom,
  DateTime? initialTo,
}) {
  return showModalBottomSheet<PurchaseFilterResult>(
    context: context,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _PurchaseFilterSheet(
      initialFrom: initialFrom,
      initialTo: initialTo,
    ),
  );
}

class _PurchaseFilterSheet extends StatefulWidget {
  const _PurchaseFilterSheet({this.initialFrom, this.initialTo});

  final DateTime? initialFrom;
  final DateTime? initialTo;

  @override
  State<_PurchaseFilterSheet> createState() => _PurchaseFilterSheetState();
}

class _PurchaseFilterSheetState extends State<_PurchaseFilterSheet> {
  late DateTime? _from = widget.initialFrom;
  late DateTime? _to = widget.initialTo;

  Future<void> _pickDate({required bool isFrom}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: (isFrom ? _from : _to) ?? DateTime.now(),
      firstDate: DateTime(2024),
      lastDate: DateTime(2030),
    );
    if (picked == null) return;
    setState(() {
      if (isFrom) {
        _from = picked;
      } else {
        _to = picked;
      }
    });
  }

  String _fmt(DateTime? d) =>
      d == null ? 'Sin definir' : '${d.day}/${d.month}/${d.year}';

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: 20 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Filtrar por fecha',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: AppColors.onSurface,
            ),
          ),
          const SizedBox(height: 16),
          _DateRow(label: 'Desde', value: _fmt(_from), onTap: () => _pickDate(isFrom: true)),
          const SizedBox(height: 10),
          _DateRow(label: 'Hasta', value: _fmt(_to), onTap: () => _pickDate(isFrom: false)),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(
                    context,
                    const PurchaseFilterResult(),
                  ),
                  child: const Text('Limpiar'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(
                    context,
                    PurchaseFilterResult(dateFrom: _from, dateTo: _to),
                  ),
                  child: const Text('Aplicar'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DateRow extends StatelessWidget {
  const _DateRow({required this.label, required this.value, required this.onTap});

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Text(label, style: const TextStyle(color: AppColors.onSurfaceMuted, fontSize: 14)),
            const Spacer(),
            Text(value, style: const TextStyle(color: AppColors.onSurface, fontSize: 14, fontWeight: FontWeight.w600)),
            const SizedBox(width: 6),
            const Icon(Icons.calendar_today_rounded, size: 16, color: AppColors.skyBlue),
          ],
        ),
      ),
    );
  }
}
