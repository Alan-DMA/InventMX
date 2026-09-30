---
version: 1
slug: "ort-presentation-support-home-screen-dart-c596d13c"
primary_target: "frontend/lib/features/support/presentation/support_home_screen.dart"
related_targets: ["frontend/lib/features/auth/presentation/recover_access_screen.dart","frontend/lib/features/auth/presentation/enter_code_screen.dart","frontend/lib/features/auth/presentation/set_new_password_screen.dart","frontend/lib/features/support/presentation/topic_help_screen.dart","frontend/lib/features/support/presentation/case_form_screen.dart","frontend/lib/features/support/presentation/case_detail_screen.dart","frontend/lib/features/saas_admin/presentation/hard_lock_screen.dart","frontend/lib/features/support_access/presentation/support_access_screen.dart"]
---

# Surface brief — Soporte, recuperar acceso y suspensión (Centro de soporte, etapa 2b)

## Scope
Modo: Operate (el artículo de ayuda de cada tema es un momento Read dentro de Operate). Mundo visual establecido de la app del tendero; confirmado por Eduardo el Sep 29 2026 tras `/intent` (P16, P23–P27). Primaria: `support_home_screen.dart`. Relacionadas: recuperar acceso (3 pantallas), tema/formulario/caso, `hard_lock_screen.dart` (variante abuso), `support_access_screen.dart` (oculta hasta la etapa 4).

## Audiencia y tarea
Tendero en el mostrador, Android de gama baja, a veces en crisis: no puede entrar o su tienda está suspendida. Tarea: resolver solo si se puede (ayuda primero) y, si no, contarle a soporte su situación y seguir la respuesta; nunca quedar sin salida.

## Restricciones (de /intent)
Ninguna pantalla sin salida (la de contraseña nueva siempre deja "Cerrar sesión"). Pedir código no revela si el correo existe. "Aún necesito ayuda" siempre visible y con peso (esconderlo sería Obstrucción). Estados escritos, nunca sólo color. La suspensión por abuso nunca ofrece renovar (Bait and Switch). Acceso de soporte: 1 h preseleccionada (default protector), quitarlo es un toque; oculto mientras no tenga efecto. El motivo de la suspensión sólo lo ve el dueño (P8).

## Direction contract

THESIS: La ayuda antes que el formulario, y el caso como una conversación. Refuta el "centro de ayuda" de tarjetas con íconos y el formulario de contacto genérico: aquí los temas son renglones que se leen como una lista de preguntas del propio tendero, cada tema es un artículo breve con la acción que lo resuelve, y lo que se envía se convierte en un caso con número y un hilo donde soporte tiene nombre.

OWN-WORLD: Fondo `darkSlate`, bloques `surface` radio 12 con borde `border`, texto `onSurface`/`onSurfaceMuted`, tipografía del sistema. Esmeralda sólo en la acción del tendero (Enviar a soporte, Entrar, Guardar contraseña, Escribir a soporte, Permitir acceso); rojo para la suspensión; azul cielo para "Respondido" e información; ámbar sólo si algo vence. Código de acceso en mono del sistema porque es un dato que se teclea (grupos de 4, tracking amplio, 28 px). Sin gradientes, sin íconos decorativos en los temas, sin tarjetas anidadas.

STORY: "Busco mi problema en una lista con mis palabras, leo lo que lo arregla y, si no alcanza, lo cuento una vez y alguien con nombre me responde aquí mismo." Cree que soporte existe y responde; hace: lee → toca la acción o "Aún necesito ayuda" → llena lo que el tema pide → ve su caso 1042 esperando → vuelve cuando aparece el punto de respuesta.

FIRST VIEWPORT (390 px): AppBar "Soporte" con un ícono de conversación a la derecha, siempre visible, con insignia azul cielo de respuestas nuevas (tope "9+"); abre "Mis casos" como hoja inferior (resumen escrito de conteos, renglones con número, tema, estado escrito, no leído con punto azul cielo y negritas; cargando, vacío y error se resuelven dentro de la hoja). Revisión de QA de Eduardo, Sep 29: antes era una sección arriba de los temas. El cuerpo abre directo en "¿En qué te ayudamos?" con los temas como renglones de lista (título w600 + resumen de una línea muted + chevron), separados por divisores finos, sin tarjetas.

FORM: Ayuda-primero + hilo (patrón de soporte tipo Steam fijado por Eduardo en P23, no una candidata elegida por mí). Momento distintivo: el caso recién enviado aparece con su número grande y "Esperando a soporte" como primer estado del hilo; la respuesta de soporte entra como mensaje a la izquierda firmado "Soporte Nexus · nombre".

FINISH: unreviewed and undocumented is unfinished; this build ends with the finish review, the verdict, DESIGN.md, and every shipping raster carrying its provenance.

## Pendientes
Panel de casos (etapa 3). Fotos en casos y notificaciones push fuera. Acceso de soporte visible hasta la etapa 4.
