---
version: 1
slug: "frontend-lib-main-admin-dart"
primary_target: "frontend/lib/main_admin.dart"
related_targets: ["frontend/lib/admin/shell/admin_shell.dart","frontend/lib/admin/access/presentation/access_screen.dart","frontend/lib/admin/cases/presentation/cases_screen.dart","frontend/lib/admin/today/presentation/today_screen.dart","frontend/lib/admin/audit/presentation/audit_screen.dart","frontend/lib/admin/help_topics/presentation/help_topics_screen.dart"]
---

# Surface brief — Panel de plataforma (Centro de soporte, etapa 3)

## Scope
Modo: Operate. App web aparte (Flutter Web, `lib/main_admin.dart` + `lib/admin/`), laptop primero; en pantalla chica se apila. Superficies: acceso (3a), Casos (3b), Hoy + ficha deslizante (3c), diálogos de acción (3d), Bitácora y Temas de ayuda (3e). Mundo visual heredado de la app del tendero (pinned por Eduardo, P1/P15, brief del Sep 28) + acento de plataforma índigo. Build code-led (sin generación de imágenes en la sesión del Sep 30).

## Audiencia y tarea
Alan y Eduardo: desarrolladores que atienden soporte por ratos, en laptop, a menudo de noche, saliendo de un editor oscuro; interrumpidos. Tarea: vaciar la cola de casos sin olvidar ninguno y actuar sobre una tienda con motivo y sin ver su contenido. Lo que escriben lo lee el tendero tal cual en un Android barato. Rangos: 0–30 casos esperando, cientos en total, mensajes de 1–2000 caracteres; decenas a ~200 tiendas; 5–30 eventos/día.

## Restricciones (de /intent, P28–P34)
Nunca contenido de la tienda: sólo metadatos (P2). Toda acción con motivo ≥ 10 y "Así lo verá la tienda". Enviar principal, Enviar y resolver secundario, cambiar estado en ⋯ (Destructive Defaults). Contadores sólo de lo que espera (Attention Bait). Novedades cada 60 s en silencio; "Hay un mensaje nuevo · Actualizar", nunca recarga bajo los dedos. Borrador guardado en la pestaña; sesión vencida → acceso → misma ruta con el borrador. "Ya los guardé" sin marcar. Bloqueo con hora real; no inventar intentos restantes. Teclado primero: Tab lógico, foco visible índigo, Esc, Ctrl K, J/K, R, Ctrl+Enter. Estados escritos, nunca sólo color.

## Direction contract

THESIS: La cola que se vacía. La bandeja es una cola, no un buzón: la columna que manda es cuánto lleva esperando (neutra; ámbar pasadas 24 h), y se vacía de arriba abajo sin soltar el teclado. Refuta el helpdesk SaaS (tabla densa de etiquetas, prioridades, SLA, avatares, macros) y el admin de tarjetas KPI con gráficas.

OWN-WORLD: El sistema de la app del tendero sin cambios: fondo darkSlate, bloques surface radio 12 con borde fino, tipografía del sistema, cifras tabulares. El índigo #818CF8 es la única firma de plataforma: franja fija, sección activa, Enviar, anillos de foco. Esmeralda ausente salvo dentro de la vista previa "Así lo verá la tienda" de los diálogos de acción (3d), que cita la app del tendero en su propio mundo. Ámbar = vence (sesión, espera > 24 h); rojo = suspensión, cadena rota; azul cielo = información. Sin tarjetas anidadas, gradientes ni íconos decorativos.

STORY: Entro con contraseña y el código de Authenticator; la franja me dice dónde estoy y cuánto me queda. Veo "Casos 3", abro el que más espera, leo el contexto de la tienda (metadatos), lo que contestó en el formulario y la conversación; escribo, envío, y la cola baja a 2.

FIRST VIEWPORT: Bandeja a 1440×900: franja fija ~36 px (PANEL DE PLATAFORMA · operador · sesión restante · Salir); navegación con texto 220 px (Hoy · Casos 3 · Bitácora · Temas de ayuda); lista ~380 px con pestañas Esperando / Respondidos / Resueltos y buscador; el hilo llena el resto: "Caso 1042 · Algo no funciona" + línea de contexto de la tienda, respuestas del formulario, conversación, y abajo fijo el compositor con Enviar índigo. Sin selección: cuántos esperan y el más antiguo señalado. Acceso: columna angosta centrada con la franja desde el primer paso; código en mono 28 px con tracking amplio que se envía solo a los 6 dígitos; 10 códigos en rejilla 2×5 mono con Copiar todos, Descargar .txt y "Ya los guardé".

FORM: Panel = "Feed del día", opción 6 de 7 del concept-seed 09cb4dce (P15, pinned). Casos = cola + conversación fijada por Eduardo con /intent (P28, P31–P34); sin nueva tirada. Firma de interacción: vaciar la cola con el teclado (J/K entre casos, R para responder, Ctrl+Enter para enviar) y ver el contador de Esperando bajar. (Sep 30: Eduardo retiró la burbuja "Así lo leerá" del compositor por redundante.)

FINISH: unreviewed and undocumented is unfinished; this build ends with the finish review, the verdict, DESIGN.md, and every shipping raster carrying its provenance.

## Pendientes
Plantillas de respuesta / macros fuera. Editor de acciones y campos de los temas (PD-07) fuera. Suplantación de sólo lectura: etapa 4. Operadores no están en PRODUCT.md (sólo en este brief) salvo que Eduardo pida sumarlos.
