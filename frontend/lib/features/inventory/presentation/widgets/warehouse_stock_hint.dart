import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../domain/product.dart';
import '../inventory_provider.dart';

/// `id → nombre` de los almacenes del comercio, para rotular existencias.
final warehouseNamesProvider = Provider<Map<String, String>>((ref) {
  final options = ref.watch(warehousesProvider).valueOrNull ?? const [];
  return {for (final option in options) option.id: option.name};
});

/// "Hay 26 en Bodega" cuando aquí no queda nada pero otra bodega sí tiene
/// (D24): el tendero se entera de que puede pedir un traslado en vez de
/// creer que se acabó. Nulo si aquí hay existencias o no hay en otro lado.
String? otherWarehousesHint(Product product, Map<String, String> names) {
  if (product.availableStock > 0) return null;
  final elsewhere = product.stockElsewhere.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  if (elsewhere.isEmpty) return null;

  final parts = [
    for (final entry in elsewhere)
      '${entry.value} en ${names[entry.key] ?? 'otro almacén'}',
  ];
  final joined = parts.length == 1
      ? parts.single
      : '${parts.sublist(0, parts.length - 1).join(', ')} y ${parts.last}';
  return 'Hay $joined';
}

/// Renglón pequeño con el aviso de [otherWarehousesHint].
class OtherWarehousesHint extends StatelessWidget {
  const OtherWarehousesHint({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      key: const Key('otherWarehousesHint'),
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.warehouse_outlined, size: 13, color: AppColors.skyBlue),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppColors.skyBlue,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
