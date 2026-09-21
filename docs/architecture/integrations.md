# Integraciones backend real — plan y estado

> Última actualización: 18 sep 2026. Nace de la sesión donde se adoptó el backend
> modular de Alan (merge `InvenMex/main`), se reparó el pipeline de migraciones,
> se auditó qué features siguen en mock, y se armó la primera tanda de tests de
> integración contra el backend vivo. Se actualiza cada vez que algo pase de
> mock a real, o que un test de integración nuevo se agregue.

## Cómo correr los tests de integración

```
backend:  backend/.venv/Scripts/python.exe -m uvicorn app.main:app --host 127.0.0.1 --port 8000
frontend: cd frontend && flutter test test/integration/
```

Viven en `frontend/test/integration/`, separados de los tests unitarios/widget
normales porque **requieren el backend real levantado en `127.0.0.1:8000`**.
Si el backend no responde, cada test se marca `skipped` con un mensaje claro
(`isBackendUp()` en `_harness.dart`) en vez de tronar con un error de conexión
confuso. Usan un tenant dedicado (`integration-test@nexus.mx`), no el tenant de
QA manual (`eduardo@nexus.com`), para no ensuciar datos de prueba.

## Estado por feature (mock vs real)

| Feature | Estado | Detalle |
|---|---|---|
| `auth` (login, registro, `/me`, almacén operativo) | ✅ Real | `AuthRepositoryImpl` completo, 3/3 + 1 métodos probados |
| `inventory` (catálogo, kardex) | ✅ Real | `InventoryRepositoryImpl`, 9/9 métodos, probado con ida y vuelta real. Detalle de producto (`GET /inventory/products/{id}`) incluye `suggested_max_price_mxn`/`_source` (nuevo, Sep 2026 — ver nota "Precio máximo sugerido" abajo) |
| `inventory/import` (carga masiva Excel/CSV) | ✅ Real (20 sep 2026) | `ImportRepositoryImpl` reescrito contra el contrato del backend modular (`ImportPreviewResponse`/`ColumnMapping`/`ImportExecutionResponse`). **La nota de la séptima sesión ("ya estaba conectada, sólo verificación") era falsa**: las URLs eran correctas pero el cliente mandaba `col_name`/`col_price_mxn` y leía `preview_rows`/`updated_count` — 422 en cada importación y vista previa vacía. 4/4 casos en `import_repository_test.dart` (preview con sugerencia, alta parcial con omitidos, sin columna de stock, error legible) |
| `cash_treasury` (turnos de caja) | ✅ Real | `CashRepositoryImpl` completo, 5/5 métodos probados. `expectedCashMxnProvider`/`digitalPaymentTotalsProvider` ya piden `GET /sales`/`GET /cash/sessions/{id}/movements` reales (Sep 2026 — ver nota "cash_treasury desacoplado del mock" abajo). `ensureOpenSession()` sigue usando un fondo inicial fijo (`CashRepositoryMock.defaultOpeningAmountMxn`) porque no existe todavía una UI de apertura de turno real — fuera de alcance |
| `saas_admin` | ✅ Real (repo) / ⚠️ roto | `SaasRepositoryImpl` completo, 13/13 métodos, pero apunta a `/api/v1/saas/*` — **rutas eliminadas** en el merge de hoy. El backend real ahora vive en `/api/v1/saas-billing/*`, con otro contrato. Pendiente de remapear |
| `analytics/commissions` | ✅ Real | `CommissionsRepositoryImpl`, único método, sin flag |
| `analytics/dashboard` | 🔀 Flag (mock por defecto) | `ANALYTICS_MOCK` (default `true`). Impl completa, sólo falta decidir cuándo voltear el switch |
| `inventory/clone_catalog` | 🔀 Flag (mock por defecto) | `CLONE_MOCK` (default `true`). Impl completa pero pega a endpoints sin contrato documentado — verificar que existan antes de voltear |
| `sales_pos/community_catalog` (lookup EAN Tier 2) | 🔀 Flag (mock por defecto) | `COMMUNITY_MOCK` (default `true`). Impl completa |
| `sales_pos` (Kardex/reembolso) | ✅ Real | `SalesRepositoryImpl` completo: `checkout/getSales/getSaleById/getCashiers/refundSale`, 5/5 probados contra backend vivo (incluye reembolso total y parcial por renglón). `salesRepositoryProvider` **ya apunta a `SalesRepositoryImpl`** (Sep 2026) — el bloqueador (cash_treasury/comisiones leyendo el mock estático) se resolvió |
| `management` (almacenes CRUD, usuarios, roles) | ⛔ 100% mock, deliberado | Decisión de Eduardo (Sep 16): no conectar aunque exista endpoint legacy. No reabrir sin decisión explícita. **Excepción real (Sep 2026):** el bloque "Precios" de `PreferencesScreen` (margen máximo sugerido) sí es real — vive aparte, no comparte repositorio con Almacenes/Categorías/Usuarios — ver nota "Precio máximo sugerido" abajo |
| `dashboard` (snapshot + avisos) | ⛔ 100% mock, deliberado | Misma decisión. Ya documenta qué endpoint futuro usaría cada dato (ver comentario en `dashboard_repository.dart`) |
| `account` (cambio de contraseña) | ⛔ 100% mock | Falta endpoint (`POST /auth/change-password` propuesto, no existe) |
| `purchases` (proveedores, órdenes de compra, CxP) | ✅ Real (repo) / ⚠️ provider en mock | `PurchasesRepositoryImpl` completo, 10/10 métodos probados contra backend vivo (ciclo proveedor→producto→orden→recepción→CxP→pago). `purchasesRepositoryProvider` **sigue apuntando a `PurchasesRepositoryMock` a propósito** — bloqueador real: "Nueva orden de compra" captura productos por nombre libre, no selecciona un producto real del catálogo, y el backend exige `product_id` real. Ver "PRÓXIMAS TAREAS" en `registro_implementacion.md`. OCR (`parse-receipt`) y dictado (`parse-voice-dictation`) quedan 100% locales a propósito — mismo bloqueador de fondo |
| `whatsapp_catalog/store_orders` (pedidos web del tendero + WS) | ✅ Real (20 sep 2026, Tarea 13.3) | `StoreOrdersRepositoryImpl` 4/4 + `OrderEventsChannel` (`WS /ws/orders`). Endpoints y tabla construidos aquí (migración `0020`). 2/2 en `store_orders_repository_impl_test.dart` (ciclo completo con WS real; cancelar/reabrir). El shell abre el socket: **todo test que monte `DashboardShell`/POS/router debe sobreescribir `orderEventsProvider` (stream vacío) y `storeOrdersRepositoryProvider` (mock)** o fallará por timers pendientes |
| `whatsapp_catalog` (vitrina, pedidos, Mi catálogo) | ✅ Real (20 sep 2026) | `WhatsappCatalogRepositoryImpl`, 6/6 métodos contra `whatsapp_catalog` de Alan. `submitOrder`/`fetchOrder` **ya tienen endpoint**: `POST /public/catalog/{slug}/orders` (201 + folio `P-YYMMDD-XXXX`) y `GET .../orders/{folio}`, construidos en esta sesión (tabla `catalog_orders`, migración `0019`). `GET/PUT /catalog-settings` ahora traen `store_name`/`store_slug`. 4/4 casos en `whatsapp_catalog_repository_impl_test.dart` (settings con slug + commit + borrar con vacío; vitrina anónima → vista previa → pedido con folio → ticket; `OrderRejected`; `CatalogDisabled`/`StoreNotFound`). El mock queda sólo para widget tests |
| `account` → almacén operativo | ✅ Real (nuevo, hoy) | `default_warehouse_id` en `users`, `GET /me` lo expone, `PATCH /me/warehouse` lo cambia (valida mismo tenant). Reemplaza el selector 100% local que había antes |

