import 'dart:io';
import 'dart:ui' as ui;

/// Dimensiones codificadas de una imagen en disco, sin decodificar píxeles.
///
/// `ImageDescriptor` lee solo la cabecera del archivo: cuesta milisegundos
/// aunque la foto sea de 12 MP. No aplica la orientación EXIF — ver
/// `resolveImageSpace` en `viewfinder_region.dart`.
///
/// Devuelve `null` ante cualquier fallo: quien llama debe seguir sin
/// recorte, nunca bloquear el flujo por esto.
Future<ui.Size?> readImageSize(String path) async {
  try {
    // Sin archivo no hay cabecera que leer — y la llamada al motor con una
    // ruta inexistente no resuelve en `flutter test`.
    if (!File(path).existsSync()) return null;
    final buffer = await ui.ImmutableBuffer.fromFilePath(path);
    try {
      final descriptor = await ui.ImageDescriptor.encoded(buffer);
      try {
        return ui.Size(
          descriptor.width.toDouble(),
          descriptor.height.toDouble(),
        );
      } finally {
        descriptor.dispose();
      }
    } finally {
      buffer.dispose();
    }
  } catch (_) {
    return null;
  }
}
