import 'package:web/web.dart' as web;

/// Pestaña abierta por el panel (etapa 4): se abre en blanco dentro del clic
/// y se lleva a su dirección después, para que el navegador no la bloquee.
class PendingTab {
  PendingTab(this._window);
  final web.Window? _window;

  void navigate(String url) {
    final w = _window;
    if (w == null) {
      web.window.open(url, '_blank');
      return;
    }
    w.location.href = url;
  }

  void close() => _window?.close();
}

void openInNewTab(String url) => web.window.open(url, '_blank');

PendingTab openPendingTab() => PendingTab(web.window.open('', '_blank'));
