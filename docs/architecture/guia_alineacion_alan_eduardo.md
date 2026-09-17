# GUÍA DE ALINEACIÓN TÉCNICA: ALAN (BACKEND) & EDUARDO (FRONTEND)
## Nexus MX v3.0 — Sistema de Gestión Comercial Modular

> **Fecha:** Septiembre 2026  
> **Estado:** Aprobado y sincronizado al 100%  
> **Fuente de verdad:** `AGENTS.md`, `docs/api/`, `Documento Maestro Nexus v3-0.md`, `Constitucion Nexus v1-0.md`

---

## 1. 🎯 PROPÓSITO DEL DOCUMENTO

Esta guía técnica tiene como finalidad garantizar que tanto **Alan** (desarrollo Backend FastAPI / PostgreSQL) como **Eduardo** (desarrollo Frontend Flutter / Riverpod) trabajen con total coherencia, simetría y sin discrepancias de modelos, rutas o bases de datos. Asimismo, sirve como referencia inmutable para cualquier agente de inteligencia artificial que asista en el desarrollo del proyecto Nexus.

---

## 2. 🗄️ BASE DE DATOS Y ESQUEMA UNIVERSAL (`public`)

### 2.1 Regla Suprema
- **Nombre de la base de datos:** `nexus`
- **Esquema único universal:** `public`
- **Estado de esquemas legacy:** El esquema `inventmx` ha sido **eliminado por completo** junto con las tablas obsoletas de la versión anterior (tablas de Binance P2P, VES, tasas paralelas, etc.).
- **Row-Level Security (RLS):** Toda tabla multi-tenant cuenta con `ENABLE ROW LEVEL SECURITY;` y `FORCE ROW LEVEL SECURITY;` con política estándar que evalúa `app.current_tenant` o el flag administrativo `app.bypass_rls`.

### 2.2 Inventario de Tablas en Producción (36 Tablas en `public`)
1. **Tenancy y Autenticación:** `tenants`, `users`, `roles`, `permissions`, `user_roles`, `role_permissions`, `revoked_tokens`.
2. **Suscripciones y Facturación SaaS (Día 14):** `subscription_invoices`, `saas_webhook_logs`.
3. **Catálogo e Inventario:** `categories`, `products`, `combos`, `combo_items`, `warehouses`, `product_stocks`, `stock_reservations`, `inventory_movements`, `seed_products`.
4. **Proveedores y Compras:** `suppliers`, `purchase_orders`, `purchase_order_items`.
5. **Ventas y TPV:** `sales`, `sale_items`, `sale_payments`, `ticket_settings`.
6. **Caja y Tesorería:** `cash_shifts`, `cash_movements`, `cash_session_denominations`.
7. **Analítica y Comisiones:** `commissions`, `commission_records`.
8. **Catálogo B2B / Crowdsourced:** `community_catalog_submissions`, `community_verified_catalog`.
9. **WhatsApp y Canales:** `whatsapp_catalog_settings`, `whatsapp_orders`.

---

## 3. 💳 MÓDULO DE SUSCRIPCIONES Y FACTURACIÓN SAAS (DÍA 14)

### 3.1 Catálogo de Planes Oficial
| Plan Tier | Tarifa Mensual (MXN) | Límite Usuarios | Límite Sucursales/Almacenes |
|---|---|---|---|
| **EMPRENDEDOR** | \$199.00 | Hasta 2 | 1 Almacén |
| **COMERCIO** | \$399.00 | Hasta 5 | Multi-almacén (hasta 3) |
| **CORPORATIVO** | \$699.00 | Hasta 15 | Multi-almacén (hasta 10) |

### 3.2 Endpoints del Módulo SaaS
Todos bajo `/api/v1`:

| Método | Endpoint | Descripción | Acceso / Auth |
|---|---|---|---|
| `GET` | `/api/v1/saas/plans` | Lista los 3 planes con características, límites y precio | Público / Exento |
| `GET` | `/api/v1/subscription` | Consulta el estado del tenant (`ACTIVE`, `SOFT_LOCK`, `HARD_LOCK`) y consumo | Autenticado |
| `POST` | `/api/v1/subscription/change-plan` | Solicita cambio de plan (valida capacidades en downgrade) | Dueño / Admin |
| `GET` | `/api/v1/billing/invoices` | Historial de facturas mensuales del tenant | Dueño / Admin |
| `GET` | `/api/v1/billing/invoices/{id}` | Detalle de factura específica | Dueño / Admin |
| `GET` | `/api/v1/billing/invoices/{id}/payment-methods` | Genera CLABE STP de 18 dígitos y código de barras OXXO de 14 dígitos | Dueño / Admin |
| `POST` | `/api/v1/webhooks/spei/payment-confirmation` | Webhook de confirmación de transferencia SPEI (reactiva cuenta) | Exento / Webhook Key |
| `POST` | `/api/v1/webhooks/oxxo/payment-confirmation` | Webhook de pago en tiendas OXXO (reactiva cuenta) | Exento / Webhook Key |

