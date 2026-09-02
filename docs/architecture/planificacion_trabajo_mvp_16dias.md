# PLANIFICACIÓN DE TRABAJO DEL MVP (16 DÍAS)
## Nexus v3.0 — Sistema de Gestión Comercial Modular (Retail México)

> **Duración Total:** 16 Días Laborales  
> **Jornada Diaria:** 6 Horas / Día por Desarrollador  
> **Capacidad Total:** 96 Horas / Desarrollador (192 Horas Totales del Equipo)  
> **Metodología:** Flujo de Trabajo Agéntico Asistido (Spec-Driven + Clean Architecture)  
> **Regla de Granularidad:** Toda tarea de 4 o más horas está rigurosamente subdividida en subtareas de $\le 2-3$ horas.

---

## 👥 ASIGNACIÓN DE ROLES Y RESPONSABILIDADES

| Responsable | Rol Principal | Enfoque de Desarrollo en el MVP |
|---|---|---|
| **Alan** | Co-Fundador & Lead Architect | **Backend & Core Engineering:** PostgreSQL DDL con RLS, FastAPI Modular, Servicios de Negocio, Algoritmo de Consenso Crowdsourced, Webhooks SPEI/OXXO y Seguridad. |
| **Eduardo** | Co-Fundador & Lead Operations | **Frontend, UX & QA:** Flutter Feature-First, Riverpod State, UI Components, Wizard Banxico, Google ML Kit OCR On-Device, Dictado de Voz y Pruebas en Campo. |

---

## 📅 CRONOGRAMA MAESTRO DÍA A DÍA (16 DÍAS)

```mermaid
gantt
    title Plan de Desarrollo MVP 16 Días - Nexus v3.0 (México)
    dateFormat  YYYY-MM-DD
    axisFormat  Día %j
    
    section Semana 1: Fundación & Inventario
    D1: Fundación Core, RLS & Shell UI         :d1, 2026-09-01, 1d
    D2: RBAC, Middleware & Onboarding Gamificado:d2, 2026-09-02, 1d
    D3: Inventario 3 Campos & Ficha Detalle    :d3, 2026-09-03, 1d
    D4: Combos, Stock TTL & Traslados          :d4, 2026-09-04, 1d
    D5: Mapeo Excel & Escaneo Góndola Batch    :d5, 2026-09-05, 1d
    
    section Semana 2: POS, Caja & Compras
    D6: POS Checkout & Lazy Loading Just-in-Time:d6, 2026-09-08, 1d
    D7: Pagos Mixtos & Calculadora Vuelto MXN  :d7, 2026-09-09, 1d
    D8: Notas de Venta Ticket & Comisiones     :d8, 2026-09-10, 1d
    D9: Módulo de Caja & Wizard Cono Banxico   :d9, 2026-09-11, 1d
    D10: Auditoría Descuadres & Cierre de Turno:d10, 2026-09-12, 1d
    
    section Semana 3: Compras, OCR & Canales
    D11: Compras, Proveedores & Cuentas x Pagar:d11, 2026-09-15, 1d
    D12: OCR Facturas On-Device & Dictado Voz  :d12, 2026-09-16, 1d
    D13: Catálogo Digital WhatsApp Web & SSR   :d13, 2026-09-17, 1d
    D14: Suscripciones SaaS (SPEI / OXXO Pay)  :d14, 2026-09-18, 1d
    
    section Semana 4: Red Comunitaria & Release
    D15: Catálogo Semilla & Consenso 3 Tenants :d15, 2026-09-21, 1d
    D16: Hardening RLS, Testing E2E & Piloto MX:d16, 2026-09-22, 1d
```

---

## 📋 DETALLE DE MÓDULOS, TAREAS Y SUBTAREAS

---

### MÓDULO 01: ARQUITECTURA CORE, MULTI-TENANCY Y AUTENTICACIÓN

#### 🗓️ DÍA 1: Setup de Infraestructura, Base de Datos RLS y Shell UI

