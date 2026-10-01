import 'package:flutter_riverpod/flutter_riverpod.dart';

/// `true` sólo dentro de la pestaña de soporte (`main_support.dart`,
/// Centro de soporte etapa 4): la app del tendero abierta por un operador en
/// sólo lectura. Las piezas que no tienen sentido ahí (cerrar sesión, canal
/// en vivo de pedidos, avisos de soporte) lo consultan.
final supportModeProvider = Provider<bool>((_) => false);
