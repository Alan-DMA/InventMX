/// Pestaña abierta por el panel (etapa 4). Fuera del navegador no hace nada.
class PendingTab {
  void navigate(String url) {}
  void close() {}
}

/// Abre `url` en una pestaña nueva. Llamar dentro del clic: si espera a la
/// red antes, el navegador la bloquea.
void openInNewTab(String url) {}

/// Abre una pestaña en blanco ya (dentro del clic) para llevarla a su
/// dirección cuando el servidor responda ("Abrir de nuevo").
PendingTab openPendingTab() => PendingTab();