##### Tarea 1.1: Core Backend & Esquema PostgreSQL Multi-tenant con RLS
- **Responsable:** Alan
- **Tiempo Total Estimado:** 6 Horas
- **Dependencias:** Ninguna (Inicio del proyecto)
- **Subtareas:**
  - **1.1.1 (2.0h):** Configuración de FastAPI, SQLAlchemy Async Engine, `alembic` y variables de entorno `.env` en `app/core/config/` y `app/core/database/`.
  - **1.1.2 (2.0h):** Creación del script DDL de migraciones PostgreSQL con tablas `tenants`, `users`, `roles`, `permissions` y función de inyección de contexto RLS (`SET app.current_tenant`).
  - **1.1.3 (2.0h):** Implementación de políticas de seguridad Row-Level Security (RLS) en todas las tablas y suite de pruebas pytest de aislamiento multi-tenant.
- **Entregable:** Base de datos relacional operativa con RLS estricto y 100% de aislamiento verificado entre comercios.

##### Tarea 1.2: Shell de Flutter, Design System y Conexión de Red
- **Responsable:** Eduardo
- **Tiempo Total Estimado:** 6 Horas
- **Dependencias:** Ninguna
- **Subtareas:**
  - **1.2.1 (2.0h):** Setup de Flutter, estructura de carpetas Feature-First, configuración de `AppTheme` (paleta oscura/clara, tipografía Inter y JetBrains Mono) en `lib/core/theme/`.
  - **1.2.2 (2.0h):** Configuración del cliente HTTP `Dio` con `AuthInterceptor` (inyección de JWT, manejo de refresh token y timeout) en `lib/core/network/`.
  - **1.2.3 (2.0h):** Implementación de la pantalla de Login (`auth/presentation/login_screen.dart`), almacenamiento local de sesión en `Hive` y enrutamiento con `GoRouter`.
- **Entregable:** Aplicación Flutter compilando en Android/Web con autenticación persistente y tema corporativo.

---

#### 🗓️ DÍA 2: RBAC Granular, Middleware de Suscripción y Onboarding Gamificado

##### Tarea 2.1: Matriz de Permisos RBAC y Middleware de Morosidad
- **Responsable:** Alan
- **Tiempo Total Estimado:** 6 Horas
- **Dependencias:** Tarea 1.1
- **Subtareas:**
  - **2.1.1 (2.0h):** Implementación de servicios de autenticación JWT (Access 15m + Refresh 7d) y hashing seguro con `bcrypt` en `modules/auth_tenancy/services/`.
  - **2.1.2 (2.0h):** Matriz de permisos granular (`permissions`) y decorador/dependency injection `@require_permission` en controladores FastAPI.
  - **2.1.3 (2.0h):** Middleware de verificación de estados de suscripción (`ACTIVE`, `SOFT_LOCK` ➔ 403 en creación, `HARD_LOCK` ➔ 403 total).
- **Entregable:** Endpoints de autenticación y protección granular por roles y morosidad.

##### Tarea 2.2: Onboarding Gamificado y Setup Asistido (UI)
- **Responsable:** Eduardo
- **Tiempo Total Estimado:** 6 Horas
- **Dependencias:** Tarea 1.2
- **Subtareas:**
  - **2.2.1 (2.0h):** Diseño de la barra de progreso de onboarding y tarjetas de hitos iniciales (*"¡Registra tus primeros 50 productos!"*) en `features/onboarding/presentation/`.
  - **2.2.2 (2.0h):** Asistente paso a paso (Wizard) para configurar datos del comercio (Nombre, Almacén inicial, preferencias de ticket).
  - **2.2.3 (2.0h):** Diálogo de recompensa por completar setup (activación de beneficio de 1 mes gratis o badge de activación) con persistencia en estado Riverpod.
- **Entregable:** Flujo de bienvenida gamificado que reduce el abandono inicial del comerciante.

---

### MÓDULO 02: INVENTARIO, 3 CAMPOS VITALES Y CATÁLOGO EAN-13

#### 🗓️ DÍA 3: Modelo de Inventario MXN y Ficha de Detalle de Producto

##### Tarea 3.1: Backend de Inventario, 3 Campos Vitales y Multi-almacén
- **Responsable:** Alan
- **Tiempo Total Estimado:** 6 Horas
- **Dependencias:** Tarea 2.1
- **Subtareas:**
  - **3.1.1 (2.0h):** Modelos y esquemas Pydantic para `products` (`name`, `price_mxn`, `cost_mxn`, `cost_usd_import`, `sku`), `categories` y `warehouses` en `modules/inventory/`.
  - **3.1.2 (2.0h):** Lógica de autogeneración de SKU (`NEX-XXXXX`), categoría "General" automática y endpoint rápido de creación de 3 campos vitales.
  - **3.1.3 (2.0h):** Endpoints CRUD de productos con filtros por categoría, búsqueda por trigramas (`pg_trgm`) y filtro de stock bajo.