## Bugs reales encontrados y resueltos esta sesión

Todos verificados con test de integración o curl directo contra el backend vivo.

**20 sep 2026 (Excel + catálogo web):**

| Síntoma | Causa | Fix |
|---|---|---|
| Importar Excel/CSV devolvía 422 siempre; la vista previa mostraba 0 filas | `ImportRepositoryImpl` escrito contra el backend legacy (claves `col_name`/`preview_rows`/`updated_count`) | Reescrito contra `import_export.py`; `ColumnMapping`/`SuggestedMapping` tipados en Dart |
| Los cambios de "Mi catálogo" (número de WhatsApp, reglas) se perdían al cerrar la petición | `CatalogSettingsService.update_settings` no hacía `session.commit()` — mismo patrón que `SalesService`/`PurchasingService` | `await self.session.commit()` en `get_settings` (la config se crea en el primer GET) y `update_settings` |
| No había forma de borrar el número de WhatsApp desde la app | `CatalogRepository.update_settings` ignoraba `None` y guardaba `""` tal cual | Los campos de texto (`whatsapp_number`, `welcome_message`, `business_hours`) se normalizan: vacío → `NULL` |
| "Mi catálogo" no podía armar el enlace público | `CatalogSettingsResponse` no traía el slug del tenant (la app tira el `tenant` del login) | `store_name` + `store_slug` en la respuesta |
| Tras importar, Inventario seguía mostrando la lista vieja | `ImportScreen` no invalidaba `inventoryProvider` (tercer caso del mismo patrón: checkout, reembolso, import) | `ref.invalidate(inventoryProvider)` si `imported > 0` |
| `subscription_lock_test.dart` colgaba en "Nueva compra" | Abría `/purchases` sin override tras voltear `purchasesRepositoryProvider` a real (octava sesión) | `purchasesRepositoryProvider.overrideWithValue(PurchasesRepositoryMock())` |

