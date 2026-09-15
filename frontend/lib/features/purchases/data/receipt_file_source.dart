import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfx/pdfx.dart';

import '../domain/receipt_scan.dart';

/// Factura que llega como archivo, no como foto — Tarea 12.2, Q-03.
///
/// Muchas notas de entrega ya son digitales (PDF por WhatsApp o correo). El
/// archivo entra al **mismo pipeline** que la cámara: cada página del PDF se
/// rasteriza on-device a una imagen y de ahí sigue OCR → tabla → mapeo →
/// revisión. Sin cámara no aplica la revisión de condiciones de la toma.
///
/// Contrato aparte de `ReceiptPhotoSource` para que los tests inyecten un
/// doble: el selector de archivos y el render de PDF viven detrás de canales
/// de plataforma.
abstract interface class ReceiptFileSource {
  /// Imágenes listas para el OCR, en orden de página, o `null` si el usuario
  /// canceló.
  Future<ReceiptCapture?> pick();
}

/// Renderiza las páginas de un PDF a imágenes en disco.
abstract interface class PdfPageRasterizer {
  Future<List<String>> rasterize(String pdfPath);
}

class FilePickerReceiptFileSource implements ReceiptFileSource {
  const FilePickerReceiptFileSource({
    this.rasterizer = const PdfxPageRasterizer(),
  });

  final PdfPageRasterizer rasterizer;

  static const _imageExtensions = {'jpg', 'jpeg', 'png', 'webp'};

  @override
  Future<ReceiptCapture?> pick() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png', 'webp'],
      allowMultiple: false,
    );
    final path = result?.files.firstOrNull?.path;
    if (path == null) return null;

    final extension = path.split('.').last.toLowerCase();
    if (_imageExtensions.contains(extension)) {
      return ReceiptCapture.single(path);
    }
    final pages = await rasterizer.rasterize(path);
    if (pages.isEmpty) return null;
    return ReceiptCapture(imagePaths: pages);
  }
}

/// Render con `pdfx` (pdfium en Android, PDFKit en iOS, pdf.js en web) —
/// 100% en el dispositivo, sin servidor (Constitución Art. II / VII).
///
/// Dependencia justificada contra el Art. IV: Flutter no trae decodificador
/// de PDF y ML Kit solo lee imágenes; rasterizar es la única forma de que un
/// PDF pase por el mismo OCR que la foto, y escribir un renderer propio no es
/// razonable.
class PdfxPageRasterizer implements PdfPageRasterizer {
  const PdfxPageRasterizer({
    this.targetWidthPx = 1800,
    this.maxPages = 20,
  });

  /// Ancho de render por página. La letra de una nota de entrega es
  /// pequeña; por debajo de ~1500 px el OCR empieza a confundir cifras.
  final double targetWidthPx;

  /// Tope de páginas para acotar memoria y tiempo en un gama baja. Una nota
  /// de entrega real rara vez pasa de 3.
  final int maxPages;

  @override
  Future<List<String>> rasterize(String pdfPath) async {
    final document = await PdfDocument.openFile(pdfPath);
    try {
      final tempDir = await getTemporaryDirectory();
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final pages = <String>[];
      final count = document.pagesCount.clamp(0, maxPages);

      for (var number = 1; number <= count; number++) {
        final page = await document.getPage(number);
        try {
          final scale = targetWidthPx / page.width;
          final image = await page.render(
            width: page.width * scale,
            height: page.height * scale,
            format: PdfPageImageFormat.jpeg,
            backgroundColor: '#FFFFFF',
          );
          if (image == null) continue;
          final file = File('${tempDir.path}/receipt_${stamp}_p$number.jpg');
          await file.writeAsBytes(image.bytes, flush: true);
          pages.add(file.path);
        } finally {
          await page.close();
        }
      }
      return pages;
    } finally {
      await document.close();
    }
  }
}