- **Entregable:** API de inventario optimizada para Pesos Mexicanos con soporte multi-almacén.

##### Tarea 3.2: UI de Inventario, Ficha de Detalle y Formulario 3 Campos
- **Responsable:** Eduardo
- **Tiempo Total Estimado:** 6 Horas
- **Dependencias:** Tarea 1.2
- **Subtareas:**
  - **3.2.1 (2.0h):** Pantalla principal de Inventario (`inventory_screen.dart`): Buscador píldora con cámara, chips de filtro (*Todos*, *Categoría ▾*, *⚠️ Stock bajo*) y lista de tarjetas.
  - **3.2.2 (2.0h):** Pantalla de Detalle de Producto (`product_detail_screen.dart`): Banner fotográfico, precios en $ MXN, desglose de margen %, tarjetas pastel (*DISPONIBLE* / *RESERVADO*).
  - **3.2.3 (2.0h):** Modal ultra-rápido de 3 campos vitales (Nombre, Precio MXN, Stock) que autocompleta en menos de 5 segundos.
- **Entregable:** Interfaz completa de inventario idéntica a los bocetos visuales aprobados.

---

#### 🗓️ DÍA 4: Combos, Stock Reservado con TTL y Traslados entre Almacenes

##### Tarea 4.1: Backend de Combos, Stock TTL (15 min) y Kardex
- **Responsable:** Alan
- **Tiempo Total Estimado:** 6 Horas
- **Dependencias:** Tarea 3.1
- **Subtareas:**
  - **4.1.1 (2.0h):** Modelado de `combos` y `combo_items` con validación de existencia de componentes en `modules/inventory/domain/`.
  - **4.1.2 (2.0h):** Mecanismo de reserva de stock con TTL de 15 minutos y tarea en background (Cron/Asyncio) para liberación automática de artículos expirados.
  - **4.1.3 (2.0h):** Registro histórico en tabla `inventory_movements` (Kardex: entradas, salidas, mermas, traslados) con transacciones ACID.
- **Entregable:** Lógica de combos comerciales, liberación de stock no cobrado y trazabilidad total en Kardex.

##### Tarea 4.2: UI de Ajustes Físicos, Traslado de Almacenes e Impresión de Etiquetas
- **Responsable:** Eduardo
- **Tiempo Total Estimado:** 6 Horas
- **Dependencias:** Tarea 3.2
- **Subtareas:**
  - **4.2.1 (2.0h):** Diálogo de Ajuste Físico de Stock (+ Entrada / — Salida con motivo: Conteo físico, Merma, Devolución).
  - **4.2.2 (2.0h):** Modal interactivo de Traslado entre Almacenes (Origen ➔ Destino) con validación de saldo disponible.
  - **4.2.3 (2.0h):** Modal de Vista Previa e Impresión de Etiquetas para góndola con código de barras y precio en $ MXN.
- **Entregable:** Cuadrícula de 4 acciones de almacén totalmente operativas en la UI.

---

#### 🗓️ DÍA 5: Importador Flexible Excel y Escaneo Continuo de Góndola

##### Tarea 5.1: Backend de Importación Flexible y Catálogo Semilla EAN-13 Base
- **Responsable:** Alan
- **Tiempo Total Estimado:** 6 Horas
- **Dependencias:** Tarea 3.1
- **Subtareas:**
  - **5.1.1 (2.5h):** Servicio de procesamiento dinámico de archivos Excel/CSV (`openpyxl`) con mapeo visual de columnas personalizadas por el usuario.
  - **5.1.2 (2.0h):** Base de datos precargada (Tier 1) con los Top 1,000 abarrotes de mayor rotación en México (EAN-13 GS1, nombres oficiales y categorías).
  - **5.1.3 (1.5h):** Endpoint `/inventory/lookup-ean/{barcode}` para resolución instantánea de códigos de barra en < 5ms.
- **Entregable:** Motor de carga masiva sin plantillas rígidas y resolución de productos estándar de abarrotes.

