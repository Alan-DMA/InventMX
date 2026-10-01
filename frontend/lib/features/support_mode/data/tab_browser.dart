import 'tab_browser_memory.dart' if (dart.library.js_interop) 'tab_browser_web.dart' as impl;

/// Lo que la pestaña de soporte necesita del navegador (etapa 4, P39): el
/// token vive en `sessionStorage` (sobrevive a F5, muere con la pestaña), el
/// código del enlace se lee una vez y se borra de la barra de direcciones, y
/// al terminar no queda nada de la tienda guardado en el navegador.
abstract class TabBrowser {
  String? readToken();
  void writeToken(String token);

  /// El código del enlace (`?c=`), quitándolo de la barra de direcciones y del historial.
  String? takeLinkCode();

  /// Borra `sessionStorage`, `localStorage` y las bases de IndexedDB del origen.
  Future<void> wipe();

  /// Intenta cerrar la pestaña (sólo funciona si la abrió el panel).
  void closeTab();
}

TabBrowser createTabBrowser() => impl.createTabBrowser();

/// En memoria: tests y cualquier plataforma que no sea web.
class MemoryTabBrowser implements TabBrowser {
  MemoryTabBrowser({this.linkCode});

  String? linkCode;
  String? token;
  bool wiped = false;
  bool closed = false;

  @override
  String? readToken() => token;

  @override
  void writeToken(String value) => token = value;

  @override
  String? takeLinkCode() {
    final code = linkCode;
    linkCode = null;
    return code;
  }

  @override
  Future<void> wipe() async {
    token = null;
    wiped = true;
  }

  @override
  void closeTab() => closed = true;
}
