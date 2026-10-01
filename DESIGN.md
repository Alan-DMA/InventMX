---
name: Nexus (InvenMX)
description: Sistema oscuro del tendero, compartido por la app de la tienda y el Panel de plataforma (acento índigo).
colors:
  dark-slate: "#0F172A"
  surface: "#1E293B"
  surface-variant: "#334155"
  border: "#334155"
  on-surface: "#F1F5F9"
  on-surface-muted: "#94A3B8"
  emerald: "#10B981"
  emerald-dark: "#059669"
  sky-blue: "#38BDF8"
  warning: "#F59E0B"
  error: "#EF4444"
  platform-indigo: "#818CF8"
  platform-indigo-pressed: "#6366F1"
  strip: "#1F2747"
  strip-warning: "#2F2A26"
  danger: "#DC2626"
typography:
  headline:
    fontFamily: "Inter, sans-serif"
    fontSize: "24px"
    fontWeight: 700
  title:
    fontFamily: "Inter, sans-serif"
    fontSize: "20px"
    fontWeight: 700
  title-small:
    fontFamily: "Inter, sans-serif"
    fontSize: "15px"
    fontWeight: 700
  body-large:
    fontFamily: "Inter, sans-serif"
    fontSize: "16px"
    fontWeight: 400
  body:
    fontFamily: "Inter, sans-serif"
    fontSize: "14px"
    fontWeight: 400
    lineHeight: 1.45
  body-small:
    fontFamily: "Inter, sans-serif"
    fontSize: "13px"
    fontWeight: 400
  label:
    fontFamily: "Inter, sans-serif"
    fontSize: "12.5px"
    fontWeight: 600
  strip-label:
    fontFamily: "Inter, sans-serif"
    fontSize: "12px"
    fontWeight: 700
    letterSpacing: "1.1px"
  button:
    fontFamily: "Inter, sans-serif"
    fontSize: "14.5px"
    fontWeight: 600
  mono-code:
    fontFamily: "monospace"
    fontSize: "28px"
    fontWeight: 600
    letterSpacing: "10px"
    fontFeature: "tnum"
rounded:
  skeleton: "6px"
  row: "8px"
  control: "10px"
  field: "12px"
  dialog: "14px"
  card: "16px"
  pill: "999px"
spacing:
  xs: "4px"
  sm: "8px"
  md: "12px"
  lg: "16px"
  xl: "24px"
components:
  button-primary:
    backgroundColor: "{colors.emerald}"
    textColor: "{colors.dark-slate}"
    rounded: "{rounded.field}"
    height: "52px"
    width: "100%"
  button-platform-primary:
    backgroundColor: "{colors.platform-indigo}"
    textColor: "{colors.dark-slate}"
    typography: "{typography.button}"
    rounded: "{rounded.control}"
    padding: "0 20px"
    height: "44px"
  button-platform-primary-pressed:
    backgroundColor: "{colors.platform-indigo-pressed}"
    textColor: "{colors.dark-slate}"
  button-platform-disabled:
    backgroundColor: "{colors.surface-variant}"
    textColor: "{colors.on-surface-muted}"
  button-danger:
    backgroundColor: "{colors.danger}"
    textColor: "#FFFFFF"
    typography: "{typography.button}"
    rounded: "{rounded.control}"
    padding: "0 20px"
    height: "44px"
  button-outlined-panel:
    backgroundColor: "{colors.dark-slate}"
    textColor: "{colors.on-surface}"
    rounded: "{rounded.control}"
    padding: "0 16px"
    height: "44px"
  input-panel:
    backgroundColor: "{colors.dark-slate}"
    textColor: "{colors.on-surface}"
    rounded: "{rounded.field}"
    padding: "14px 16px"
  input-tendero:
    backgroundColor: "{colors.surface-variant}"
    textColor: "{colors.on-surface}"
    rounded: "{rounded.field}"
    padding: "14px 16px"
  card:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.on-surface}"
    rounded: "{rounded.card}"
  status-chip:
    textColor: "{colors.on-surface}"
    typography: "{typography.label}"
    rounded: "{rounded.pill}"
    padding: "4px 10px"
  platform-strip:
    backgroundColor: "{colors.strip}"
    textColor: "{colors.platform-indigo}"
    typography: "{typography.strip-label}"
    height: "40px"
    padding: "0 8px 0 16px"
  platform-strip-warning:
    backgroundColor: "{colors.strip-warning}"
    textColor: "{colors.warning}"
  nav-rail:
    backgroundColor: "{colors.dark-slate}"
    textColor: "{colors.on-surface}"
    width: "220px"
  nav-item-active:
    textColor: "{colors.platform-indigo}"
    rounded: "{rounded.row}"
  tenant-sheet:
    backgroundColor: "{colors.dark-slate}"
    width: "480px"
  action-dialog:
    backgroundColor: "{colors.surface}"
    rounded: "{rounded.dialog}"
    width: "560px"
