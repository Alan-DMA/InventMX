---
version: 1
slug: "g-presentation-public-catalog-screen-dart-3f0ee5dd"
primary_target: "frontend/lib/features/whatsapp_catalog/presentation/public_catalog_screen.dart"
related_targets: ["frontend/lib/features/whatsapp_catalog/presentation/widgets/order_bar.dart","frontend/lib/features/whatsapp_catalog/presentation/widgets/order_sheet.dart"]
---

# Vitrina pública — `/tienda/{slug}` (Tarea 13.2.1 / 13.2.2)

## Scope and visitor mode

Operate. Cliente final de una tiendita: abre el enlace desde WhatsApp o un QR, ve precios, arma su pedido y lo envía al WhatsApp de la tienda. Sin cuenta. Incluye la vitrina, la barra de pedido flotante y el sheet de envío. El panel del tendero ("Mi catálogo") es otra superficie dentro de la app oscura y hereda ese mundo.

## Audience, job, task, content, constraints

- Cliente en teléfono Android barato, datos móviles, luz de día. Un pulgar.
- Tarea: encontrar 3–10 productos, ajustar cantidades, enviar el pedido en < 1 minuto.
- Contenido real: nombre, categoría, precio $ MXN, disponibilidad; datos de la tienda (nombre, horario, WhatsApp, pedido mínimo, envío, entrega/recoger). Sin fotos hoy (placeholder por categoría, D4).
- Restricciones confirmadas por Eduardo: nunca tapar precio ni el botón de pedir; no parecer app de delivery (sin banners, promos, cuenta); no pedir datos de más (solo nombre; teléfono y dirección cuando aplican); nunca ocultar el estado real (agotado, catálogo apagado, sin red).
- Decisión: **canon** (catálogo estándar) al nivel de la página de tienda de Rappi / Uber Eats. Seed key 8add2b3d, kind canon.

## Direction contract

THESIS: La página de tienda que todo cliente mexicano ya sabe usar (grid de productos, "+", barra inferior con el total), pero sin la capa comercial de las apps de delivery: cero promos, cero cuenta, cero comisión — solo la tiendita y sus precios. Se rehúsa la vitrina "editorial" de tienda en línea y el tablero oscuro del tendero.

OWN-WORLD: Blanco puro de fondo, tinta `#111827` para nombres y precios, gris `#6B7280` para secundario, divisores `#E5E7EB`. Un acento: esmeralda `#059669` (más oscuro que el de la app para 4.5:1 sobre blanco) en "+", stepper, barra de pedido y CTA. Tipografía del sistema; precios en semibold con cifras tabulares. Tarjetas de producto sin sombra: borde de 1 px y radio 12; el placeholder de foto es un bloque tintado por categoría (`#F3F4F6` + ícono de línea de Material), nunca un ícono en tarjeta vacía. Chips de categoría en píldora con estado activo esmeralda sólido. Barra de pedido: superficie esmeralda sólida, texto blanco, sombra suave con desplazamiento.

STORY: "Aquí está lo que la tienda tiene, a su precio de hoy; agrego lo que quiero y se lo mando por WhatsApp como siempre." El cliente entiende en el primer segundo que es la tienda de la esquina, no un marketplace.

FIRST VIEWPORT: Cabecera compacta: nombre de la tienda (título), horario y "Pedidos por WhatsApp" con el número; debajo, buscador de altura 44 px y fila de chips de categoría. Inmediatamente el grid 2 columnas (3 en ≥ 600 px): placeholder/foto 1:1 arriba, nombre en 2 líneas máx., precio, "+" esmeralda de 40 px en la esquina. Agotado: tarjeta atenuada, etiqueta "Agotado" en texto, sin "+". La barra de pedido aparece al primer "+".

SIGNATURE: El "+" se convierte en stepper `− 2 +` dentro de la misma esquina, y la barra inferior crece con el conteo y el total; al abrirla, el sheet "Tu pedido" muestra los renglones, el total desglosado y, antes de enviar, "Así le llegará a la tienda" con la vista previa del mensaje real de WhatsApp.

RISK: Sin fotos, un grid de placeholders puede verse vacío; se mitiga con placeholders por categoría con color e ícono consistentes y con el precio como protagonista tipográfico. Cuando lleguen las fotos ocupan el mismo hueco 1:1.

## Unresolved

- Dominio real del enlace público (`CATALOG_BASE_URL`).
- Fotos de producto (backend).
