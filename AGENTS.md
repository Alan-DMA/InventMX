# 📜 REGLAS DE GOBERNANZA PARA AGENTES DE IA (NEXUS v3.0)
## Leyes Inquebrantables de Desarrollo, Arquitectura y Trazabilidad

> **Este documento es la ley suprema de interacción técnica para todo agente de IA (Antigravity, Cursor, Copilot, Claude, Gemini, etc.) que trabaje en el repositorio Nexus MX.**  
> Ningún agente tiene autorización para violar, ignorar o eludir las reglas descritas a continuación bajo ninguna circunstancia.

---

### 1. 🗄️ REGLA DE BASE DE DATOS: ESQUEMA ÚNICO UNIVERSAL (`public`)
1. **Un solo esquema:** La base de datos PostgreSQL se llama **`nexus`** y TODO el modelo de datos reside exclusivamente en el esquema estándar **`public`**.
2. **Prohibición de esquemas secundarios:** Está terminantemente **PROHIBIDO** crear esquemas adicionales (como `inventmx`, `app`, `core`, etc.) o alterar el `search_path` de PostgreSQL.
3. **DDL y Migraciones:** Todas las sentencias DDL y migraciones de Alembic deben operar sobre `public` de forma explícita o por defecto.
4. **Row-Level Security (RLS):** Toda tabla transaccional multi-tenant debe tener habilitado `ENABLE ROW LEVEL SECURITY;` y `FORCE ROW LEVEL SECURITY;` con política estricta vinculada a `app.current_tenant`.
5. **Cero residuos:** Está prohibido dejar tablas temporales, huérfanas o remanentes de versiones antiguas en la base de datos.

---

### 2. 📡 REGLA DE ENDPOINTS: CONTRATO OPENAPI COMO FUENTE ÚNICA DE VERDAD
1. **Inspección previa obligatoria:** Antes de escribir una sola línea de código en controladores de FastAPI o clientes Dio en Flutter, el agente **DEBE consultar** la carpeta `docs/api/` (`docs/api/openapi.yaml`).
2. **Prohibición de rutas inventadas:** Está terminantemente **PROHIBIDO** crear rutas ad-hoc o cambiar prefijos de módulos.
   - ❌ **INCORRECTO:** Poner los turnos de caja en `/api/v1/sales/shifts/*` o comisiones en `/api/v1/sales/commissions/*`.
   - ✅ **CORRECTO:** Seguir la especificación formal: `/api/v1/cash/*` en `cash_treasury` y `/api/v1/analytics/commissions` en `analytics_reports`.
3. **Nomenclatura de endpoints:**
   - Todos los endpoints deben usar `kebab-case` (ej: `/open-session`, `/parse-receipt`, `/payment-methods`).
   - Identificadores expuestos en URLs deben ser `UUID v4` (`/{id}`).
   - La raíz de la API es siempre `/api/v1`.

---

### 3. 👥 REGLA DE SINCRONIZACIÓN ALAN (BACKEND) & EDUARDO (FRONTEND)
1. **Trazabilidad bidireccional:** Cada funcionalidad debe implementarse de forma consistente entre el Backend y el Frontend:
   - Si Alan crea un endpoint, el contrato de payload y respuesta debe coincidir exactamente con lo que Eduardo espera en el repositorio de Flutter (`frontend/lib/features/*/data/*repository*.dart`).
   - Si Eduardo define un DTO o enum en Flutter (ej. `BanxicoCatalog`, `CashSessionStatus`), el backend debe aceptar y retornar esos valores exactos en JSON.
2. **Módulos espejo:**
   - `backend/app/modules/cash_treasury/` ⟷ `frontend/lib/features/cash_treasury/`
   - `backend/app/modules/saas_billing/` ⟷ `frontend/lib/features/saas_admin/`
   - `backend/app/modules/sales_pos/` ⟷ `frontend/lib/features/sales_pos/`
   - `backend/app/modules/inventory/` ⟷ `frontend/lib/features/inventory/`
   - `backend/app/modules/analytics_reports/` ⟷ `frontend/lib/features/analytics/`
   - `backend/app/modules/purchasing_suppliers/` ⟷ `frontend/lib/features/purchases/`
   - `backend/app/modules/whatsapp_catalog/` ⟷ `frontend/lib/features/whatsapp_catalog/`
   - `backend/app/modules/community_catalog/` ⟷ `frontend/lib/features/community_catalog/`
3. **Prohibición de Mocks permanentes:** Los repositorios de Flutter pueden incluir Mocks únicamente durante el desarrollo preliminar, pero deben conectarse a los endpoints reales de FastAPI en cuanto el backend esté disponible.

---

### 4. 📝 REGLA DE CALIDAD DE CÓDIGO: COMENTARIOS LÍNEA POR LÍNEA
1. **Documentación exhaustiva:** Todo código producido por agentes debe estar **comentado línea por línea o bloque por bloque funcional**, explicando el *por qué* y la regla de negocio que respalda.
2. **Clean Architecture estricta:**
   - Backend: `domain/` ➔ `schemas/` ➔ `repositories/` ➔ `services/` ➔ `api/`.
   - Frontend: `presentation/` ➔ `domain/` ➔ `data/`.
3. **Tipado fuerte:**
   - En Python: Tipado estático completo con Pydantic v2, `Decimal` para montos en MXN (jamás `float`), y enums nativos de Python.
   - En Dart: Modelos inmutables con `Equatable`, manejo de estado con Riverpod y DTOs con `toMap` / `fromMap`.

---

### 5. 🧪 REGLA DE VERIFICACIÓN AUTOMATIZADA: CERO REGRESIONES
1. **Ejecución obligatoria:** Todo cambio realizado por un agente debe verificarse ejecutando:
   - Backend: `pytest tests` (desde `backend/`).
   - Frontend: `flutter test` (desde `frontend/`).
2. **Cero fallos tolerados:** Ningún commit ni entrega es válida si un solo test preexistente falla.
3. **Prohibición de scripts de depuración en la raíz:** Scripts como `test_checkout_debug.py` no deben vivir en la raíz del proyecto para evitar interferir con la recolección automática de pruebas.
