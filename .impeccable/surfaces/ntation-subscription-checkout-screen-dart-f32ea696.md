---
version: 1
slug: "ntation-subscription-checkout-screen-dart-f32ea696"
primary_target: "frontend/lib/features/saas_admin/presentation/subscription_checkout_screen.dart"
related_targets: ["frontend/lib/features/saas_admin/presentation/founder_admin_dashboard_screen.dart","frontend/lib/features/saas_admin/presentation/subscription_lock_banner.dart","frontend/lib/features/saas_admin/presentation/hard_lock_screen.dart"]
---

# Surface brief — Suscripción, panel de fundadores y morosidad (Tarea 14.2)

## Scope
Modo: Operate. Tres pantallas del tendero/fundador dentro del mundo visual establecido de la app (darkSlate, surface, esmeralda como única acción, ámbar/rojo solo estado, tipografía de sistema). Primaria: `subscription_checkout_screen.dart`. Relacionadas: `founder_admin_dashboard_screen.dart`, `subscription_lock_banner.dart`, `hard_lock_screen.dart`.

## Audiencia y tarea
- Tendero pagando la mensualidad a Nexus desde banca móvil (SPEI) u OXXO; puede estar ya bloqueado y con clientes esperando. Tarea: saber cuánto, cómo y cuándo; avisar que pagó; saber qué pasa después.
- Fundadores conciliando pagos manuales y leyendo MRR/morosos. Tarea: aprobar sin equivocar comercio.

## Restricciones (de /intent)
Sin urgencia fabricada; plan actual siempre el seleccionado; monto exacto una sola vez junto a CLABE y concepto; confirmación con nombre + monto al aprobar/rechazar/suspender; "Ya pagué" siempre devuelve estado visible; Hard Lock explica qué no se pierde y deja cerrar sesión sin culpa.

## Direction contract

THESIS: El ciclo de cobro se ve antes que el cobro. La pantalla refuta la "página de precios" (tres tarjetas grandes de plan liderando) y pone primero el mes como una línea con hoy, vencimiento, solo lectura y bloqueo; el tendero nunca es sorprendido por un estado que ya vio venir.

OWN-WORLD: Fondo `darkSlate`, tarjetas `surface` radio 12 con borde `border`, texto `onSurface`/`onSurfaceMuted`, esmeralda solo en la acción primaria y en el tramo "activo" de la línea; ámbar para solo lectura, rojo para bloqueo, `skyBlue` para chips informativos. Cifras en tabular (`FontFeature.tabularFigures`), monto a 28–32 px w800; CLABE agrupada de cuatro en cuatro en mono del sistema. Sin gradientes, sin glow, sin iconos decorativos: el barcode OXXO es el único elemento "gráfico".

STORY: "Mi plan cuesta esto, estoy aquí en el mes, esto es lo que pasa si no pago y esto es exactamente lo que transfiero." Cree que el sistema es predecible y que su aviso llegó. Hace: copia CLABE/concepto, transfiere, toca "Ya pagué", ve "Recibimos tu aviso".

FIRST VIEWPORT (390 px): AppBar "Mi suscripción"; línea 1: "Plan Comercio · $399.00/mes" + chip de estado. Bloque ciclo (alto ~96 px): barra horizontal del mes con marcadores hoy / vence / +10 y leyenda de dos líneas con fechas exactas de solo lectura y bloqueo. Tarjeta "A pagar": monto 30 px w800 tabular, periodo y vencimiento. Segmento SPEI | OXXO; tarjeta de instrucciones con CLABE, banco, concepto, monto, botón Copiar por dato. Acción primaria esmeralda a todo el ancho "Ya pagué". Debajo del pliegue: "Cambiar plan" (tarjetas compactas, actual marcada) e "Historial".

FORM: Línea del ciclo — candidata 4 de mi lista ordenada (ficha de pago, estado de cuenta, tres pasos, línea del ciclo, ticket, pestañas, aviso de cobro). Seed key b27b1215 (surface, operate); la asignación repartió 4, 3, 7 y Eduardo fijó la 4. Señal de interacción: el mismo `CycleLine` reaparece comprimido en el banner de Soft Lock y a tamaño completo en Hard Lock; al aprobar un pago el tramo activo se extiende animado hasta el nuevo vencimiento.

FINISH: unreviewed and undocumented is unfinished; this build ends with the finish review, the verdict, DESIGN.md, and every shipping raster carrying its provenance.

## Pendientes
OXXO sin proveedor (mock only, estado "próximamente" con backend real). Copy "menos de 24 h" depende de los fundadores.
