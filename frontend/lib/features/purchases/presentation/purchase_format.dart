/// Formato de fecha compartido del módulo de Compras.
///
/// El año sólo aparece cuando no es el actual: una orden de esta semana se lee
/// "15 sep" y deja ancho para lo que la acompaña (la etiqueta de la tarjeta,
/// el renglón de vencimiento de una CxP). Vive aquí porque ya iba por su
/// tercera copia — tarjeta de orden, tarjeta de CxP y detalle de orden.
library;

const _months = [
  'ene', 'feb', 'mar', 'abr', 'may', 'jun', //
  'jul', 'ago', 'sep', 'oct', 'nov', 'dic',
];

String formatPurchaseDate(DateTime date) {
  final short = '${date.day} ${_months[date.month - 1]}';
  return date.year == DateTime.now().year ? short : '$short ${date.year}';
}
