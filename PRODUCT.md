# Product

<!-- impeccable:product-schema 1 -->

## Platform

web

## Users

- **Tendero / dueño de tiendita de abarrotes en México** (usuario principal de la app Nexus/InvenMX). Opera de pie, con prisa, frente al cliente o al repartidor, en un teléfono Android de gama baja. Su trabajo: vender, cobrar, saber qué tiene y qué le falta, sin capacitación previa.
- **Cliente final de la tiendita** (usuario de la vitrina pública). Recibe un enlace por WhatsApp o escanea un QR en el mostrador. Abre el catálogo en su celular, muchas veces con datos móviles y a plena luz; no tiene cuenta ni la quiere. Su trabajo: ver precios actualizados, armar su pedido y mandarlo al WhatsApp de la tienda en menos de un minuto.

## Product Purpose

Nexus v3.0 (InvenMX) es el sistema operativo del pequeño comercio mexicano: inventario, punto de venta, caja, compras y catálogo digital en una sola app, en pesos mexicanos, pensada para tienditas que hoy operan con libreta y WhatsApp. Éxito = el tendero registra sus productos en minutos, vende sin fricción y recibe pedidos estructurados sin pagar comisiones a apps de delivery.

## Positioning

Digitaliza la tiendita **a través de WhatsApp**, no en contra de él: el catálogo público genera pedidos estructurados que llegan al WhatsApp del negocio (RF-23/RF-24), sin cuentas para el cliente, sin comisiones y sincronizado en tiempo real con el inventario del tendero (RF-25). Motor híbrido de catálogo semilla EAN-13 + red comunitaria (Constitución 7.5) para dar de alta productos en < 1 ms.

## Operating Context

- App del tendero: Flutter (Android primero, también web), Feature-First + Riverpod, tema oscuro `darkSlate`, hoy corriendo sobre repositorios mock mientras el backend FastAPI se conecta.
- Vitrina pública: ruta web `/tienda/{slug}` (RF-23, Constitución 7.4) servida por el mismo build de Flutter Web; el backend expone `GET /public/catalog/{slug}` y `POST /public/catalog/{slug}/build-whatsapp-order`, que arma el mensaje y el enlace `wa.me` (formato con emojis, negritas y desglose en $ MXN).
- Escena del cliente: teléfono barato, sol, datos móviles, un pulgar. Escena del tendero al compartir: mostrador (QR impreso), estados de WhatsApp/Facebook.
- Documentación que gobierna: `Constitucion Nexus v1-0.md` (máxima autoridad), `Documento Maestro Nexus v3-0.md` (RF-XX), `docs/architecture/registro_implementacion.md` (estado real y decisiones).

## Capabilities and Constraints

- Precios siempre en pesos mexicanos con dos decimales (`$ MXN`).
- Cero dependencias innecesarias (Constitución Art. IV); preferir soluciones nativas de Flutter.
- Sin login para el cliente final; sin recolección de datos más allá de lo que él mismo escribe en su pedido (nombre, teléfono opcional, dirección si pide a domicilio).
- Reglas de la tienda que la vitrina debe respetar: catálogo activable/desactivable, pedido mínimo, costo de envío, entrega a domicilio / recoger en tienda habilitables, productos agotados visibles pero no pedibles.
- Terminología: "tiendita", "tendero", "pedido", "recoger en tienda", "a domicilio", "envío". Nunca "checkout", "carrito de compras" en copy (sí "tu pedido").
- Limitación conocida: Flutter Web no carga en < 1 s con datos móviles (bundle inicial de varios MB); la vitrina compensa con skeleton inmediato y cero dependencias extra. Registrado en la bitácora.
- Fotos de producto: el inventario mock no las tiene (D4, Sep 2026): la vitrina usa un placeholder por categoría hasta que el backend las entregue.

## Brand Commitments

- Nombre del producto: Nexus (repo InvenMX); pie del mensaje de pedido: "Pedido generado vía InventMX Catálogo Digital" (texto fijado por el backend).
- Color de marca de la app del tendero: esmeralda `#10B981` (acción primaria) sobre `darkSlate #0F172A`.
- **Vitrina pública (decisión D1 de Eduardo, Sep 2026):** tema claro propio, distinto del oscuro del tendero; tipografía del sistema; rápida, honesta, sin decoración. El esmeralda puede reaparecer como acento de marca.

## Evidence on Hand

- Productos reales de ejemplo: `frontend/lib/features/inventory/data/inventory_mock_data.dart` (16 productos de abarrotes con precio, stock y categoría — Bebidas, Botanas, Panadería, Lácteos, Abarrotes, Limpieza, Combos).
- Formato real del mensaje de pedido: `backend/app/modules/whatsapp_catalog/services/public_catalog_service.py`.
- No hay fotos de producto, logotipos de tiendas ni testimonios; no inventarlos.

## Product Principles

1. **Lo que el tendero ve es lo que el cliente ve.** El catálogo público refleja el inventario sin pasos intermedios.
2. **WhatsApp es el canal, no el enemigo.** Todo termina en un mensaje que el tendero ya sabe leer.
3. **Cero fricción para el cliente.** Sin cuenta, sin app, sin más campos que los que el pedido necesita.
4. **Honestidad de estado.** Agotado se ve agotado; catálogo apagado se dice; sin red se explica y se puede reintentar.
5. **Ligero por respeto.** Datos móviles y teléfonos baratos son la norma, no el caso límite.

## Accessibility & Inclusion

Contraste legible bajo el sol (texto principal sobre blanco ≥ 7:1 en la vitrina), objetivos táctiles de 44 px, sin dependencia del color para el estado (agotado se escribe), textos escalables con el sistema.