##### Tarea 5.2: UI de Mapeo Visual de Excel y Modo Góndola en Ráfaga
- **Responsable:** Eduardo
- **Tiempo Total Estimado:** 6 Horas
- **Dependencias:** Tarea 3.2, 5.1
- **Subtareas:**
  - **5.2.1 (3.0h):** Interfaz visual de mapeo interactivo de columnas (*"¿Cuál columna de tu archivo es 'Precio'?"*) con previsualización de datos.
  - **5.2.2 (3.0h):** Modo "Escaneo Continuo de Góndola": cámara activa en ráfaga, detección de código EAN, autocompletado y teclado numérico gigante para precio/stock sin cambiar de pantalla.
- **Entregable:** Herramientas de alta velocidad que permiten digitalizar 100 artículos en menos de 15 minutos.

---

### MÓDULO 03: PUNTO DE VENTA (POS), CHECKOUT Y VUELTO MXN

#### 🗓️ DÍA 6: POS Checkout, Máquina de Estados y Lazy Loading en Venta

##### Tarea 6.1: Backend de Checkout POS y Lazy Loading de Productos
- **Responsable:** Alan
- **Tiempo Total Estimado:** 6 Horas
- **Dependencias:** Tarea 3.1, 4.1
- **Subtareas:**
  - **6.1.1 (2.0h):** Endpoint `POST /api/v1/sales/checkout` con validación de stock atómico, congelamiento de `unit_cost_mxn` y máquina de estados (`DRAFT` ➔ `PAID` ➔ `COMPLETED`).
  - **6.1.2 (2.0h):** Lógica de *Lazy Loading / Inventario Orgánico*: si un producto escaneado no existe, se crea automáticamente en `products` con los datos mínimos ingresados en la venta.
  - **6.1.3 (2.0h):** Pruebas unitarias de concurrencia y prevención de sobreventa en PostgreSQL.
- **Entregable:** Motor transaccional de ventas resistente a alta concurrencia con registro Just-in-Time.

##### Tarea 6.2: UI de Punto de Venta (POS), Carrito y Búsqueda Fuzzy
- **Responsable:** Eduardo
- **Tiempo Total Estimado:** 6 Horas
- **Dependencias:** Tarea 3.2
- **Subtareas:**
  - **6.2.1 (2.0h):** Pantalla de Checkout (`checkout_screen.dart`): Buscador píldora permanente con cámara, lista de artículos con controles (+ / -) y subtotal en vivo.
  - **6.2.2 (2.0h):** Botón flotante punteado "+ Agregar producto al vuelo" con modal ultra-rápido que no detiene el flujo de la venta.
  - **6.2.3 (2.0h):** Panel inferior fijo con desglose de Subtotal en `$ MXN` y botón principal "Cobrar $ XX.XX".
- **Entregable:** Pantalla de ventas ágil, intuitiva y optimizada para smartphone o tablet de mostrador.

---

#### 🗓️ DÍA 7: Pagos Mixtos y Calculadora Rápida de Cambio MXN

##### Tarea 7.1: Backend de Pagos Mixtos y Registro Contable
- **Responsable:** Alan
- **Tiempo Total Estimado:** 6 Horas
- **Dependencias:** Tarea 6.1
- **Subtareas:**
  - **7.1.1 (2.0h):** Tabla `sale_payments` con soporte para métodos: `CASH_MXN`, `SPEI`, `CODI`, `CARD_TPV` y referencias bancarias.
  - **7.1.2 (2.0h):** Validación de suma exacta de pagos mixtos versus total de la venta y cálculo del vuelto entregado.
  - **7.1.3 (2.0h):** Registro contable sin bloqueo de webhooks bancarios (respetando la separación financiera del Art. III).
- **Entregable:** API robusta para cobros fraccionados y múltiples formas de pago en pesos.

##### Tarea 7.2: UI de Modal de Cobro y Calculadora de Vuelto MXN
- **Responsable:** Eduardo
- **Tiempo Total Estimado:** 6 Horas
- **Dependencias:** Tarea 6.2
- **Subtareas:**
  - **7.2.1 (2.0h):** Modal de cobro con pestañas de métodos de pago (Efectivo, SPEI, Tarjeta/TPV, Mixto).
  - **7.2.2 (2.0h):** Calculadora de cambio en efectivo con botones de acceso rápido para billetes de **$50, $100, $200 y $500 MXN** y monto exacto.
  - **7.2.3 (2.0h):** Campo de captura de referencia para transferencias SPEI o autorización de TPV Clip/Mercado Pago.
