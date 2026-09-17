---
version: 1
slug: "sentation-analytics-dashboard-screen-dart-77e1da40"
primary_target: "frontend/lib/features/analytics/presentation/analytics_dashboard_screen.dart"
related_targets: ["frontend/lib/features/sales_pos/presentation/widgets/product_search_results.dart","frontend/lib/features/inventory/presentation/widgets/clone_catalog_sheet.dart","frontend/lib/features/analytics/presentation/widgets/daily_sales_chart.dart"]
---

# Surface brief — Sugerencia comunitaria, clonación de catálogo y dashboard (Tarea 15.2)

## Scope
Modo: Operate. Tres superficies del tendero dentro del mundo visual establecido (darkSlate, `surface` radio 12 con borde, esmeralda solo en la acción primaria, skyBlue en chips informativos, cifras tabulares, tipografía del sistema). Primaria: `analytics_dashboard_screen.dart` (tab Reportes). Relacionadas: `product_search_results.dart` (sugerencia en POS), `clone_catalog_sheet.dart` (hoja desde "Mi cuenta"), `daily_sales_chart.dart`.

## Audiencia y tarea
- Cajero con fila: escanea un código que su tienda nunca vendió. Tarea: cobrar sin teclear un nombre largo. Hoy el POS daba "Sin resultados" (dead end).
- Dueño Plan Corporativo: abre sucursal → clonar sin Excel. Dueño en general: saber si el mes fue bueno sin scroll horizontal.

## Restricciones (de /intent)
Privacidad sagrada (Const. 7.5): el distintivo nunca dice qué tienda aportó el nombre ni precio ni stock; `confidence_score` se muestra como "N comercios coinciden", nunca estrellas ni %. La sugerencia se ofrece: un toque la usa, ninguno la ignora; el precio lo pone la tienda. Clonación: dice antes qué se copia y qué no; el resumen dice qué pasó, no "¡Éxito!". Gate de plan honesto: sin Corporativo la entrada no aparece. Dashboard sin loss framing: comparativa con ambos montos, cambio como dato; margen negativo en rojo como número.

## Direction contract

THESIS: El dato antes que la métrica héroe. Reportes abre con la serie diaria (qué pasó cada día) y el monto del período como su título; ganancia, comparativa y top se leen en ese orden. En el POS la red comunitaria aparece exactamente donde antes había un callejón sin salida.

OWN-WORLD: Sin gradientes ni glow; barras del `CustomPainter` en gris con hoy en esmeralda; barras horizontales de comparativa (esmeralda actual / gris anterior); chips de período como los de categorías. Hoja de clonación: tarjeta destino sobre `darkSlate`, switches esmeralda, botón primario a todo el ancho con el conteo exacto ("Clonar 15 productos").

FIRST VIEWPORT (390 px): Reportes: chips Hoy/Semana/Mes; tarjeta Ventas con monto 30 px w800, tickets y ticket promedio, "Mejor día", barras del período y tres fechas. Debajo: Ganancia (utilidad bruta + % margen + nota de costo congelado), Comparado con…, Lo más vendido (5 filas con barra proporcional). Tablet: columna a 600 dp.

FORM: POS — tarjeta de sugerencia con chip de origen (`groups` comunidad / `verified` semilla), nombre, "categoría · N comercios coinciden", acción "Usar este nombre y poner precio" → AddProductModal prellenado → al guardar entra al carrito. Clonación — una hoja, tres estados (destino y opciones → progreso determinado → resumen).

FINISH: revisado en capturas `.impeccable/review/15_2_*.png` (arnés temporal con Segoe UI; los rótulos de botón salen en bloques por la fuente por defecto del entorno de pruebas, no en la app). Detector mecánico sin hallazgos. Correcciones aplicadas tras inspección: helper del código truncado (copy más corto, 2 líneas); chips de período alineados a la columna de 600 dp en tablet.

## Pendientes
Backend 15.1 (Alan): `lookup-ean` Tier 2, `clone-catalog`, `clone-targets/{code}` (sin contrato aún), `/analytics/dashboard` + `sales-trends`. Mocks por defecto (`COMMUNITY_MOCK`, `CLONE_MOCK`, `ANALYTICS_MOCK`).
