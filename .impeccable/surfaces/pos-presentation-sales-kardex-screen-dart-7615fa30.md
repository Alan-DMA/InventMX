---
version: 1
slug: "pos-presentation-sales-kardex-screen-dart-7615fa30"
primary_target: "frontend/lib/features/sales_pos/presentation/sales_kardex_screen.dart"
related_targets: ["frontend/lib/features/sales_pos/presentation/sale_receipt_screen.dart","frontend/lib/features/sales_pos/presentation/widgets/refund_sale_modal.dart","frontend/lib/features/analytics/presentation/analytics_dashboard_screen.dart","frontend/lib/features/sales_pos/presentation/checkout_screen.dart"]
---

# Surface brief — Kardex de ventas y consulta de ticket (Fase 2, Sep 2026)

## Scope
Modo: Operate. Expansión del mundo visual establecido (darkSlate, `surface` r12 con borde, esmeralda sólo en la acción primaria, skyBlue en lo informativo/bancario, error en lo destructivo-pero-legítimo, cifras tabulares, Inter). Primaria: `sales_kardex_screen.dart` (`/ventas/historial`). Relacionadas: `sale_receipt_screen.dart` (modo consulta `isLookup` + `SaleLookupScreen` en `/ventas/historial/:id` + acciones de reembolso), `refund_sale_modal.dart` (hoja de reembolso), `analytics_dashboard_screen.dart` (enlace "Ver ventas" en la sección Ventas), `checkout_screen.dart` (icono de historial en el AppBar del POS).

## Audiencia y tarea
- Cajero, hace 5 min: el cliente quiere su ticket por WhatsApp o reclama el cobro. Reconoce la venta por **hora + total**, no por folio. Detalle = ticket con compartir.
- Dueño, fin del día: qué vendió cada quien y cuánto entró por cada forma de pago. Filtra por cajero/pago y necesita ver **cuántas y cuánto suman**.
- Dueño/Encargado (permiso `ventas.eliminar`, no el Cajero): cliente devuelve un producto, error de cobro, venta duplicada — necesita reembolsar total o parcialmente sin salir del ticket.

## Restricciones (de /intent — `/intent:fortify`, catálogo de escenarios de venta, Sep 2026)
Hermano del kardex de inventario (`KardexBottomSheet`): misma anatomía (embudo, panel colapsable, scroll infinito al 80 %, skeleton, vacío, error) pero como página, porque se entra al detalle y se vuelve. Separadores de día como punto de parada visual del scroll infinito. Vacíos con salida. Ticket de consulta sin celebración: nada de "¡Venta registrada!" ni "Nueva Venta"; título = folio.

**Reembolso** (una venta admite un solo evento, total o parcial): botón sólo en modo consulta, gateado por `ventas.eliminar` (ya en `seed.py`, ya asignado a Dueño/Encargado). La hoja pide ítems + cantidad, motivo obligatorio y un switch explícito "¿regresa al inventario?" — no se asume automáticamente. El total histórico del renglón **no se toca** (kardex = registro del hecho); lo neto (bruto − reembolsos) vive en la franja de resumen, en "Vendido hoy" y en Reportes. Una venta reembolsada sigue visible (transparencia), atenuada y con etiqueta, sin la acción disponible. `/cancel` no se ofrece: sin un estado "en construcción" en el POS actual, no tiene ventana de uso real.

## Direction contract

THESIS: La venta se reconoce por cuándo y cuánto; el reembolso se reconoce por lo que se pierde, no lo que se gana — vocabulario de error (rojo), nunca el vocabulario de éxito (esmeralda) de "Cobrar"/"Nueva Venta".

OWN-WORLD: Icono de forma de pago en caja 36 dp con tinte al 12 %. Encabezados de día en versalitas apagadas. Fila de reembolso: contador `− N +` acotado a la cantidad original, tinte rojo al 6-15 % cuando hay selección. Botón "Reembolsar" = `OutlinedButton` rojo en el ticket (nunca filled — no es la acción primaria del ticket); dentro de la hoja, el CTA final sí es filled rojo (es la única acción posible ahí). Venta reembolsada: `Opacity` 0.55 en el renglón del kardex + total tachado + pill "Reembolsada"; en el ticket, un banner rojo con fecha y motivo reemplaza el botón.

FIRST VIEWPORT (390 px): kardex sin cambios de Fase 2. Ticket en consulta: tarjeta + WhatsApp/Imprimir + (si aplica) "Reembolsar" a todo lo ancho.

FORM: `RefundSaleModal` — `DraggableScrollableSheet` (igual patrón que `PaymentModal`/`KardexBottomSheet`): lista de ítems con contador, "Reembolsar todo" como atajo, motivo, switch, total en vivo. **El error de envío vive en el pie, no en la lista** — un hallazgo real de la primera pasada: un error dentro del `ListView` puede quedar fuera de la porción visible del sheet si el contenido ya llena el alto inicial, y el cajero nunca lo ve sin desplazarse a propósito.

FINISH: revisado en capturas `.impeccable/review/refund_*.png` (mismo arnés temporal Roboto-como-Inter). Detector mecánico sin hallazgos. Corrección aplicada en la primera pasada: banner de error movido de la lista al pie fijo del modal.

## Pendientes
Backend (Alan, 8.1): `GET /sales`, `GET /sales/{id}`, `POST /sales/{id}/refund` (ya en el yaml, sin implementar); propuesta de `total_amount_mxn` neto en el listado. `cashier_id` real depende de N-04. Comisiones (`commissions_repository.dart`) no descuenta reembolsos todavía — pendiente de decidir con Eduardo si un reembolso debe ajustar la comisión ya calculada.
