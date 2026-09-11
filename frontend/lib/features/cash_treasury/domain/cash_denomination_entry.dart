import 'package:equatable/equatable.dart';
import 'banxico_denomination.dart';

/// Fila local del wizard de arqueo: una denominación con la cantidad de
/// piezas contadas. Vive únicamente en el estado del wizard (flujo
/// transaccional efímero) hasta que se confirma el cierre — ver
/// `BanxicoCount` para la agregación final que viaja al repositorio.
class CashDenominationEntry extends Equatable {
  const CashDenominationEntry({
    required this.denomination,
    required this.quantity,
  });

  final BanxicoDenomination denomination;
  final int quantity;

  double get subtotalMxn => denomination.value * quantity;

  CashDenominationEntry copyWith({int? quantity}) => CashDenominationEntry(
        denomination: denomination,
        quantity: quantity ?? this.quantity,
      );

  @override
  List<Object?> get props => [denomination, quantity];
}