- **Entregable:** Experiencia de cobro sin errores de cambio en efectivo y soporte de transferencias.

---

#### 🗓️ DÍA 8: Notas de Venta (Ticket 58/80mm) y Comisiones de Empleados

##### Tarea 8.1: Backend de Comprobantes Internos y Comisiones Dinámicas
- **Responsable:** Alan
- **Tiempo Total Estimado:** 6 Horas
- **Dependencias:** Tarea 7.1
- **Subtareas:**
  - **8.1.1 (2.0h):** Generador de comprobantes administrativos tipo *Nota de Venta* con folio consecutivo, fecha/hora y desglose informativo de IVA.
  - **8.1.2 (2.0h):** Motor de cálculo de comisiones para personal de ventas (porcentaje sobre volumen o margen de ganancia) asociado a `user_id`.
  - **8.1.3 (2.0h):** Endpoints de reportes de comisiones acumuladas por vendedor y periodo.
- **Entregable:** API de notas de venta y liquidación de comisiones de personal.

##### Tarea 8.2: UI de Ticket Imprimible, Compartir WhatsApp y Tablero de Comisiones
- **Responsable:** Eduardo
- **Tiempo Total Estimado:** 6 Horas
- **Dependencias:** Tarea 7.2
- **Subtareas:**
  - **8.2.1 (2.5h):** Formato visual de ticket térmico (58mm / 80mm) y generación de comprobante digital en PDF.
  - **8.2.2 (1.5h):** Botón para compartir nota de venta directamente por WhatsApp al cliente.
  - **8.2.3 (2.0h):** Tablero de rendimiento de empleados (`SR-05`) con comisiones acumuladas en tiempo real.
- **Entregable:** Emisión de tickets físicos/digitales y gamificación del desempeño del equipo de ventas.

---

### MÓDULO 04: CAJA, ARQUEO Y CONO MONETARIO BANXICO

#### 🗓️ DÍA 9: Apertura/Cierre de Caja y Desglose de Denominaciones Banxico

##### Tarea 9.1: Backend de Sesiones de Caja y Denominaciones Banxico
- **Responsable:** Alan
- **Tiempo Total Estimado:** 6 Horas
- **Dependencias:** Tarea 7.1
- **Subtareas:**
  - **9.1.1 (2.0h):** Modelado de `cash_registers`, `cash_sessions` y la tabla `cash_session_denominations` en `modules/cash_treasury/`.
  - **9.1.2 (2.0h):** Endpoint `POST /api/v1/cash/open-session` con registro del fondo de caja inicial en MXN.
  - **9.1.3 (2.0h):** Endpoint `POST /api/v1/cash/close-session` que procesa el conteo físico de billetes ($20 a $1000) y monedas ($0.50 a $20) de Banxico.
- **Entregable:** Estructura completa de auditoría física de caja según el cono monetario mexicano.

##### Tarea 9.2: UI del Asistente Visual de Cierre de Caja (Wizard Banxico)
- **Responsable:** Eduardo
- **Tiempo Total Estimado:** 6 Horas
- **Dependencias:** Tarea 7.2
- **Subtareas:**
  - **9.2.1 (2.5h):** Wizard guiado paso a paso con ilustraciones de billetes oficiales ($20, $50, $100, $200, $500, $1000 MXN) y campos de conteo rápido.
  - **9.2.2 (2.0h):** Paso de conteo de monedas ($0.50, $1, $2, $5, $10, $20 MXN) con sumatoria instantánea en tiempo real.
  - **9.2.3 (1.5h):** Resumen de ingresos digitales (SPEI total, TPV tarjetas, CoDi) para cotejo del cajero.
- **Entregable:** Interfaz visual amigable que elimina los errores manuales en los cortes de turno.

---

#### 🗓️ DÍA 10: Auditoría de Descuadres y Reporte de Cierre de Turno

