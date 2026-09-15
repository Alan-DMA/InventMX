import 'dart:math' as math;
import 'dart:ui';

import 'ocr_helper.dart';

/// Geometría del marco guía de la cámara — Tarea 12.2, Q-01.
///
/// `takePicture()` devuelve el cuadro completo del sensor, y el visor solo
/// muestra la parte que cabe en la pantalla (`BoxFit.cover`). Eduardo lo vio
/// en QA: el OCR leía texto que él no tenía en el encuadre. En vez de
/// recortar y re-codificar la foto (segundos de CPU en un gama baja), se
/// calcula qué región normalizada de la imagen corresponde al marco y se
/// descartan las líneas del OCR que caen fuera — mismo efecto, costo cero.
///
/// Todo lo de aquí es puro para poder probarlo sin cámara.

/// Región normalizada (0..1, en el espacio de la imagen **derecha**, como se
/// ve en pantalla) que ocupa el marco guía de tamaño [frame] centrado en un
/// visor de tamaño [viewport], cuando la vista previa de aspecto
/// [previewAspect] (ancho / alto, ya en la orientación de la pantalla) se
/// dibuja con `BoxFit.cover`.
///
/// [margin] amplía el marco en esa fracción de su tamaño por cada lado: la
/// última columna de la factura suele quedar pegada a la esquina y un
/// recorte exacto la mutila.
Rect viewfinderRegion({
  required Size viewport,
  required Size frame,
  required double previewAspect,
  double margin = 0.06,
}) {
  if (viewport.width <= 0 || viewport.height <= 0 || previewAspect <= 0) {
    return const Rect.fromLTWH(0, 0, 1, 1);
  }

  // La vista previa escalada para cubrir el visor, centrada.
  final previewWidth = previewAspect;
  const previewHeight = 1.0;
  final scale = math.max(
    viewport.width / previewWidth,
    viewport.height / previewHeight,
  );
  final shownWidth = previewWidth * scale;
  final shownHeight = previewHeight * scale;
  final offsetX = (viewport.width - shownWidth) / 2;
  final offsetY = (viewport.height - shownHeight) / 2;

  // El marco, con margen, en coordenadas del visor.
  final frameWidth = frame.width * (1 + 2 * margin);
  final frameHeight = frame.height * (1 + 2 * margin);
  final left = (viewport.width - frameWidth) / 2;
  final top = (viewport.height - frameHeight) / 2;

  double nx(double x) => ((x - offsetX) / shownWidth).clamp(0.0, 1.0);
  double ny(double y) => ((y - offsetY) / shownHeight).clamp(0.0, 1.0);

  return Rect.fromLTRB(
    nx(left),
    ny(top),
    nx(left + frameWidth),
    ny(top + frameHeight),
  );
}

/// Tamaño real del espacio de coordenadas en el que vienen las cajas de
/// [lines].
///
/// `ImageDescriptor` reporta las dimensiones **codificadas** del archivo, sin
/// aplicar la orientación EXIF; ML Kit sí la aplica al leer el archivo. Si
/// alguna caja se sale del tamaño reportado pero cabe con los lados
/// intercambiados, o si la orientación del archivo no coincide con la del
/// visor donde se tomó, las dimensiones van al revés.
Size resolveImageSpace(
  Size decoded,
  List<OcrLine> lines, {
  required bool portraitViewport,
}) {
  final swapped = Size(decoded.height, decoded.width);
  if (lines.isNotEmpty) {
    var fitsDecoded = true;
    var fitsSwapped = true;
    for (final line in lines) {
      final box = line.boundingBox;
      if (box.right > decoded.width + 1 || box.bottom > decoded.height + 1) {
        fitsDecoded = false;
      }
      if (box.right > swapped.width + 1 || box.bottom > swapped.height + 1) {
        fitsSwapped = false;
      }
    }
    if (!fitsDecoded && fitsSwapped) return swapped;
    if (fitsDecoded && !fitsSwapped) return decoded;
  }
  final decodedIsPortrait = decoded.height >= decoded.width;
  return decodedIsPortrait == portraitViewport ? decoded : swapped;
}

/// Líneas del OCR cuyo centro cae dentro de [region] (normalizada) sobre una
/// imagen de tamaño [imageSize]. Si la región es toda la imagen, devuelve la
/// lista sin tocar.
List<OcrLine> clipLinesToRegion(
  List<OcrLine> lines,
  Rect region,
  Size imageSize,
) {
  if (region == const Rect.fromLTWH(0, 0, 1, 1)) return lines;
  if (imageSize.width <= 0 || imageSize.height <= 0) return lines;

  final pixels = Rect.fromLTRB(
    region.left * imageSize.width,
    region.top * imageSize.height,
    region.right * imageSize.width,
    region.bottom * imageSize.height,
  );
  return [
    for (final line in lines)
      if (pixels.contains(line.boundingBox.center)) line,
  ];
}