| Bug | Causa | Fix |
|---|---|---|
| Login fallaba con error interno tras el merge | `migrations/env.py` importaba `app.models.models` (borrado en el merge modular) → Alembic roto → migraciones nunca corrieron → esquema real desincronizado | Reescrito el import para cargar `domain/__init__.py` de cada módulo |
| Migraciones "corrían" pero no dejaban tablas | `SET search_path` antes de `context.configure()` dispara el autobegin de SQLAlchemy 2.0; Alembic ve una transacción ya abierta y no la comitea | `connection.commit()` explícito al final de `run_migrations_online()` |
| Migración `de56324d132d` (RLS legacy) huérfana | Encadenaba sobre una revisión que Alan eliminó al reescribir el historial completo (`0001_initial_core_and_rls.py` ya cubre RLS) | Eliminada — superada por la cadena modular |
| `CashRepositoryImpl` truena al parsear turnos | Los montos vienen como **string** (`"500.00"`), no número — Pydantic serializa `Decimal` así | Helper `_toDouble()` defensivo en 8 puntos de parseo |
| `checkout()` fallaba con 422 | Payload sin `warehouse_id` (obligatorio), payos con nombres de campo viejos (`amount_usd`/`amount_mxn` en vez de `amount_paid_mxn`, `reference_number` en vez de `reference_code`) | Payload y parseo de respuesta reescritos contra el contrato real (`SaleCheckoutRequest`/`SaleResponse`) |
| `warehouse_id` del checkout venía de un mock | `operatingWarehouseProvider` sacaba su lista de `management_provider.dart` (mock, ids falsos `wh-00X`) en vez del backend real | Construido `default_warehouse_id` en el perfil del backend (`/me`, `PATCH /me/warehouse`); `operatingWarehouseProvider` y "Dónde opero" reapuntados a `GET /inventory/warehouses` real |
| `GET /sales` tronaba con `TypeError` | `sales_service.py::list_sales` llamaba al repositorio con el kwarg `status_filter`, pero el repositorio espera `status`; además descartaba `total_count` y trataba la tupla `(sales, total_count)` como si fuera sólo la lista | Kwarg corregido a `status`; el servicio ahora retorna `(items, total)` y el endpoint expone el total en el header `X-Total-Count` |
| **`POST /sales/checkout` "no descontaba el stock"** (mal diagnosticado el 17 sep) | La causa real no era la lógica de descuento — `SalesService.process_pos_checkout`, `cancel_sale` y `add_payment_to_sale` nunca llamaban `session.commit()`. `get_db()` sólo hace `session.close()`, que revierte cualquier transacción no comiteada — la venta completa (folio, ítems, descuento de stock, Kardex) se creaba y se veía en la misma petición, pero se perdía por completo al cerrarse la sesión | `await self.session.commit()` agregado al final de `process_pos_checkout`, `add_payment_to_sale`, `cancel_sale` y el nuevo `refund_sale`. Verificado con curl directo (stock 10→8 tras vender 2) y con el test antes-`skip`eado de `sales_repository_impl_test.dart`, ahora en verde. **Nota:** `record_sale_commission` tiene el mismo patrón sin commit — no se tocó por estar fuera del alcance de esta tarea, pero es candidato a revisar |
| Reincidencia en QA de dispositivo (Sep 18, quinta sesión): "al vender no se descuenta el stock", esta vez de verdad de UI | El backend estaba bien (re-verificado con curl: 10→8). `CartNotifier.checkout()` (`cart_provider.dart`) nunca invalidaba `inventoryProvider` tras un checkout exitoso — a diferencia de `adjustStock`/`transferStock`. `productDetailProvider` resuelve primero contra la lista cacheada de `inventoryProvider.products` antes de pedir al backend, así que Inventario/Detalle de producto seguían mostrando el stock de antes de la venta indefinidamente | `ref.invalidate(inventoryProvider)` al final de `checkout()`, mismo patrón que `product_detail_screen.dart`. Cubre producto simple/combo/al vuelo sin parcheo por ítem. Test de regresión en `cart_provider_test.dart` (confirmado que falla sin el fix) |
| Mismo bug, mismo día, en Reembolsos (parcial y total) | `_handleRefund()` (`sale_receipt_screen.dart`) invalidaba `saleDetailProvider`/`salesKardexProvider` tras un reembolso pero no `inventoryProvider` — la reposición a stock (`refund_to_stock`) del backend quedaba igual de invisible en Inventario/Detalle de producto | `ref.invalidate(inventoryProvider)` agregado al final de `_handleRefund()`. Test de regresión end-to-end en `sale_receipt_screen_test.dart` (abre hoja de reembolso, confirma, verifica `getProducts` llamado de nuevo — confirmado que falla sin el fix) |
| **Mismo patrón de `session.commit()` faltante, ahora en `purchasing_suppliers`** (séptima sesión, al conectar Compras) | `create_supplier`, `update_supplier`, `deactivate_supplier`, `create_purchase_order`, `receive_purchase_order` (`purchasing_service.py`) y `record_supplier_payment` (`accounts_payable_service.py`) tampoco comiteaban — la corrección anterior de `sales_pos` no cubría este módulo (la nota de la fila de arriba sobre "todos los demás servicios sí comitean" era incorrecta, quedó desactualizada). Un proveedor creado exitosamente (201) desaparecía antes de que la orden de compra pudiera referenciarlo, con 404 "Proveedor especificado no existe" | `await self.session.commit()` agregado a los 6 métodos. Verificado con el nuevo `purchases_repository_impl_test.dart` (ciclo completo proveedor→producto→orden→recepción→CxP→pago contra backend vivo) y con la suite unitaria completa del backend (145 tests, sin regresiones) |