---

# Design System: Nexus (InvenMX)

## Overview

**Creative North Star: "El mostrador de noche"**

Un solo mundo oscuro, sobrio y de trabajo, compartido por dos superficies: la app del tendero (Android primero, esmeralda como acción) y el Panel de plataforma de los fundadores (Flutter Web, laptop primero, índigo como firma). El fondo es pizarra profunda, los bloques son superficies planas con borde fino y el texto es claro sobre oscuro. Nada decora: la jerarquía la dan el peso tipográfico, el color semántico y el orden, no la profundidad ni los adornos.

El panel no inventa un mundo nuevo: hereda `AppTheme.dark` completo y sólo sustituye el esmeralda por el índigo en los lugares donde el operador actúa o se orienta (franja, sección activa, acción principal, foco, selección de texto, cursor). Así el operador nunca confunde "estoy en el panel" con "estoy dentro de una tienda". Cuando el panel necesita mostrar lo que verá el tendero, lo cita en su propio mundo, con esmeralda incluido, dentro de una vista previa acotada.

El estado siempre se escribe. El color refuerza, nunca informa solo: "Esperando a soporte", "Suspendida por soporte", "1 día espera". Las cifras son medida: tabulares, con espacio que no parte la línea entre cifra y unidad.

**Key Characteristics:**
- Tema oscuro único: pizarra de fondo, superficie para bloques, borde fino en lugar de sombra.
- Un acento de acción por superficie: esmeralda en la app del tendero, índigo en el panel.
- Semáforo de plazo: ámbar = algo vence; rojo = suspensión, cadena rota o irreversible; azul cielo = información.
- Estados escritos con texto, ícono funcional y color, nunca color solo.
- Inter en toda la interfaz; mono del sistema sólo para lo que se teclea o se copia.
- Teclado primero en el panel: foco índigo visible, Esc, Ctrl K, J/K, R, Ctrl+Enter.

## Colors

Pizarra fría de Tailwind (slate) como mundo, con un acento de acción por superficie y un semáforo reservado a significados.

### Primary
- **Esmeralda de mostrador** (emerald): acción primaria y éxito en la app del tendero (botón lleno, contorno, chip seleccionado al 20 %). Su variante **Esmeralda presionado** (emerald-dark) es el estado presionado. En el panel sólo existe dentro de las vistas previas que citan la app del tendero.
- **Índigo de plataforma** (platform-indigo): la única firma del panel. Franja fija, sección activa del riel, pestaña y fila seleccionadas (índigo suave al 16 %), botón Enviar y demás acciones principales, etiqueta flotante, anillo de foco, cursor, selección de texto (al 32 %), casillas marcadas, indicador de progreso, botones de texto. Presionado: **Índigo profundo** (platform-indigo-pressed). Línea de borde de la franja: índigo al 40 %.

