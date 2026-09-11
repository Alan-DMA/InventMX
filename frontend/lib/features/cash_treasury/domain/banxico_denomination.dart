import 'package:equatable/equatable.dart';

/// Cono monetario oficial del Banco de México (Banxico) — Constitución
/// Art. VII (7.2), Doc. Maestro RF-18/RF-19.
enum DenominationKind {
  bill,
  coin;

  String get label => switch (this) {
        DenominationKind.bill => 'Billete',
        DenominationKind.coin => 'Moneda',
      };
}

/// Una denominación física oficial (ej. billete de $50, moneda de $0.50).
///
/// `apiKey` es la clave exacta que espera `BanxicoDenominations` en
/// `docs/api/components.yaml` (`bills_1000` ... `coins_050`).
class BanxicoDenomination extends Equatable {
  const BanxicoDenomination({
    required this.value,
    required this.kind,
    required this.apiKey,
  });

  final double value;
  final DenominationKind kind;
  final String apiKey;

  String get displayValue =>
      value == value.roundToDouble() ? value.toStringAsFixed(0) : value.toStringAsFixed(2);

  @override
  List<Object?> get props => [value, kind, apiKey];
}

/// Catálogo fijo del cono monetario Banxico (6 billetes + 6 monedas).
abstract final class BanxicoCatalog {
  static const bills = [
    BanxicoDenomination(value: 1000, kind: DenominationKind.bill, apiKey: 'bills_1000'),
    BanxicoDenomination(value: 500, kind: DenominationKind.bill, apiKey: 'bills_500'),
    BanxicoDenomination(value: 200, kind: DenominationKind.bill, apiKey: 'bills_200'),
    BanxicoDenomination(value: 100, kind: DenominationKind.bill, apiKey: 'bills_100'),
    BanxicoDenomination(value: 50, kind: DenominationKind.bill, apiKey: 'bills_50'),
    BanxicoDenomination(value: 20, kind: DenominationKind.bill, apiKey: 'bills_20'),
  ];

  static const coins = [
    BanxicoDenomination(value: 20, kind: DenominationKind.coin, apiKey: 'coins_20'),
    BanxicoDenomination(value: 10, kind: DenominationKind.coin, apiKey: 'coins_10'),
    BanxicoDenomination(value: 5, kind: DenominationKind.coin, apiKey: 'coins_5'),
    BanxicoDenomination(value: 2, kind: DenominationKind.coin, apiKey: 'coins_2'),
    BanxicoDenomination(value: 1, kind: DenominationKind.coin, apiKey: 'coins_1'),
    BanxicoDenomination(value: 0.5, kind: DenominationKind.coin, apiKey: 'coins_050'),
  ];

  static List<BanxicoDenomination> byKind(DenominationKind kind) =>
      kind == DenominationKind.bill ? bills : coins;

  static const all = [...bills, ...coins];

  BanxicoCatalog._();
}

/// Conteo físico de piezas por denominación — payload de
/// `opening_denominations` / `physical_denominations`.
class BanxicoCount extends Equatable {
  const BanxicoCount(this.piecesByApiKey);

  static const empty = BanxicoCount({});

  /// apiKey → cantidad de piezas.
  final Map<String, int> piecesByApiKey;

  double get totalMxn => BanxicoCatalog.all.fold(0.0, (sum, d) {
        final qty = piecesByApiKey[d.apiKey] ?? 0;
        return sum + (qty * d.value);
      });

  /// Serializa las 12 claves exactas del schema `BanxicoDenominations`,
  /// incluyendo ceros para las denominaciones no contadas.
  Map<String, int> toJson() => {
        for (final d in BanxicoCatalog.all) d.apiKey: piecesByApiKey[d.apiKey] ?? 0,
      };

  @override
  List<Object?> get props => [piecesByApiKey];
}