## `sales_pos` Kardex/reembolso real — completado (18 sep 2026)

Implementation Plan aprobado por Eduardo el 18 sep, implementado y probado el
mismo día (backend + frontend + tests, sin quedar a medias):

1. **`GET /sales`**: kwarg corregido (`status`, no `status_filter`), servicio
   retorna `(items, total_count)`, endpoint expone el total en
   `X-Total-Count`. Query param de estado ahora es `status` (alias), alineado
   con `docs/api/sales.yaml`.
2. **`cashier_name`** agregado a `SaleResponse`, tomado de `sale.cashier`
   (`lazy="selectin"`, siempre cargado) — mismo patrón que
   `default_warehouse_id`.
3. **Reembolso parcial real**: migración `0017_add_sale_refund_columns`
   (`sale_items.refunded_quantity`, `sales.refunded_amount_mxn`), endpoint
   `POST /api/v1/sales/{id}/refund` (`SalesService.refund_sale`) — acepta
   `items` específicos o reembolsa todo lo pendiente si se omite, repone
   stock opcionalmente con `MovementType.SALE_RETURN` (espejo de
   `cancel_sale`), permiso `sales.cancel`. Un solo evento de reembolso por
   venta: al aplicarse el estado pasa a `REFUNDED` (total o parcial) y un
   segundo intento devuelve 422.
4. **`SalesRepositoryImpl`**: `getSales/getSaleById/getCashiers/refundSale`
   reales. Cajero filtrado por nombre en la UI, resuelto a `cashier_id`
   contra `GET /users` (requiere `settings.manage_users` — si el rol en
   sesión no lo tiene, el filtro por cajero simplemente no ofrece opciones,
   comportamiento ya existente en el notifier). Limitación conocida y
   documentada en el código: `PaginatedSales.totalAmountMxn` sólo suma la
   página actual (el contrato real no expone un agregado del recorte
   completo) y el filtro por `paymentKind` se aplica en cliente porque el
   backend no implementa `payment_method` como filtro todavía.
