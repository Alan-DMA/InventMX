/// Fechas y esperas como las lee el operador (hora de su equipo).
library;

const _months = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];

String _two(int n) => n.toString().padLeft(2, '0');

/// Espacio que no parte la línea: "3 h" o "27 oct 2026" nunca quedan
/// separados en dos renglones.
const nbsp = '\u00A0';

/// "30 sep · 14:05" (el mismo formato que ve el tendero en su caso).
String adminMoment(DateTime d) {
  final l = d.toLocal();
  return '${l.day} ${_months[l.month - 1]} · ${_two(l.hour)}:${_two(l.minute)}';
}

/// "27 oct 2026".
String adminDate(DateTime d) {
  final l = d.toLocal();
  return '${l.day}$nbsp${_months[l.month - 1]}$nbsp${l.year}';
}

/// Duración corta: "20 min", "3 h", "1 día", "4 días" (con [nbsp]). Menos de un minuto:
/// "un momento".
String adminSpan(Duration span) {
  if (span.inMinutes < 1) return 'un momento';
  if (span.inMinutes < 60) return '${span.inMinutes}${nbsp}min';
  if (span.inHours < 24) return '${span.inHours}${nbsp}h';
  final days = span.inDays;
  return days == 1 ? '1${nbsp}día' : '$days${nbsp}días';
}

/// "hace 3 h" / "hace un momento".
String adminAgo(DateTime then, DateTime now) {
  final span = now.difference(then);
  return span.inMinutes < 1 ? 'hace un momento' : 'hace ${adminSpan(span)}';
}
