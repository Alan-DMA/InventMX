---
version: 1
slug: "frontend-lib-main-support-dart"
primary_target: "frontend/lib/main_support.dart"
related_targets: ["frontend/lib/features/support_access/presentation/support_access_screen.dart"]
---

# Surface brief — Modo soporte (Centro de soporte, etapa 4)

## Scope
Modo: Operate. Entrada aparte `lib/main_support.dart`: la app real del tendero en una pestaña del navegador, en sólo lectura, con el permiso del dueño (P37). Se abre sólo con un enlace de un uso del panel; no tiene pantalla de inicio de sesión. Incluye los estados de entrada (abriendo, enlace inválido o vencido) y de salida ("El acceso terminó"). En la app del tendero (misma etapa): Acceso de soporte visible en ☰ · Administración con la tarjeta "Soporte está viendo tu tienda ahora" y "Quién entró", y el aviso en Avisos (P41). Build code-led.

## Audiencia y tarea
Operador (Alan o Eduardo) en laptop, saliendo del panel índigo, con un caso abierto: mirar lo que ve el dueño para entender su problema, sin tocar nada y sin olvidar que está dentro de la tienda de otro. Dueño (Android barato, de pie): enterarse de que soporte entró, para qué y qué miró, y poder cortarlo de un toque.

## Restricciones (P37–P42)
La app se ve idéntica a la del dueño: los botones que escriben no se apagan; al tocarlos el servidor rechaza y se dice "Modo soporte: no se guardó nada" (P40). La pestaña se abre con un clic explícito "Abrir la tienda ↗" (P42). El tiempo es el del servidor. Al terminar se borra lo guardado en el navegador. Sin "Cerrar sesión": su lugar lo toma "Terminar".

## Direction contract

THESIS: Dentro, pero de visita. La app del tendero intacta bajo una franja índigo que nunca se va: el operador ve exactamente lo que ve el dueño y en todo momento sabe que es una visita con reloj. Refuta el "modo administrador" que recolorea o recorta la app y el banner de cortesía que se cierra con una X.

OWN-WORLD: El mundo del tendero sin tocar (darkSlate, esmeralda como acción de la app, Inter, radios de DESIGN.md) más un solo objeto de plataforma: la franja fija de 40 px del panel (fondo strip, texto e ícono índigo #818CF8, borde inferior índigo al 40 %), que pasa a ámbar a 5 min. Las pantallas de entrada y salida viven en el mundo del panel: pizarra profunda, una columna angosta centrada, índigo como acción. Rojo sólo si algo falló.

STORY: Abro el enlace, la franja aparece antes que la tienda; veo "MODO SOPORTE · SÓLO LECTURA · Abarrotes Rosy · quedan 30 min". Recorro Inventario como lo vería Doña Rosy, encuentro el producto mal capturado, termino; la pantalla me dice que terminó y que ya puedo cerrar la pestaña. El dueño recibe un aviso con mi nombre y el motivo, y luego ve que miré Inventario.

FIRST VIEWPORT: Laptop 1440×900: franja fija de 40 px arriba, a todo lo ancho: escudo 16 px + "MODO SOPORTE · SÓLO LECTURA" en índigo, nombre de la tienda en tinta clara, a la derecha "quedan 24 min" en cifras tabulares, "Seguir 30 min más" (sólo con ≤ 10 min) y "Terminar" como botón de contorno. Debajo, la app del tendero en una columna de teléfono centrada (máx. 480 px) sobre pizarra profunda, para que se vea como en el Android del dueño. En < 640 px la franja se compacta: "SOPORTE · SÓLO LECTURA · 24 min · Terminar"; con "+30 min" visible, "SOPORTE · 4 min · +30 min · Terminar"; un rechazo reemplaza al título por "No se guardó nada" mientras dura.

FORM: Extensión del mundo establecido (franja de plataforma de DESIGN.md + app del tendero), no una superficie con estructura libre: por eso sin tirada de concept-seed. new-work §3: "Never run the script for a local extension or a precisely specified narrow request; shape those directly" — y esta superficie quedó especificada por las decisiones de Eduardo. La estructura la fijó Eduardo con /intent al aprobar P37 ("App real en pestaña"), P40, P41 y P42 ("Botón 'Abrir la tienda ↗'"); no hay seed key. Firma de interacción: la franja cuenta el tiempo real del servidor y, al acabarse o al retirarse el permiso, la tienda se retira bajo ella y queda "El acceso terminó · el dueño retiró el permiso" con la pestaña ya limpia.

FINISH: unreviewed and undocumented is unfinished; this build ends with the finish review, the verdict, DESIGN.md, and every shipping raster carrying its provenance.

## Pendientes
Las secciones que ve el dueño salen de los datos que la app pidió: Inicio pide resúmenes de varias secciones. Cámara, escáner y voz no se ofrecen en modo soporte.