5. Tests nuevos: 3 en el backend (`test_sales_pos_and_lazy_loading.py` —
   listado paginado con `X-Total-Count`, reembolso total, reembolso parcial
   por renglón) + 6 en `sales_repository_impl_test.dart` (detalle, 404,
   listado, cajeros, reembolso total con doble intento, reembolso parcial).
   Los 11 tests del archivo backend y los 8 del archivo frontend pasan en
   verde contra el backend real; suite completa de backend (141 tests) y
   suite completa de frontend (662 tests, unitarios/widget + integración
   con backend real levantado) sin regresiones.

**`salesRepositoryProvider` sigue en Mock a propósito** (ver Pendientes →
punto 1): no es un problema de contrato, es que `cash_session_provider.dart`,
`analytics_dashboard_repository.dart` y `commissions_repository.dart` leen
`SalesRepositoryMock.todaysSales` (estático) directo, saltándose el
provider. Voltear hoy dejaría esas tres pantallas sin datos del día porque un
checkout real no escribe en esa lista estática.

## Ficha de producto — limpieza de UI y "Precio máximo sugerido" real (18 sep 2026, sesión aparte)

Pedido de Eduardo sobre pantallas ya construidas (editar producto y ficha de
detalle), fuera del flujo de `registro_implementacion.md` — documentado aquí
porque cruzó a backend:

1. **Editar producto**: eliminada la sección duplicada "IMAGEN DEL PRODUCTO"
   (URL + botón de subida que repetía lo que ya hace el banner de arriba);
   quitados los tags "Subir archivo"/"URL web" del placeholder del banner —
   sólo queda "Cambiar foto" como entrada única (sigue abriendo el mismo
   modal con ambas opciones).
2. **Stock reservado**: quitado de la ficha (`StockCard` ya no tiene
   `variant`, sólo renderiza DISPONIBLE). Decisión de Eduardo tras
   confirmar que **sí es funcional en el backend** (hold de 15 min durante
   checkout, `ReservationStatus`/`core/tasks.py`) pero casi siempre en 0 en
   la práctica — no aporta al dueño de la tienda verlo, mismo criterio que
   "la app es referencial, no operacional" ya usado en el modal de pago.
3. **Precio máximo sugerido** (antes placeholder `'—'` sin cálculo alguno):
   - Modelo de **elasticidad de la demanda** cuando hay suficiente
     historial: `InventoryService._compute_suggested_max_price` agrupa
     `sale_items` del producto por precio, ajusta `Q = a - b·P` por mínimos
     cuadrados (`_fit_demand_curve`, sólo si la pendiente es negativa — si
     no, los datos no tienen sentido económico y se descarta) y sugiere el
     precio que maximiza ingresos, `P* = a/(2b)`.
   - **Margen máximo configurable** como piso mientras no haya ≥2 precios
     históricos distintos con ventas: `costo × (1 + max_margin_percent/100)`.
     Nuevo campo `tenants.max_margin_percent` (migración
     `0018_add_max_margin_percent_to_tenants`, default 40.00%), editable vía
     `GET/PATCH /api/v1/tenants/me/pricing-settings` (permiso
     `settings.manage_store` — seeded desde el día 1, nunca usado hasta
     ahora).
   - `ProductResponse` expone `suggested_max_price_mxn` +
     `suggested_max_price_source` (`"historical"` o `"margin_fallback"`) —
     sólo se calcula en el **detalle** del producto (`get_product_by_id`),
     nunca en el listado, para no correr una regresión por producto en cada
     carga.
   - Frontend: `Product.suggestedMaxPriceMxn/-Source` nuevos; la ficha
     muestra el valor real + una leyenda de qué criterio se usó. Nuevo
     bloque **"Precios"** en `PreferencesScreen`, real (a diferencia del
     resto de la pantalla, mock a propósito) — repositorio: métodos nuevos
     en `AuthRepository` (`fetchMaxMarginPercent`/`setMaxMarginPercent`),
     mismo patrón que `default_warehouse_id`.
4. Tests nuevos: 4 en el backend (`test_inventory_and_vital_fields.py` —
   ajuste de margen con RBAC, margen de respaldo sin historial, elasticidad
   con historial suficiente incluyendo el cálculo exacto esperado) + 4 en
   frontend (`product_detail_screen_test.dart` — historial/margen/sin dato;
   `management_screens_test.dart` — fila y edición del margen). Suite
   completa de backend (145 tests) y frontend sin regresiones.

## Bug reportado: "seleccionar un producto no lo agrega al carrito" (18 sep 2026)

