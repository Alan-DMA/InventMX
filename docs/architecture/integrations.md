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
| `inventory` (catálogo, kardex, import masivo) | ✅ Real | `InventoryRepositoryImpl`, 9/9 métodos, probado con ida y vuelta real |
| `cash_treasury` (turnos de caja) | ✅ Real (repo) / ⚠️ ver nota | `CashRepositoryImpl` completo, 5/5 métodos probados. **Pero** `CashSessionNotifier.ensureOpenSession()`, `_computeExpectedCashMxn()` y `digitalPaymentTotalsProvider` (en `cash_session_provider.dart`) siguen leyendo `CashRepositoryMock`/`SalesRepositoryMock` **directo**, saltándose el repositorio inyectado — pendiente de arreglar (ver Pendientes) |
| `saas_admin` | ✅ Real (repo) / ⚠️ roto | `SaasRepositoryImpl` completo, 13/13 métodos, pero apunta a `/api/v1/saas/*` — **rutas eliminadas** en el merge de hoy. El backend real ahora vive en `/api/v1/saas-billing/*`, con otro contrato. Pendiente de remapear |
| `analytics/commissions` | ✅ Real | `CommissionsRepositoryImpl`, único método, sin flag |
| `analytics/dashboard` | 🔀 Flag (mock por defecto) | `ANALYTICS_MOCK` (default `true`). Impl completa, sólo falta decidir cuándo voltear el switch |
| `inventory/clone_catalog` | 🔀 Flag (mock por defecto) | `CLONE_MOCK` (default `true`). Impl completa pero pega a endpoints sin contrato documentado — verificar que existan antes de voltear |
| `sales_pos/community_catalog` (lookup EAN Tier 2) | 🔀 Flag (mock por defecto) | `COMMUNITY_MOCK` (default `true`). Impl completa |
| `sales_pos` (Kardex/reembolso) | 🚧 Parcial | `SalesRepositoryImpl.checkout()` real y probado. `getSales/getSaleById/getCashiers/refundSale` = `UnimplementedError` a propósito. `salesRepositoryProvider` sigue en Mock — ver Pendientes |
| `management` (almacenes CRUD, usuarios, roles) | ⛔ 100% mock, deliberado | Decisión de Eduardo (Sep 16): no conectar aunque exista endpoint legacy. No reabrir sin decisión explícita |
| `dashboard` (snapshot + avisos) | ⛔ 100% mock, deliberado | Misma decisión. Ya documenta qué endpoint futuro usaría cada dato (ver comentario en `dashboard_repository.dart`) |
| `account` (cambio de contraseña) | ⛔ 100% mock | Falta endpoint (`POST /auth/change-password` propuesto, no existe) |
| `purchases` (proveedores, OCR, CxP) | ⛔ 100% mock | Backend de Alan (11.1/12.1) nunca llegó — 11 métodos por construir |
| `whatsapp_catalog` (vitrina, pedidos) | ⛔ 100% mock | 6 métodos; `submitOrder`/`fetchOrder` ni siquiera tienen endpoint propuesto |
| `account` → almacén operativo | ✅ Real (nuevo, hoy) | `default_warehouse_id` en `users`, `GET /me` lo expone, `PATCH /me/warehouse` lo cambia (valida mismo tenant). Reemplaza el selector 100% local que había antes |

## Bugs reales encontrados y resueltos esta sesión

Todos verificados con test de integración o curl directo contra el backend vivo.

| Bug | Causa | Fix |
|---|---|---|
| Login fallaba con error interno tras el merge | `migrations/env.py` importaba `app.models.models` (borrado en el merge modular) → Alembic roto → migraciones nunca corrieron → esquema real desincronizado | Reescrito el import para cargar `domain/__init__.py` de cada módulo |
| Migraciones "corrían" pero no dejaban tablas | `SET search_path` antes de `context.configure()` dispara el autobegin de SQLAlchemy 2.0; Alembic ve una transacción ya abierta y no la comitea | `connection.commit()` explícito al final de `run_migrations_online()` |
| Migración `de56324d132d` (RLS legacy) huérfana | Encadenaba sobre una revisión que Alan eliminó al reescribir el historial completo (`0001_initial_core_and_rls.py` ya cubre RLS) | Eliminada — superada por la cadena modular |
| `CashRepositoryImpl` truena al parsear turnos | Los montos vienen como **string** (`"500.00"`), no número — Pydantic serializa `Decimal` así | Helper `_toDouble()` defensivo en 8 puntos de parseo |
| `checkout()` fallaba con 422 | Payload sin `warehouse_id` (obligatorio), payos con nombres de campo viejos (`amount_usd`/`amount_mxn` en vez de `amount_paid_mxn`, `reference_number` en vez de `reference_code`) | Payload y parseo de respuesta reescritos contra el contrato real (`SaleCheckoutRequest`/`SaleResponse`) |
| `warehouse_id` del checkout venía de un mock | `operatingWarehouseProvider` sacaba su lista de `management_provider.dart` (mock, ids falsos `wh-00X`) en vez del backend real | Construido `default_warehouse_id` en el perfil del backend (`/me`, `PATCH /me/warehouse`); `operatingWarehouseProvider` y "Dónde opero" reapuntados a `GET /inventory/warehouses` real |

