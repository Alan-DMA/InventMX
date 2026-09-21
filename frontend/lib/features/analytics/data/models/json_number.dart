/// Lectura tolerante de números del backend de analítica.
///
/// FastAPI + Pydantic v2 serializan `Decimal` como **string** (`"150.00"`)
/// en las respuestas con `response_model`, y como `num` en las que devuelven
/// un `dict` (`/analytics/commissions`). Estos helpers aceptan ambas formas;
/// leer `as num?` directo dejaría todos los montos en $0.00.
library;

double toDoubleOrZero(dynamic value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? 0.0;
  return 0.0;
}

int toIntOrZero(dynamic value) => toDoubleOrZero(value).round();

DateTime? toDateTimeOrNull(dynamic value) =>
    value is String ? DateTime.tryParse(value) : null;