Investigado a fondo: el cableado tocar-resultado → `addProduct` → carrito
**sí estaba bien** (confirmado escribiendo el primer test que simula el tap
real en vez de llamar al provider directo — ver `checkout_screen_test.dart`,
"tocar un producto en el panel de resultados lo agrega al carrito"). Se
encontraron y corrigieron dos bugs reales, adyacentes, que sí explican "no
puedo completar una venta":

- **`inventoryProvider` se creaba tarde**: sólo se activaba al primer tecleo
  en el buscador (dentro de `ProductSearchResults`), dejando una ventana
  donde una búsqueda inmediata al abrir el POS mostraba "Sin resultados"
  mientras el catálogo seguía en camino del backend. Fix: `checkout_screen.
  dart` precalienta `inventoryProvider` en `initState()`.
- **`CartNotifier.checkout()` leía el almacén operativo síncrono**
  (`ref.read(operatingWarehouseProvider).valueOrNull` en vez de `await
  ref.read(operatingWarehouseProvider.future)`): si el cajero cobraba antes
  de que ese provider terminara de resolver, leía `null` y abortaba el
  cobro con "Selecciona un almacén operativo" aunque el carrito estuviera
  bien armado — el carrito no se vaciaba, pero la venta nunca se completaba.

## `cash_treasury` desacoplado del mock + `salesRepositoryProvider` real (18 sep 2026, tercera sesión)

Plan aprobado por Eduardo, con un hallazgo a mitad de camino que cambió el
alcance (ver abajo): `SalesRepository.getSales()` sólo traía `SaleSummary`
con una clasificación gruesa del pago (`cash`/`card`/`mixed`...), sin el
desglose exacto por método — insuficiente para un arqueo de caja preciso
con ventas de pago mixto. Eduardo decidió extender el contrato en vez de
aproximar.

1. **`SaleSummary` extendido**: nuevo campo `payments: List<PaymentEntry>`
   (el desglose real, ya lo devolvía el backend — sólo faltaba adjuntarlo al
   modelo del listado). Sin cambios de backend.
2. **`cash_session_provider.dart` real**:
   - `_shiftSalesProvider` (nuevo, privado): trae las ventas del turno vía
     `getSales(dateFrom: apertura)`, paginando hasta agotar el total.
     Filtra por cajero **en cliente** (no `SalesQuery.cashierName`, que
     exige `settings.manage_users` vía `GET /users` — un Cajero cerrando su
     propio turno no necesariamente lo tiene). Cacheado por sesión: no se
     re-consulta al registrar un movimiento de caja menor (los movimientos
     no cambian qué se vendió).
   - `CashMovementsNotifier` ahora pide `GET /cash/sessions/{id}/movements`
     real en vez de `CashRepositoryMock.movementsFor` estático; usa
     `ref.watch(cashSessionProvider.select((s) => s?.id))` para no
     recargar cuando sólo cambia el `status` de la misma sesión (cerrar
     turno) en vez del id.
   - `expectedCashMxnProvider`/`digitalPaymentTotalsProvider` pasaron de
     `Provider` síncrono a `FutureProvider` — la UI (`CashSessionScreen`,
     `CloseSessionWizard`) ahora los lee como `AsyncValue`.
   - **Hallazgo de diseño**: `CashSessionNotifier` (dueño de
     `cashSessionProvider`) no puede leer `_shiftSalesProvider` ni
     `cashMovementsProvider` (ambos dependen de `cashSessionProvider`) —
     Riverpod lo marca como dependencia circular aunque sea `ref.read`, no
     `ref.watch`. `closeSession()` ahora recibe `movements` como parámetro
     (se lo pasa `CloseSessionWizard`, que sí puede leerlo) y pide las
     ventas frescas y directo (`_fetchShiftSalesRaw`, sin pasar por el
     provider cacheado).
3. **`commissions_repository.dart`**: `CommissionsRepositoryMock` eliminado
   — código muerto confirmado (ningún provider real lo usaba;
   `employee_performance_provider.dart` ya apuntaba a
   `CommissionsRepositoryImpl` real desde antes).
4. **`analytics_dashboard_repository.dart`**: sin cambios — su lectura de
   `SalesRepositoryMock.todaysSales` vive dentro de
   `AnalyticsDashboardRepositoryMock`, ya detrás de `ANALYTICS_MOCK`
   (independiente, sigue en la lista de flags pendientes más abajo).
5. **`salesRepositoryProvider` volteado a `SalesRepositoryImpl`** — los tres
   consumidores del mock estático (cash_treasury, comisiones,
   parcialmente analytics) ya no bloquean el flip.