##### Tarea 10.1: Backend de Conciliación de Caja y Detección de Descuadres
- **Responsable:** Alan
- **Tiempo Total Estimado:** 6 Horas
- **Dependencias:** Tarea 9.1
- **Subtareas:**
  - **10.1.1 (2.0h):** Algoritmo de comparación entre saldo teórico del sistema (Ventas + Fondo - Retiros) vs. saldo físico contado.
  - **10.1.2 (2.0h):** Registro de movimientos de caja extraordinarios (`cash_movements`: entradas de efectivo, retiros para proveedores, gastos chicos).
  - **10.1.3 (2.0h):** Generación de reporte de corte Z/X con métricas de faltantes o sobrantes.
- **Entregable:** API de control financiero y auditoría estricta de turnos.

##### Tarea 10.2: UI de Reporte de Cuadre de Caja y Exportación
- **Responsable:** Eduardo
- **Tiempo Total Estimado:** 6 Horas
- **Dependencias:** Tarea 9.2, 10.1
- **Subtareas:**
  - **10.2.1 (2.0h):** Pantalla de resultado del arqueo: Indicadores visuales de cuadre exacto (verde) o discrepancias (rojo/ámbar).
  - **10.2.2 (2.0h):** Modal para registrar entradas/salidas de efectivo de caja menor durante el turno.
  - **10.2.3 (2.0h):** Impresión del ticket de corte de caja en impresora térmica y exportación a PDF.
- **Entregable:** Pantallas de auditoría y cierre de operaciones de caja para dueños y supervisores.

---

### MÓDULO 05: COMPRAS, PROVEEDORES Y OCR ON-DEVICE

#### 🗓️ DÍA 11: Módulo de Compras, Proveedores y Cuentas por Pagar

##### Tarea 11.1: Backend de Compras y Cuentas por Pagar a Proveedores
- **Responsable:** Alan
- **Tiempo Total Estimado:** 6 Horas
- **Dependencias:** Tarea 3.1
- **Subtareas:**
  - **11.1.1 (2.0h):** Modelado de `suppliers`, `purchase_orders`, `purchase_items` y `accounts_payable` en `modules/purchasing_suppliers/`.
  - **11.1.2 (2.0h):** Lógica de recepción de mercancía: ingreso automático al inventario físico en el almacén seleccionado al aprobar la compra.
  - **11.1.3 (2.0h):** Módulo de cuentas por pagar en Pesos Mexicanos (registro de abonos, saldos y plazos de crédito).
- **Entregable:** API de abastecimiento y gestión de compromisos de pago con proveedores.

##### Tarea 11.2: UI de Compras, Directorio de Proveedores y Cuentas por Pagar
- **Responsable:** Eduardo
- **Tiempo Total Estimado:** 6 Horas
- **Dependencias:** Tarea 3.2
- **Subtareas:**
  - **11.2.1 (2.0h):** Pantalla de registro de compras con selección de proveedor, fecha y tabla de artículos entrantes.
  - **11.2.2 (2.0h):** Directorio de proveedores con historial de compras y datos de contacto comercial.
  - **11.2.3 (2.0h):** Tablero de cuentas por pagar con semáforo de vencimientos y registro de abonos.
- **Entregable:** Interfaz completa para control de compras y pagos a distribuidores.

---

#### 🗓️ DÍA 12: OCR On-Device de Facturas y Captura Asistida por Voz

##### Tarea 12.1: Backend Parser de Facturas y Normalización Heurística
- **Responsable:** Alan
- **Tiempo Total Estimado:** 6 Horas
- **Dependencias:** Tarea 11.1
- **Subtareas:**
  - **12.1.1 (2.5h):** Algoritmo de parseo heurístico de bloques de texto extraídos (regex para detección de `[CANT] [DESCRIPCION] [PRECIO UNIT] [TOTAL]`).
  - **12.1.2 (2.0h):** Endpoint de carga masiva de compra pre-parseada para revisión antes de confirmación.
  - **12.1.3 (1.5h):** Pruebas con facturas y notas de remisión típicas de proveedores mexicanos (Bimbo, PepsiCo, Sigma, Lala).
- **Entregable:** Motor de procesamiento estructurado de documentos comerciales físicos.