### Secondary
- **Azul cielo** (sky-blue): información. Borde de foco y etiqueta flotante en la app del tendero, íconos de acción de la barra superior, estado "Respondido" (le toca al tendero), avisos informativos en la ficha (borde al 35 %).

### Tertiary
- **Ámbar de plazo** (warning): algo vence. Franja con sesión a 10 min o menos, espera de un caso mayor a 24 h, tienda bloqueada por falta de pago o en sólo lectura.
- **Rojo de alarma** (error): suspensión por soporte, cadena de la Bitácora rota, errores de campo; fondos de aviso al 16 %, contornos al 60 %.
- **Rojo de botón destructivo** (danger): fondo de los botones que ejecutan algo irreversible, con texto blanco (4.8:1, AA). Más oscuro que el rojo de alarma precisamente para que el blanco sea legible.

### Neutral
- **Pizarra profunda** (dark-slate): fondo de toda pantalla, barra superior, ficha deslizante y campos del panel; texto sobre botones llenos.
- **Pizarra de bloque** (surface): tarjetas, diálogos, snackbars, burbujas de conversación, esqueletos de carga.
- **Pizarra de control** (surface-variant): relleno de campos y chips del tendero, botón deshabilitado, pulgar de la barra de desplazamiento.
- **Borde fino** (border): el mismo tono que la pizarra de control; divisores, contornos de tarjeta, campo, chip y ficha.
- **Tinta clara** (on-surface): texto principal.
- **Tinta apagada** (on-surface-muted): texto secundario, pistas, metadatos, estado "Resuelto".
- **Franja** (strip) y **Franja en aviso** (strip-warning): fondos de la franja fija; índigo o ámbar al 14 % sobre pizarra profunda.

### Named Rules
**La Regla de la Firma Única.** En el panel, el índigo es la única firma de plataforma: franja, sección activa, acción principal y foco. No se usa para estados de casos ni de tiendas; "Esperando a soporte" es neutro.

**La Regla del Esmeralda Citado.** El esmeralda no aparece en el cromo del panel. Sólo vive dentro de las vistas previas "Así lo verá la tienda" y "Así lo verá el tendero", que citan la app del tendero en su propio mundo.

**La Regla del Semáforo de Plazo.** Ámbar significa que algo vence o espera demasiado; rojo significa suspensión, cadena rota o acción irreversible; azul cielo significa información. Ningún color del semáforo se usa como decoración.

## Typography

**Display Font:** Inter (vía google_fonts)
**Body Font:** Inter
**Label/Mono Font:** mono del sistema (`monospace`) con cifras tabulares, sólo para códigos y claves

**Character:** Una sola sans neutra y legible en teléfono barato y en laptop de noche; la voz la dan los pesos (400 a 700), no una segunda familia.

### Hierarchy
- **Headline** (700, 24px): títulos de pantalla ("Casos", "Hoy") y encabezados grandes del tendero.
- **Title** (700, 20px): nombre de la tienda en la ficha, título del caso ("Caso 1042 · Algo no funciona").
- **Title small** (700, 15px): subtítulos de sección dentro de la ficha y del diálogo.
- **Body large** (400, 16px): campos y texto principal del tendero.
- **Body** (400, 14px, interlineado 1.45): mensajes, explicaciones, errores escritos.
- **Body small** (400, 13px): metadatos, pistas, línea de contexto de la tienda.
- **Label** (600, 12.5px): chips de estado y títulos de bloque ("Así lo verá la tienda").
- **Strip label** (700, 12px, 1.1px de tracking, mayúsculas): exclusivamente "PANEL DE PLATAFORMA" / "PLATAFORMA" en la franja fija.
- **Button** (600, 14.5px en el principal del panel, 14px en contorno y texto; 15px en los botones anchos del tendero).
- **Mono code** (600, 28px, 10px de tracking): el código de Authenticator en el acceso; los códigos de respaldo usan la misma familia a 15–16px.