## Bug reportado, no resuelto (es de Alan)

**`POST /sales/checkout` no descuenta el stock del producto vendido.** La venta
se crea perfecto (folio, totales, ítems, `status: COMPLETED`), pero
`product_stock.current_stock` queda igual. Verificado limpio con curl directo,
aislado de cualquier código de cliente — no es un problema de mapeo del
frontend. Test de integración documentado con `skip:` explicando el bug
(`test/integration/sales_repository_impl_test.dart`), listo para reactivarse
en cuanto se corrija.

## Pendientes / próximas tareas (orden sugerido)

1. **Reportar a Alan** el bug de stock sin descontar (bloquea confiar en
   checkout real para cualquier flujo de venta de verdad).
2. **`cash_treasury`**: sacar `CashSessionNotifier` de leer
   `CashRepositoryMock`/`SalesRepositoryMock` directo — usar el repositorio
   inyectado (`cashRepositoryProvider`) para `ensureOpenSession`,
   `_computeExpectedCashMxn` y `digitalPaymentTotalsProvider`. Depende de que
   `salesRepositoryProvider` tenga `getSales` real (punto 3) para calcular
   ventas del turno.
3. **`sales_pos` Kardex/reembolso real**: escribir `getSales`, `getSaleById`,
   `getCashiers` contra el contrato real (cajero por `cashier_id` UUID, sin
   total/suma agregada en el listado — hay que decidir cómo resolver eso en
   el cliente). Para `refundSale`: decidir con Eduardo/Alan si se acepta sólo
   cancelación total (`POST /{id}/cancel`, ya existe) o se le pide a Alan un
   endpoint de reembolso parcial por renglón (lo que el mock ya soporta hoy).
   Sólo entonces voltear `salesRepositoryProvider` a `SalesRepositoryImpl`.
4. **`saas_admin`**: remapear `SaasRepositoryImpl` de `/api/v1/saas/*` a
   `/api/v1/saas-billing/*` — revisar el contrato real de Alan primero
   (probablemente distinto al legacy que se retiró).
5. **Flags ya listos para voltear** cuando se confirme que sus endpoints
   existen de verdad en el backend montado: `ANALYTICS_MOCK`,
   `COMMUNITY_MOCK`, `CLONE_MOCK` (este último con endpoints sin contrato
   documentado — confirmar con Alan antes).
6. **Sin backend todavía** (deliberado o por falta de endpoint, no urgente):
   `management`, `dashboard`, `account.changePassword`, `purchases`,
   `whatsapp_catalog`.

## Qué cubrir con tests de integración a medida que se avance

Cada punto de la lista de Pendientes debería llegar con su propio archivo en
`test/integration/`, mismo patrón que los ya existentes:

- `cash_repository_test.dart` — agregar un caso que verifique que el efectivo
  esperado del turno refleja ventas reales (hoy no se puede probar porque
  depende del punto 2).
- `sales_repository_impl_test.dart` — cuando se implementen los métodos
  reales, agregar: listar ventas del día, traer detalle por id, listar
  cajeros, y (según lo que se decida) reembolso total o parcial.
- `saas_repository_test.dart` (nuevo) — perfil, plan, suscripción contra
  `/api/v1/saas-billing/*` una vez remapeado.
- Antes de voltear cada flag mock→real (`ANALYTICS_MOCK`, `COMMUNITY_MOCK`,
  `CLONE_MOCK`): un test de integración mínimo que confirme que el endpoint
  real responde con el shape esperado, corriendo con `--dart-define` en
  `false` para forzar la implementación real.
- Para los módulos 100% mock sin backend (`management`, `purchases`,
  `whatsapp_catalog`, `account.changePassword`, `dashboard`): no hay nada que
  probar todavía — el primer test de integración de cada uno nace junto con
  su primer endpoint real.

## QA manual pendiente (dispositivo)

- Confirmar en el teléfono que "Dónde opero" (Perfil) lista los almacenes
  reales del comercio y que cambiarlo se refleja de inmediato en el checkout.
- Repetir el flujo completo de una venta en el POS real una vez que el bug de
  stock (ver arriba) esté resuelto por Alan, para confirmar que el inventario
  sí baja en pantalla.
