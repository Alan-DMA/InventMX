import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../domain/cash_movement.dart';
import 'cash_movement_tile.dart';

/// A partir de este número de filas se acota la altura y se activa el
/// scroll interno — con 4 movimientos o menos se muestran todos, tal como
/// antes.
const _kMaxVisibleRows = 4;

/// Alto aproximado de una fila (`CashMovementTile`, ver ese archivo): 20px
/// de padding vertical + ~32px de contenido.
const _kRowHeight = 53.0;

/// Lista de movimientos de caja menor con altura acotada — usada tanto en
/// `CashSessionScreen` (turno abierto, Subtarea 10.2.2) como en
/// `CashSessionSummaryScreen` (ticket Corte Z, Subtarea 10.2.3).
///
/// Sin este límite, un turno con muchos movimientos alargaba
/// indefinidamente el `Column` contenedor y, con él, el scroll de toda la
/// pantalla (reportado por Eduardo en QA). Con 4 filas o menos no cambia
/// nada visualmente; a partir de la 5ª, la altura se acota a un rango que
/// deja siempre 3-4 filas legibles (ajustado al alto del viewport) y el
/// resto se revela con scroll propio del contenedor, no de la pantalla.
class CashMovementsListBox extends StatelessWidget {
  const CashMovementsListBox({super.key, required this.movements});

  final List<CashMovement> movements;

  @override
  Widget build(BuildContext context) {
    if (movements.length <= _kMaxVisibleRows) {
      return Column(
        children: [
          for (var i = 0; i < movements.length; i++) ...[
            if (i > 0) const Divider(height: 1, color: AppColors.border),
            CashMovementTile(movement: movements[i]),
          ],
        ],
      );
    }

    final viewportHeight = MediaQuery.of(context).size.height;
    final maxHeight = (viewportHeight * 0.28).clamp(_kRowHeight * 3, _kRowHeight * 4.5);

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: ListView.separated(
        padding: EdgeInsets.zero,
        itemCount: movements.length,
        separatorBuilder: (_, __) => const Divider(height: 1, color: AppColors.border),
        itemBuilder: (_, i) => CashMovementTile(movement: movements[i]),
      ),
    );
  }
}
