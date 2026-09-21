import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../domain/whatsapp_order.dart';

/// "¿Por qué se cancela?" — chips de un toque. Sin diálogo de confirmación:
/// cancelar es reversible ("Reabrir"), la fricción no se justifica. El
/// motivo alimenta reportes (cuántos se caen por falta de existencias).
Future<CancelReason?> showCancelReasonSheet(BuildContext context) =>
    showModalBottomSheet<CancelReason>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) => const _CancelReasonSheet(),
    );

class _CancelReasonSheet extends StatelessWidget {
  const _CancelReasonSheet();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Text(
              '¿Por qué se cancela?',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: AppColors.onSurface,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Un toque y listo. Si te equivocas, el pedido se puede reabrir.',
              style: TextStyle(fontSize: 12.5, color: AppColors.onSurfaceMuted),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final reason in CancelReason.values)
                  ActionChip(
                    key: Key('cancelReason-${reason.apiValue}'),
                    avatar: Icon(_icon(reason), size: 16,
                        color: AppColors.onSurface),
                    label: Text(reason.label),
                    labelStyle: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.onSurface),
                    backgroundColor: AppColors.surfaceVariant,
                    side: BorderSide.none,
                    onPressed: () => Navigator.of(context).pop(reason),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static IconData _icon(CancelReason reason) => switch (reason) {
        CancelReason.customerCancelled => Icons.person_off_outlined,
        CancelReason.outOfStock => Icons.inventory_2_outlined,
        CancelReason.neverConfirmed => Icons.hourglass_empty_rounded,
        CancelReason.duplicate => Icons.content_copy_rounded,
        CancelReason.spam => Icons.report_gmailerrorred_rounded,
        CancelReason.other => Icons.more_horiz_rounded,
      };
}