### Named Rules
**La Regla de la Familia Declarada.** Botones y chips declaran Inter explícitamente (`GoogleFonts.inter`): en Flutter su estilo no hereda la familia del tema y caería en la fuente del motor.

**La Regla de la Cifra Medida.** Esperas, conteos, horas y sesión restante usan cifras tabulares; entre cifra y unidad va un espacio que no parte la línea ("3 h", "27 oct 2026"). El mono se reserva para lo que se teclea o se copia; no es disfraz de "técnico".

## Layout

La app del tendero es móvil primero: una columna, botones de ancho completo de 52px, tarjetas con margen vertical de 4px.

El panel es laptop primero y se apila en pantalla chica:
- **Franja fija** de 40px arriba, siempre visible, desde el primer paso del acceso. Bajo 640px se abrevia a "PLATAFORMA" y oculta el nombre del operador; nunca pierde la palabra "plataforma".
- **Riel de navegación con texto** de 220px a la izquierda, separado por un divisor de 1px; bajo 900px pasa a una fila arriba del contenido.
- **Casos:** cola de 380px (330px bajo 1100px de ancho disponible) + hilo que llena el resto, con el compositor fijo abajo.
- **Ficha de tienda:** panel deslizante de 480px anclado a la derecha; pantalla completa bajo 700px.
- **Diálogo de acción:** ancho máximo 560px.

Ritmo de espaciado sobre múltiplos de 4: 4, 8, 12, 16 y 24px son los pasos reutilizados; rellenos de fila 16×14, de bloque 14×12, de pantalla 24.

**La Regla de la Columna de Espera.** En la cola, la columna que manda va primero y a la izquierda: cuánto lleva esperando (64px, cifras tabulares), neutra y ámbar pasadas 24 h, con la palabra "espera" debajo.

## Elevation & Depth

Sistema plano. Todas las superficies tienen elevación 0 (botones, tarjetas, barra superior, ficha, `scrolledUnderElevation` incluido) y el tinte de superficie de Material 3 está anulado. La profundidad se comunica por tono (pizarra profunda → pizarra de bloque), por un borde fino y, para lo modal, por un velo negro al 54 % detrás de la ficha y del buscador de tiendas.

**La Regla del Velo y el Borde.** Lo que se superpone se separa con velo y borde, nunca con sombra: la ficha deslizante es pizarra profunda con un borde izquierdo fino sobre el velo.

## Shapes

Esquinas suavemente redondeadas, escalonadas por tamaño del objeto: esqueletos 6px; filas de navegación y de cola 8px; botones del panel y avisos internos 10px; campos, bloques y vista previa 12px; diálogos 14px; tarjetas del tendero 16px; chips y píldoras de estado totalmente redondos (999px en el panel, 20px en los chips del tendero). Los contornos son de 1px en el tono de borde; el foco sube a 1.5px en índigo (panel) o azul cielo (tendero).

## Components

### Buttons
Directos y con verbo: la etiqueta dice lo que va a pasar.
- **Shape:** esquinas de 12px y 52px de alto a lo ancho en el tendero; 10px y 44px de alto (40px los de texto) en el panel.
- **Primario del tendero:** esmeralda con texto pizarra profunda, peso 600.
- **Primario del panel:** índigo con texto pizarra profunda, relleno horizontal de 20px. Deshabilitado: pizarra de control con tinta apagada.
- **Destructivo del panel:** rojo de botón destructivo con texto blanco; sólo en la confirmación de algo irreversible (suspender, borrar).
- **Contorno del panel:** borde fino, texto claro, relleno de 16px; para la acción secundaria ("Enviar y resolver", "Reintentar").
- **Texto:** índigo, sin fondo, para acciones terciarias ("Ver ficha de la tienda").

### Chips
- **Estado de caso:** píldora con ícono de 14px + texto 12.5/600 en el color del estado sobre ese color al 14 %. Esperando = claro (ámbar si pasó más de un día); Respondido = azul cielo; Resuelto = apagado, fondo transparente con borde.
- **Filtro (Bitácora):** apagado = contorno fino sobre fondo de la página; encendido = índigo suave con palomita índigo. Inter 13.5/500.