6. Tests: extendido `_makeOpenContainer`/`_buildApp` en los 3 archivos de
   test de `cash_treasury` para inyectar `SalesRepositoryMock` real (no
   mocktail) vía `salesRepositoryProvider.overrideWith(...)` — necesario
   porque antes ni siquiera se tocaba ese provider desde estos tests.
7. **Efecto colateral del flip, detectado por la suite completa**: cualquier
   test que monta el Dashboard (`HomeDashboardScreen`, pantalla de entrada)
   sin pasar por su tab de Ventas usa `recentSalesProvider`
   (`dashboard_provider.dart`), que ya pegaba a `salesRepositoryProvider`
   directo — con el flip, esos tests intentaban red real y colgaban en
   `pumpAndSettle timed out`. Se agregó el override en los 4 archivos que
   montan el router completo o el Dashboard sin haberlo hecho antes:
   `app_router_test.dart`, `home_dashboard_test.dart` (3 construcciones de
   `ProviderContainer` distintas en ese archivo, todas necesitaban el
   override), `inventory_screen_test.dart`, `subscription_lock_test.dart`.
   Suite completa de frontend (666 tests) sin regresiones tras el flip.

## Pendientes / próximas tareas (orden sugerido)

1. **`saas_admin`**: remapear `SaasRepositoryImpl` de `/api/v1/saas/*` a
   `/api/v1/saas-billing/*` — revisar el contrato real de Alan primero
   (probablemente distinto al legacy que se retiró).
2. **Flags ya listos para voltear** cuando se confirme que sus endpoints
   existen de verdad en el backend montado: `ANALYTICS_MOCK`,
   `COMMUNITY_MOCK`, `CLONE_MOCK` (este último con endpoints sin contrato
   documentado — confirmar con Alan antes).
3. **Sin backend todavía** (deliberado o por falta de endpoint, no urgente):
   `management`, `dashboard`, `account.changePassword`.
   (`purchases` y `whatsapp_catalog` ya están en real — ver tabla de arriba.)
4. **Candidato a revisar en el backend** (fuera de alcance de hoy):
   `record_sale_commission` tiene el mismo patrón sin `session.commit()` que
   tenían `checkout`/`cancel`/`add_payment` antes del fix de esta sesión —
   probablemente afectado por el mismo bug.
5. **Para Alan, observado al conectar el catálogo (20 sep):** (a) `Product.show_in_catalog`
   existe en el modelo pero no en `ProductResponse`/`ProductUpdate` — la app no puede
   ocultar un producto de la vitrina; hoy todo activo se muestra (no hay UI para eso, no
   bloquea). (b) La política RLS de `catalog_settings` (migración `0012`) filtra por
   `app.current_tenant_id`, pero `set_tenant_context()` fija `app.current_tenant` —
   hoy no se nota porque la tabla no tiene `FORCE ROW LEVEL SECURITY` y el usuario de
   la app es dueño de la tabla. `catalog_orders` (0019) usa la clave correcta.
   (c) `docs/api/catalog.yaml` sigue sin reflejar el backend real (ya anotado en 13.2);
   ahora además faltan `POST/GET /public/catalog/{slug}/orders[/{folio}]` y los campos
   `store_name`/`store_slug` de `CatalogSettingsResponse`.

## Entorno LAN para QA con varios dispositivos (20 sep 2026)

**Atajo:** `powershell -ExecutionPolicy Bypass -File tools\qa_lan.ps1` (se autoeleva). Hace
todo lo de abajo: quita las reglas de **bloqueo de `python.exe`** del firewall, marca la Ethernet
como red Privada, abre el 8000 y lanza backend (que sirve también la vitrina) en su propia ventana. `-BuildWeb`
recompila la vitrina; `-NoServers` sólo arregla el firewall.

> ⚠️ **Si lo corres en otra máquina (Alan): pasa tu IP.** El script toma la IP del adaptador
> llamado `Ethernet`; si no lo encuentra (Wi-Fi, otro nombre de adaptador) **cae en la IP de la PC de
> Eduardo (`192.168.50.56`)** y avisa en rojo — los enlaces del chat y la vitrina apuntarían a un
> equipo que no es el tuyo. Úsalo así:
>
> ```
> ipconfig                          # "Dirección IPv4" del adaptador conectado a la misma red que el teléfono
> powershell -ExecutionPolicy Bypass -File tools\qa_lan.ps1 -Ip 192.168.1.20 -BuildWeb
> ```
>
> `-BuildWeb` es obligatorio la primera vez y cada vez que cambie la IP: `CATALOG_BASE_URL` queda
> horneada en `frontend/build/web` en tiempo de compilación, no se lee en runtime. Lo mismo aplica al
> APK (`--dart-define=API_URL=http://<tu IP>:8000`, ver bloque de abajo).

