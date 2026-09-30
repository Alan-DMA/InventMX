import 'dart:js_interop';

import 'package:web/web.dart' as web;

const bool canDownloadText = true;

/// Descarga un .txt generado en el navegador; el contenido nunca sale al
/// servidor.
bool downloadText(String fileName, String content) {
  try {
    final blob = web.Blob([content.toJS].toJS, web.BlobPropertyBag(type: 'text/plain;charset=utf-8'));
    final url = web.URL.createObjectURL(blob);
    web.HTMLAnchorElement()
      ..href = url
      ..download = fileName
      ..click();
    web.URL.revokeObjectURL(url);
    return true;
  } catch (_) {
    return false;
  }
}