---

## 4. 💵 MÓDULO DE CAJA Y ARQUEO CON CONO BANXICO

### 4.1 Catálogo de 12 Denominaciones del Banco de México
Tanto el Backend (`BanxicoDenominationsInput`) como el Frontend (`BanxicoCatalog`) utilizan las mismas claves exactas:
- **Billetes (6):** `bills_1000` ($1000), `bills_500` ($500), `bills_200` ($200), `bills_100` ($100), `bills_50` ($50), `bills_20` ($20).
- **Monedas (6):** `coins_20` ($20), `coins_10` ($10), `coins_5` ($5), `coins_2` ($2), `coins_1` ($1), `coins_050` ($0.50).

### 4.2 Endpoints del Módulo de Caja
Todos bajo `/api/v1/cash/*`:

| Método | Endpoint | Payload Clave | Respuesta / Efecto |
|---|---|---|---|
| `POST` | `/api/v1/cash/open-session` | `{"opening_amount_mxn": 500.0, "opening_denominations": {...}}` | Abre turno, guarda desglose en `cash_session_denominations` |
| `POST` | `/api/v1/cash/close-session` | `{"shift_id": "uuid", "physical_denominations": {...}}` | Calcula total físico, balance (`EXACT`, `SHORT`, `OVER`) y cierra |
| `GET` | `/api/v1/cash/active-session` | Ninguno (toma usuario autenticado) | Retorna turno abierto o 404 si no hay turno |
| `GET` | `/api/v1/cash/sessions` | `?skip=0&limit=20` | Lista histórica de turnos |
| `GET` | `/api/v1/cash/sessions/{id}` | UUID de turno | Detalle del turno |
| `POST` | `/api/v1/cash/sessions/{id}/movements` | `{"movement_type": "ENTRY"\|"EXPENSE", "amount_mxn": 150.0}` | Entrada/salida manual autorizada |
| `GET` | `/api/v1/cash/sessions/{id}/report` | UUID de turno | Generación de Corte Z con desglose completo |

---

## 5. 📊 MÓDULO DE ANALÍTICAS Y COMISIONES

### 5.1 Endpoint Canónico
- **Ruta:** `GET /api/v1/analytics/commissions?period_month=YYYY-MM`
- **Estructura de Respuesta JSON:**
```json
{
  "period": "2026-09",
  "total_commissions_mxn": 94.50,
  "total_sales_count": 28,
  "cashiers": [
    {
      "cashier_id": "9b1deb4d-3b7d-4bad-9bdd-2b0d7b3dcb6d",
      "cashier_name": "Ana García",
      "total_sales_mxn": 1890.00,
      "earned_commission_mxn": 94.50,
      "sales_count": 28
    }
  ],
  "ranking": [
    {
      "cashier_name": "Ana García",
      "commission_mxn": 94.50,
      "is_current_user": true
    }
  ],
  "summaries_by_user": [...]
}
```

---

## 6. 🔄 MATRIZ DE SINCRONIZACIÓN BACKEND ⟷ FRONTEND

| Módulo | Backend FastAPI (Alan) | Frontend Flutter (Eduardo) |
|---|---|---|
| **Caja / Tesorería** | `backend/app/modules/cash_treasury/` | `frontend/lib/features/cash_treasury/` |
| **Ventas / TPV** | `backend/app/modules/sales_pos/` | `frontend/lib/features/sales_pos/` |
| **Inventario** | `backend/app/modules/inventory/` | `frontend/lib/features/inventory/` |
| **SaaS / Facturación** | `backend/app/modules/saas_billing/` | `frontend/lib/features/saas_admin/` |
| **Analítica / Comisiones**| `backend/app/modules/analytics_reports/`| `frontend/lib/features/analytics/` |
| **Proveedores / Compras**| `backend/app/modules/purchasing_suppliers/`| `frontend/lib/features/purchases/` |
| **Catálogo WhatsApp** | `backend/app/modules/whatsapp_catalog/` | `frontend/lib/features/whatsapp_catalog/` |
| **Red Comunitaria B2B** | `backend/app/modules/community_catalog/` | `frontend/lib/features/community_catalog/` |

---

## 7. 🧪 PROTOCOLO DE VERIFICACIÓN AUTOMATIZADA

Para asegurar cero regresiones antes de realizar cualquier commit o entrega:
1. **Backend:**
   ```bash
   cd backend
   .venv\Scripts\pytest.exe tests
   # Resultado esperado: 138 tests passed, 0 failed
   ```
2. **Frontend:**
   ```bash
   cd frontend
   flutter test
   # Resultado esperado: 191 tests passed, 0 failed
   ```
