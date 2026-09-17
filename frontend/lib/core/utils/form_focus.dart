import 'package:flutter/material.dart';

/// Tras un `validate()` fallido, lleva el foco y el scroll al **primer**
/// campo inválido en orden de jerarquía (el más arriba en el árbol).
///
/// Regla de producto (QA de Eduardo, Sep 2026): un error de validación que
/// queda fuera de pantalla hace creer que "el botón no sirve". El formulario
/// debe subir a mostrarlo; si hay varios, se muestra el primero.
///
/// Devuelve `true` si encontró y enfocó un campo inválido.
bool focusFirstInvalidField(GlobalKey<FormState> formKey) {
  final formContext = formKey.currentContext;
  if (formContext == null) return false;

  FormFieldState<dynamic>? first;
  void visit(Element element) {
    if (first != null) return;
    if (element is StatefulElement) {
      final state = element.state;
      if (state is FormFieldState<dynamic> && state.hasError) {
        first = state;
        return;
      }
    }
    element.visitChildElements(visit);
  }

  formContext.visitChildElements(visit);
  final field = first;
  if (field == null) return false;

  // Scroll primero (el campo puede estar bajo el pliegue de un sheet)...
  Scrollable.ensureVisible(
    field.context,
    alignment: 0.15,
    duration: const Duration(milliseconds: 250),
    curve: Curves.easeOut,
  );

  // ...y luego el teclado, si el campo es de texto.
  EditableTextState? editable;
  void findEditable(Element element) {
    if (editable != null) return;
    if (element is StatefulElement && element.state is EditableTextState) {
      editable = element.state as EditableTextState;
      return;
    }
    element.visitChildElements(findEditable);
  }

  field.context.visitChildElements(findEditable);
  editable?.requestKeyboard();
  return true;
}