##### Tarea 12.2: Frontend OCR On-Device (ML Kit) y Dictado de Voz Nativo
- **Responsable:** Eduardo
- **Tiempo Total Estimado:** 6 Horas
- **Dependencias:** Tarea 11.2, 12.1
- **Subtareas:**
  - **12.2.1 (2.5h):** Integración de `google_mlkit_text_recognition` en Flutter para escaneo y extracción de texto 100% offline en el smartphone.
  - **12.2.2 (2.0h):** Pantalla de revisión interactiva de la factura escaneada antes de ingresar al inventario.
  - **12.2.3 (1.5h):** Integración del botón de micrófono para dictado de voz nativo en la creación rápida de productos (*"Coca-Cola 600, precio 18, 24 piezas"*).
- **Entregable:** Captura de facturas físicas a costo $0 de servidor y captura por voz operativa.

---

### MÓDULO 06: CATÁLOGO DIGITAL WHATSAPP Y SUSCRIPCIONES SAAS

#### 🗓️ DÍA 13: Catálogo Web Público y Generación de Pedidos por WhatsApp

##### Tarea 13.1: Backend de Catálogo Público y Renderizado SSR
- **Responsable:** Alan
- **Tiempo Total Estimado:** 6 Horas
- **Dependencias:** Tarea 3.1
- **Subtareas:**
  - **13.1.1 (2.0h):** Endpoints públicos de solo lectura `/catalog/{tenant_slug}` optimizados para alta concurrencia y caché.
  - **13.1.2 (2.0h):** Generación de metadata OpenGraph / SSR para previsualizaciones enriquecidas con foto y precio al compartir enlaces en WhatsApp.
  - **13.1.3 (2.0h):** Servicio de formateo de mensaje de pedido estructurado para WhatsApp con detalle de productos, total en $ MXN y dirección de entrega.
- **Entregable:** API pública del catálogo digital para clientes del comercio.

##### Tarea 13.2: UI del Catálogo Web Móvil y Botón de Compartir
- **Responsable:** Eduardo
- **Tiempo Total Estimado:** 6 Horas
- **Dependencias:** Tarea 1.2, 13.1
- **Subtareas:**
  - **13.2.1 (2.5h):** Interfaz pública web responsiva para clientes finales: vitrina de productos, buscador y carrito de compras.
  - **13.2.2 (2.0h):** Botón flotante "Enviar Pedido por WhatsApp" que abre la app de WhatsApp con el mensaje pre-armado.
  - **13.2.3 (1.5h):** Botón en el panel del comerciante para copiar y compartir el enlace de su catálogo en redes sociales.
- **Entregable:** Canal de ventas digital por WhatsApp completamente operativo para el comercio.

---

#### 🗓️ DÍA 14: Suscripciones SaaS (SPEI / OXXO Pay) y Panel de Fundadores

##### Tarea 14.1: Backend de Suscripciones SaaS, Webhooks SPEI y OXXO Pay
- **Responsable:** Alan
- **Tiempo Total Estimado:** 6 Horas
- **Dependencias:** Tarea 2.1
- **Subtareas:**
  - **14.1.1 (2.0h):** Modelado de `subscription_invoices`, `plans` ($199, $399, $699 MXN) y tabla de idempotencia de pagos.
  - **14.1.2 (2.0h):** Endpoints de webhooks para conciliación automática de transferencias SPEI (STP) y pagos en efectivo OXXO Pay.
  - **14.1.3 (2.0h):** Cron job de control de ciclo de vida de suscripción (`ACTIVE` ➔ `SOFT_LOCK` tras 10 días ➔ `HARD_LOCK`).
- **Entregable:** Motor de facturación y cobro automatizado del SaaS en moneda mexicana.

##### Tarea 14.2: UI del Panel de Administración SaaS y Gestión de Planes
- **Responsable:** Eduardo
- **Tiempo Total Estimado:** 6 Horas
- **Dependencias:** Tarea 1.2, 14.1
- **Subtareas:**
  - **14.2.1 (2.0h):** Pantalla de checkout de suscripción para el tenant con instrucciones de transferencia SPEI (CLABE) y código OXXO Pay.
  - **14.2.2 (2.5h):** Panel administrativo interno para Alan y Eduardo: métricas de MRR en $ MXN, lista de comercios y bandeja de aprobación manual.
  - **14.2.3 (1.5h):** Pantallas de aviso de morosidad con enlace de pago para cuentas en Soft Lock o Hard Lock.