### Cards / Containers
- **Corner Style:** 16px en el tendero; 12px en los bloques del panel.
- **Background:** pizarra de bloque; la vista previa citada va sobre pizarra profunda.
- **Shadow Strategy:** ninguna (ver Elevation & Depth).
- **Border:** 1px en el tono de borde.
- **Internal Padding:** 12–16px.

### Inputs / Fields
- **Style:** relleno lleno, radio 12px, borde fino, relleno 16×14. Tendero sobre pizarra de control; panel sobre pizarra profunda.
- **Focus:** borde de 1.5px en azul cielo (tendero) o índigo (panel); en el panel la etiqueta flotante se declara a 16px para que Material la escale a 12px legibles.
- **Error:** borde rojo de alarma, 1.5px al enfocar, con el mensaje escrito debajo.

### Navigation
- **Riel del panel:** 220px, entradas de texto 14px con ícono de 18px que acompaña al texto. Activa: texto e ícono índigo sobre índigo suave, radio 8px, con contador índigo sólo de lo que espera ("Casos 2"). Bajo 900px, fila horizontal.
- **Barra superior del tendero:** pizarra profunda, título Inter 18/600, íconos de acción en azul cielo.

### Franja de plataforma
Barra fija de 40px: escudo de 16px + "PANEL DE PLATAFORMA" en índigo, operador, sesión restante alineada a la derecha y "Salir". A 10 min del vencimiento pasa a fondo ámbar, texto ámbar y la frase "Tu sesión vence en … · lo que escribas se guarda".

### Fila de cola
Columna de espera a la izquierda (ver Layout), luego tienda en 600, número y tema en tinta apagada, primera línea del mensaje. Seleccionada: fondo índigo suave.

### Diálogo de acción de soporte
Pizarra de bloque, radio 14px, máximo 560px. Orden fijo: explicación → campos → motivo (mínimo 10 caracteres) → vista previa en vivo "Así lo verá la tienda" (texto del servidor sobre pizarra profunda, firma en esmeralda) → botón de confirmación con verbo. Si es irreversible, el botón es rojo destructivo.

### Estados de carga, vacío y error
Carga: bloques del tamaño de lo que viene, en pizarra de bloque, radio 6px, sin girar nada. Error: ícono apagado, mensaje escrito a 14px y "Reintentar" en contorno, en el lugar del contenido. Vacío: una frase que dice qué pasa y qué sigue.

## Do's and Don'ts

### Do:
- **Do** usar el índigo sólo para orientarse y actuar en el panel: franja, sección activa, acción principal, foco, selección.
- **Do** escribir cada estado con palabras; el color y el ícono sólo lo refuerzan.
- **Do** reservar el ámbar para lo que vence (sesión a 10 min o menos, espera mayor a 24 h, bloqueo por pago) y el rojo para suspensión, cadena rota o lo irreversible.
- **Do** confirmar lo irreversible con un botón rojo destructivo (#DC2626) con texto blanco y un verbo en la etiqueta.
- **Do** separar lo superpuesto con velo negro al 54 % y un borde fino.
- **Do** usar cifras tabulares y espacio no separable entre cifra y unidad en esperas, fechas y conteos.
- **Do** declarar Inter en los estilos de botones y chips.

### Don't:
- **Don't** usar esmeralda en el cromo del panel; sólo dentro de las vistas previas que citan la app del tendero.
- **Don't** pintar estados de casos o tiendas con índigo.
- **Don't** anidar tarjetas dentro de tarjetas.
- **Don't** usar gradientes ni sombras de elevación.
- **Don't** poner íconos que no acompañen un texto o no cumplan una función.
- **Don't** usar etiquetas en mayúsculas con tracking fuera de la franja de plataforma.
- **Don't** usar el mono para texto que no se teclea ni se copia.