**Causa real del "sin conexión" del 20 sep:** Windows tenía dos reglas de *Bloqueo* para
`python.exe` en el perfil Público (se crean al cancelar el diálogo "¿Permitir que python.exe se
comunique…?"), y la Ethernet estaba clasificada como Pública. Un bloqueo por programa gana sobre
cualquier permiso por puerto — por eso las reglas 8000/8088 no servían. Con NestJS "no había que
configurar nada" porque `node.exe` sí tenía su permiso. Proton VPN (kill switch) era un segundo
sospechoso, pero no el principal.

```
backend:  backend/.venv/Scripts/python.exe -m uvicorn app.main:app --host 0.0.0.0 --port 8000
          (en desarrollo sirve también frontend/build/web en /tienda/... con fallback SPA — un solo proceso)
vitrina:  cd frontend && flutter build web --release --dart-define=CATALOG_BASE_URL=http://<IP>:8000/tienda
app:      flutter build apk --debug --dart-define=API_URL=http://<IP>:8000 --dart-define=CATALOG_BASE_URL=http://<IP>:8000/tienda
URL:      http://<IP>:8000/tienda/<slug>   (rutas limpias: `usePathUrlStrategy()` en main.dart desde el 20 sep;
          con `#` WhatsApp cortaba el enlace y no era clicable)
firewall: netsh advfirewall firewall add rule name="Nexus API 8000" dir=in action=allow protocol=TCP localport=8000
```

Hallazgo del 20 sep: con las reglas del firewall creadas el teléfono seguía sin alcanzar al PC
(ni ping) — **Proton VPN (`ProTUN`) bloquea la LAN entrante** con su kill switch; hay que activar
"Permitir conexiones LAN" o desconectarla mientras se prueba. Si aun así no responde
`http://<IP>:8000/health` desde el navegador del teléfono, el router aísla Wi-Fi de Ethernet.

## Qué cubrir con tests de integración a medida que se avance

Cada punto de la lista de Pendientes debería llegar con su propio archivo en
`test/integration/`, mismo patrón que los ya existentes:

- `cash_repository_test.dart` — agregar un caso que verifique que el
  efectivo esperado del turno refleja ventas reales de punta a punta
  (checkout real → `GET /sales` → arqueo), ahora que ya no depende de nada
  más para probarse.
- `saas_repository_test.dart` (nuevo) — perfil, plan, suscripción contra
  `/api/v1/saas-billing/*` una vez remapeado.
- Antes de voltear cada flag mock→real (`ANALYTICS_MOCK`, `COMMUNITY_MOCK`,
  `CLONE_MOCK`): un test de integración mínimo que confirme que el endpoint
  real responde con el shape esperado, corriendo con `--dart-define` en
  `false` para forzar la implementación real.
- Para los módulos 100% mock sin backend (`management`,
  `account.changePassword`, `dashboard`): no hay nada que
  probar todavía — el primer test de integración de cada uno nace junto con
  su primer endpoint real.

## QA manual pendiente (dispositivo)

- **Carga masiva (20 sep):** importar un `.xlsx` real de proveedor desde el teléfono
  (el test de integración usa CSV; el parser de `.xlsx` es `openpyxl` en el backend y
  la app manda los bytes con `withData: true`). Revisar que la sugerencia de mapeo
  acierte con encabezados en español y que "Más columnas" abra sola cuando detecte
  código de barras/categoría.
- **Catálogo web (20 sep):** desde "Mi catálogo" con sesión real: enlace con el slug del
  tenant, apagar/encender, guardar número. Abrir `/tienda/{slug}` en el navegador del
  teléfono **sin sesión**, armar un pedido a domicilio con cambio, confirmar que el chat
  se abre con folio + enlace, y abrir ese enlace en otro dispositivo para ver el ticket.

- Confirmar en el teléfono que "Dónde opero" (Perfil) lista los almacenes
  reales del comercio y que cambiarlo se refleja de inmediato en el checkout.
- Repetir el flujo completo de una venta y un reembolso en el POS real ahora
  que el checkout sí descuenta stock de verdad, para confirmar que el
  inventario baja y sube en pantalla como se espera.