- **Entregable:** Panel de control de ingresos para fundadores y flujo de suscripción para clientes.

---

### MÓDULO 07: RED COMUNITARIA CROWDSOURCED Y DESPLIEGUE FINAL

#### 🗓️ DÍA 15: Red Comunitaria con Consenso de 3 Comercios y Clonación

##### Tarea 15.1: Backend del Motor de Consenso Comunitario y Clonación
- **Responsable:** Alan
- **Tiempo Total Estimado:** 6 Horas
- **Dependencias:** Tarea 5.1
- **Subtareas:**
  - **15.1.1 (2.5h):** Tablas `community_catalog_submissions` y `community_verified_catalog` con algoritmo de consenso automático (promoción al alcanzar $\ge 3$ comercios independientes con similitud > 80%).
  - **15.1.2 (2.0h):** Servicio de clonación de catálogo maestro entre sucursales o tiendas aliadas en 1 clic (con cantidades en 0).
  - **15.1.3 (1.5h):** Endpoints de analítica avanzada y rentabilidad histórica para Plan Corporativo.
- **Entregable:** Motor de autocompletado comunitario autónomo y clonación de catálogos.

##### Tarea 15.2: UI de Sugerencias Comunitarias, Clonación y Dashboard Analítico
- **Responsable:** Eduardo
- **Tiempo Total Estimado:** 6 Horas
- **Dependencias:** Tarea 6.2, 15.1
- **Subtareas:**
  - **15.2.1 (2.0h):** Indicador visual en POS cuando un producto sugerido proviene del catálogo comunitario verificado.
  - **15.2.2 (2.0h):** Modal para clonar catálogo hacia una nueva sucursal mediante código o enlace seguro.
  - **15.2.3 (2.0h):** Dashboard analítico con gráficos de ventas, productos estrella y rentabilidad neta en `$ MXN`.
- **Entregable:** Experiencia completa de catálogo comunitario y reportes ejecutivos.

---

#### 🗓️ DÍA 16: Hardening de Seguridad RLS, Testing E2E y Despliegue Piloto

##### Tarea 16.1: Hardening de Seguridad, Optimización PostgreSQL y CI/CD
- **Responsable:** Alan
- **Tiempo Total Estimado:** 6 Horas
- **Dependencias:** Todos los módulos Backend
- **Subtareas:**
  - **16.1.1 (2.0h):** Auditoría integral de políticas RLS en todas las tablas y ejecución de suite completa de pruebas unitarias/integración pytest.
  - **16.1.2 (2.0h):** Optimización de índices relacionales, consultas complejas y configuración de script de backup diario automático a Cloudflare R2.
  - **16.1.3 (2.0h):** Configuración de pipeline CI/CD en GitHub Actions y despliegue en VPS de producción.
- **Entregable:** Backend en producción 100% blindado, seguro y optimizado.

##### Tarea 16.2: Pruebas de Humo UI, Validación en Smartphones Reales y Release
- **Responsable:** Eduardo
- **Tiempo Total Estimado:** 6 Horas
- **Dependencias:** Todos los módulos Frontend
- **Subtareas:**
  - **16.2.1 (2.0h):** Pruebas de humo completas de todos los flujos de usuario (Login ➔ Onboarding ➔ Inventario ➔ Venta POS ➔ Arqueo Caja).
  - **16.2.2 (2.0h):** Validación de rendimiento en smartphone Android de gama baja (escáner con cámara, fluidez de UI y tiempos de respuesta).
  - **16.2.3 (2.0h):** Generación de APK de release firmado y despliegue de Flutter Web para pruebas con las primeras 3 tienditas piloto.
- **Entregable:** Build final del MVP en producción listo para validación comercial en campo.

---

## 📊 RESUMEN DE DISTRIBUCIÓN DE CARGA HORARIA

| Desarrollador | Horas Backend / Infra | Horas Frontend / UX | Horas QA / Testing | Total Horas (16 Días) |
|---|---|---|---|---|
| **Alan** | 86.0 h | 0.0 h | 10.0 h | **96.0 h** |
| **Eduardo** | 0.0 h | 86.0 h | 10.0 h | **96.0 h** |
| **TOTAL EQUIPO** | **86.0 h** | **86.0 h** | **20.0 h** | **192.0 h** |
