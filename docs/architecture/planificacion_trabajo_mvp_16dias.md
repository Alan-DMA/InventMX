# PLANIFICACIÓN DE TRABAJO DEL MVP (16 DÍAS)
## Nexus v3.0 — Sistema de Gestión Comercial Modular (Retail México)
### Especificación Detallada de Tareas, Subtareas, Contexto, Objetivos e Historias de Usuario

> **Duración Total:** 16 Días Laborales  
> **Jornada Diaria:** 6 Horas / Día por Desarrollador  
> **Capacidad Total:** 96 Horas / Desarrollador (192 Horas Totales del Equipo)  
> **Metodología:** Flujo de Trabajo Agéntico Asistido (Spec-Driven + Clean Architecture)  
> **Regla de Granularidad:** Toda tarea de 4 o más horas está rigurosamente subdividida en subtareas de $\le 2-3$ horas con contexto, justificación, objetivo técnico/negocio e historia de usuario asociada.

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

## 📋 DESGLOSE DETALLADO POR DÍA, TAREAS Y SUBTAREAS

---

### 🗓️ DÍA 1: Setup de Infraestructura, Base de Datos RLS y Shell UI

#### Tarea 1.1: Core Backend & Esquema PostgreSQL Multi-tenant con RLS
- **Responsable:** Alan
- **Tiempo Total Estimado:** 6 Horas
- **Dependencias:** Ninguna (Inicio del proyecto)
- **Historia de Usuario / Caso de Uso:** `HU-01 / CU-01: Aislamiento Multi-tenant de Datos`  
  *"Como dueño de una tiendita de abarrotes, quiero que toda la información de mis ventas, costos e inventarios esté completamente aislada y protegida de otros comercios para garantizar la confidencialidad de mi negocio."*
- **Contexto y Justificación:** En un modelo SaaS Multi-tenant compartido, la seguridad no puede depender solo de filtros manuales `WHERE tenant_id = ...` en el código de la aplicación. Se requiere seguridad nativa en la base de datos (PostgreSQL Row-Level Security) desde el primer commit para evitar fugas de datos irreversibles (Constitución Art. I, Principio 3).
- **Objetivo:** Establecer el motor de base de datos asíncrono, las migraciones de esquemas base y el aislamiento por RLS que gobernará todas las consultas del sistema.
- **Subtareas:**
  - **1.1.1 (2.0h) — Setup FastAPI y Conexión Asíncrona:**
    - *Contexto:* Inicializar la estructura base de FastAPI y SQLAlchemy con `asyncpg`.
    - *Objetivo:* Configurar `app/core/config/` y `app/core/database/` con pool de conexiones optimizado para VPS y soporte de migraciones con Alembic.
  - **1.1.2 (2.0h) — DDL de Tablas Core e Inyección de Contexto RLS:**
    - *Contexto:* Definir las tablas `tenants`, `users`, `roles` y la función SQL que establece la variable de sesión `SET app.current_tenant = :tenant_id`.
    - *Objetivo:* Crear el script de migración inicial en PostgreSQL que activa RLS en todas las tablas transaccionales.
  - **1.1.3 (2.0h) — Suite de Pruebas de Aislamiento RLS en Pytest:**
    - *Contexto:* Validar matemáticamente que dos tenants distintos no puedan acceder a datos cruzados.
    - *Objetivo:* Implementar tests automatizados en `backend/tests/unit/` que simulan consultas simultáneas entre Tenant A y Tenant B, verificando que la base de datos rechace o filtre el 100% de los registros ajenos.

---

#### Tarea 1.2: Shell de Flutter, Design System y Conexión de Red
- **Responsable:** Eduardo
- **Tiempo Total Estimado:** 6 Horas
- **Dependencias:** Ninguna (Inicio del proyecto)
- **Historia de Usuario / Caso de Uso:** `HU-02 / CU-02: Inicio de Sesión y Experiencia Visual Mobile-First`  
  *"Como cajero o dueño de tienda, quiero una interfaz moderna, limpia y rápida que me permita iniciar sesión en mi smartphone y navegar de forma fluida."*
- **Contexto y Justificación:** La aplicación móvil es el punto de contacto directo del comerciante. El diseño visual debe coincidir estrictamente con la paleta de colores oscuros/claros, espaciados y tipografías corporativas, además de contar con un cliente HTTP seguro que administre tokens JWT.
- **Objetivo:** Construir el cascarón frontend de Flutter con tema visual, interceptores de autenticación y la pantalla de inicio de sesión conectada a almacenamiento local seguro.
- **Subtareas:**
  - **1.2.1 (2.0h) — Setup Flutter Feature-First y Design System:**
    - *Contexto:* Organizar la estructura de carpetas en `frontend/lib/` y definir estilos globales.
    - *Objetivo:* Implementar `AppTheme` con paleta corporativa oscura (Dark Slate `#0F172A`, Esmeralda `#10B981`, Acento `#38BDF8`), tipografía Inter/JetBrains Mono y widgets base en `lib/core/theme/`.
  - **1.2.2 (2.0h) — Cliente HTTP Dio y AuthInterceptor:**
    - *Contexto:* Las peticiones al backend requieren adjuntar automáticamente el token Bearer JWT y manejar la expiración.
    - *Objetivo:* Configurar `Dio` en `lib/core/network/` con manejo automático de refresco de tokens (`refresh_token`) y detección de pérdida de conexión a internet.
  - **1.2.3 (2.0h) — Pantalla de Login, Almacenamiento en Hive y GoRouter:**
    - *Contexto:* El usuario necesita ingresar sus credenciales y mantener la sesión iniciada en el dispositivo.
    - *Objetivo:* Crear `LoginScreen`, persistencia de sesión en `Hive` y enrutamiento reactivo con `GoRouter` para navegación segura.

---

### 🗓️ DÍA 2: RBAC Granular, Middleware de Suscripción y Onboarding Gamificado

#### Tarea 2.1: Matriz de Permisos RBAC y Middleware de Morosidad
- **Responsable:** Alan
- **Tiempo Total Estimado:** 6 Horas
- **Dependencias:** Tarea 1.1
- **Historia de Usuario / Caso de Uso:** `HU-03 / CU-03: Control de Roles y Control de Acceso por Suscripción`  
  *"Como dueño de negocio, quiero crear cuentas para mis cajeros limitando su acceso para que solo puedan cobrar y registrar ventas, impidiéndoles ver mis costos de compra o borrar inventario."*
- **Contexto y Justificación:** Los pequeños comercios tienen empleados con diferentes niveles de confianza. Asimismo, el SaaS requiere aplicar la máquina de estados de cobro (`ACTIVE`, `SOFT_LOCK` tras 10 días, `HARD_LOCK`) para proteger el modelo de negocio sin borrar datos del usuario.
- **Objetivo:** Desarrollar el sistema de control de acceso basado en roles (RBAC) y el middleware de cobro del SaaS en FastAPI.
- **Subtareas:**
  - **2.1.1 (2.0h) — Servicios de Autenticación JWT y Hashing Seguro:**
    - *Contexto:* Emisión y validación criptográfica de credenciales.
    - *Objetivo:* Implementar generación de Access Token (15 min) y Refresh Token (7 días) con `bcrypt` en `modules/auth_tenancy/services/`.
  - **2.1.2 (2.0h) — Matriz de Permisos RBAC y Decorador `@require_permission`:**
    - *Contexto:* Protección de endpoints según la acción a realizar (`inventory.view`, `sales.create`, `reports.view_profit`).
    - *Objetivo:* Crear decoradores de FastAPI que validan los permisos del usuario antes de ejecutar la lógica de los controladores.
  - **2.1.3 (2.0h) — Middleware de Morosidad (Máquina de Estados SaaS):**
    - *Contexto:* Si un comercio tiene su suscripción vencida, el sistema debe limitar la escritura sin bloquear la lectura histórica.
    - *Objetivo:* Interceptor que retorna `403 FORBIDDEN` en peticiones de creación si el tenant está en `SOFT_LOCK`, o bloqueo total si está en `HARD_LOCK`.

---

#### Tarea 2.2: Onboarding Gamificado y Setup Asistido (UI)
- **Responsable:** Eduardo
- **Tiempo Total Estimado:** 6 Horas
- **Dependencias:** Tarea 1.2
- **Historia de Usuario / Caso de Uso:** `HU-04 / CU-04: Onboarding Gamificado contra el Síndrome del Panel Vacío`  
  *"Como comerciante que recién instala Nexus, quiero un asistente visual divertido con una barra de progreso que me guíe paso a paso para configurar mi tienda y me dé recompensas al avanzar."*
- **Contexto y Justificación:** La principal causa de abandono de software de inventario es la frustración de ver una pantalla en blanco ("Cold Start"). Convertir la configuración en un juego con recompensas inmediatas (gamificación) eleva drásticamente la retención y activación de clientes (SR-01).
- **Objetivo:** Implementar la interfaz del asistente de bienvenida con barra de progreso, hitos diarios y desbloqueo de beneficios.
- **Subtareas:**
  - **2.2.1 (2.0h) — Barra de Progreso e Hitos Visuales de Setup:**
    - *Contexto:* Mostrar de forma clara el avance de configuración del negocio (0% a 100%).
    - *Objetivo:* Diseñar tarjetas de hitos (*"1. Registra tu tienda"*, *"2. Agrega tus primeros 10 artículos"*, *"3. Realiza tu primera venta"*) en `features/onboarding/presentation/`.
  - **2.2.2 (2.0h) — Wizard de Configuración de Datos del Comercio:**
    - *Contexto:* El usuario necesita ingresar el nombre de su comercio, almacén principal y encabezado del ticket.
    - *Objetivo:* Crear un flujo guiado en 3 pasos simples optimizado para teclado móvil.
  - **2.2.3 (2.0h) — Diálogo de Recompensa y Estado en Riverpod:**
    - *Contexto:* Al completar el setup en la primera semana, el usuario recibe una felicitación visual y un mes gratis de suscripción.
    - *Objetivo:* Crear la animación de logro, persistencia del estado en Riverpod y sincronización con el backend.

---

### 🗓️ DÍA 3: Modelo de Inventario MXN y Ficha de Detalle de Producto

#### Tarea 3.1: Backend de Inventario, 3 Campos Vitales y Multi-almacén
- **Responsable:** Alan
- **Tiempo Total Estimado:** 6 Horas
- **Dependencias:** Tarea 2.1
- **Historia de Usuario / Caso de Uso:** `HU-05 / CU-05: Registro de Productos Minimalista en Pesos Mexicanos`  
  *"Como comerciante, quiero registrar mis productos indicando únicamente Nombre, Precio ($ MXN) y Cantidad para no perder tiempo llenando formularios complejos de 20 campos."*
- **Contexto y Justificación:** En tienditas de abarrotes mexicanas, los empleados no tienen tiempo para clasificar impuestos complejos, marcas o SKUs largos al inicio. El sistema debe operar con la regla sagrada de los "3 Campos Vitales" y moneda nativa MXN (RF-02, SR-08).
- **Objetivo:** Desarrollar la capa de datos y endpoints de inventario en MXN con autogeneración de SKU y soporte multi-almacén.
- **Subtareas:**
  - **3.1.1 (2.0h) — Modelos y Schemas Pydantic de Productos en MXN:**
    - *Contexto:* Estructura de base de datos adaptada a México (`price_mxn`, `cost_mxn`, `cost_usd_import`, `sku`, `stock`).
    - *Objetivo:* Definir modelos SQLAlchemy y Schemas Pydantic en `modules/inventory/domain/` y `modules/inventory/schemas/`.
  - **3.1.2 (2.0h) — Autogenerador de SKU y Categorización por Defecto:**
    - *Contexto:* Si el usuario no tiene código de barras, el sistema genera uno único automáticamente (`NEX-XXXXX`).
    - *Objetivo:* Implementar generador secuencial de SKU y asignación automática de categoría "General" si no se especifica otra.
  - **3.1.3 (2.0h) — Endpoints CRUD y Búsqueda Fuzzy con Trigramas:**
    - *Contexto:* Búsqueda ágil de productos incluso con errores ortográficos (ej. "cocacola", "coca cola").
    - *Objetivo:* Endpoints `/inventory/products` con índices `pg_trgm` de PostgreSQL para respuestas en menos de 10ms.

---

#### Tarea 3.2: UI de Inventario, Ficha de Detalle y Formulario 3 Campos
- **Responsable:** Eduardo
- **Tiempo Total Estimado:** 6 Horas
- **Dependencias:** Tarea 1.2
- **Historia de Usuario / Caso de Uso:** `HU-05 / CU-06: Consulta y Gestión Visual de Inventario`  
  *"Como tendero, quiero ver la lista de mis productos con fotos, buscador por cámara y filtros de stock bajo, y poder ver el desglose de margen de ganancia de cada artículo."*
- **Contexto y Justificación:** La pantalla de inventario debe ser visualmente rica, permitiendo identificar rápidamente productos agotados y revisar la rentabilidad de cada producto según el boceto aprobado.
- **Objetivo:** Implementar la pantalla principal de inventario, la ficha de detalle del producto y el modal de alta en 3 campos en Flutter.
- **Subtareas:**
  - **3.2.1 (2.0h) — Pantalla Principal de Inventario (Listado y Filtros):**
    - *Contexto:* Lista fluida con scroll infinito, chips de filtro (*Todos*, *Categoría ▾*, *⚠️ Stock bajo*) y barra de búsqueda píldora con icono de cámara.
    - *Objetivo:* Construir `InventoryScreen` en `features/inventory/presentation/` respetando el diseño del boceto.
  - **3.2.2 (2.0h) — Pantalla de Detalle de Producto (`ProductDetailScreen`):**
    - *Contexto:* Vista detallada con banner fotográfico, precios en $ MXN, margen de ganancia calculado y tarjetas de existencias (*DISPONIBLE* y *RESERVADO*).
    - *Objetivo:* Construir la pantalla de detalle de producto modelada fielmente a la referencia visual aprobada.
  - **3.2.3 (2.0h) — Modal Minimalista de Alta en 3 Campos:**
    - *Contexto:* Formulario flotante de entrada rápida que pide solo Nombre, Precio MXN y Stock.
    - *Objetivo:* Widget con validación reactiva y feedback táctil que permite registrar artículos en menos de 5 segundos.

---

### 🗓️ DÍA 4: Combos, Stock Reservado con TTL y Traslados entre Almacenes

#### Tarea 4.1: Backend de Combos, Stock TTL (15 min) y Kardex
- **Responsable:** Alan
- **Tiempo Total Estimado:** 6 Horas
- **Dependencias:** Tarea 3.1
- **Historia de Usuario / Caso de Uso:** `HU-07 / CU-07: Control de Combos, Trazabilidad en Kardex y Stock Reservado`  
  *"Como comerciante, quiero vender promociones o combos (ej. 2 refrescos + 1 botana) que descuenten automáticamente los productos individuales, y que las compras no concretadas liberen el stock en 15 minutos."*
- **Contexto y Justificación:** Las promociones comerciales son comunes en México. Se debe asegurar la consistencia ACID del stock para no vender artículos inexistentes, registrando cada movimiento en el Kardex histórico (RF-03, RF-06).
- **Objetivo:** Desarrollar la lógica transaccional de combos, el cron job de expiración de reservas y la tabla de auditoría Kardex.
- **Subtareas:**
  - **4.1.1 (2.0h) — Modelado y Validación de Combos Promocionales:**
    - *Contexto:* Tablas `combos` y `combo_items` para vincular múltiples productos con un precio de venta consolidado en MXN.
    - *Objetivo:* Servicio que valida existencias atómicas de cada componente antes de permitir la venta del combo.
  - **4.1.2 (2.0h) — Mecanismo de Stock Reservado con TTL (15 min):**
    - *Contexto:* Cuando se inicia una venta en mostrador, el stock se aparta temporalmente para evitar colisiones.
    - *Objetivo:* Implementar cron job / worker asíncrono que libera automáticamente los ítems de ventas en `PENDING_PAYMENT` que superen los 15 minutos.
  - **4.1.3 (2.0h) — Motor de Kardex (`inventory_movements`):**
    - *Contexto:* Cada entrada, salida, ajuste, merma o traslado debe persistirse con fecha, usuario responsable y motivo.
    - *Objetivo:* Implementar triggers/servicios transaccionales de registro en Kardex para auditoría contable.

---

#### Tarea 4.2: UI de Ajustes Físicos, Traslado de Almacenes e Impresión de Etiquetas
- **Responsable:** Eduardo
- **Tiempo Total Estimado:** 6 Horas
- **Dependencias:** Tarea 3.2
- **Historia de Usuario / Caso de Uso:** `HU-06 / CU-08: Operaciones de Almacén y Etiquetas para Mostrador`  
  *"Como encargado de bodega, quiero realizar ajustes de stock por mermas o conteos físicos, trasladar mercancía a mi mostrador e imprimir etiquetas con código de barras para mis anaqueles."*
- **Contexto y Justificación:** La cuadrícula 2x2 de acciones de la ficha de producto (*Ajustar stock*, *Imprimir etiqueta*, *Trasladar*, *Ver movimientos*) debe responder de inmediato con modales limpios y comprensibles.
- **Objetivo:** Construir los 4 flujos modales de operación de almacén en Flutter.
- **Subtareas:**
  - **4.2.1 (2.0h) — Modal de Ajuste de Stock Físico (+ Entrada / — Salida):**
    - *Contexto:* Modificar stock indicando cantidad y motivo (Conteo físico, Merma, Devolución de cliente).
    - *Objetivo:* Diálogo modal con teclado numérico rápido y selector de tipo de ajuste.
  - **4.2.2 (2.0h) — Modal de Traslado entre Almacenes (Bodega ➔ Mostrador):**
    - *Contexto:* Mover cantidades entre diferentes almacenes registrados del mismo comercio.
    - *Objetivo:* Interfaz con validación visual de saldo disponible en el almacén de origen y selección de destino.
  - **4.2.3 (2.0h) — Modal de Vista Previa e Impresión de Etiquetas:**
    - *Contexto:* Generar etiquetas con nombre, código de barras y precio en $ MXN para pegar en anaqueles.
    - *Objetivo:* Renderizado de etiqueta lista para impresión térmica o guardado en PDF.

---

### 🗓️ DÍA 5: Importador Flexible Excel y Escaneo Continuo de Góndola

#### Tarea 5.1: Backend de Importación Flexible y Catálogo Semilla EAN-13 Base
- **Responsable:** Alan
- **Tiempo Total Estimado:** 6 Horas
- **Dependencias:** Tarea 3.1
- **Historia de Usuario / Caso de Uso:** `HU-09 / CU-09: Carga Masiva sin Plantillas Rígidas y Catálogo Semilla EAN`  
  *"Como comerciante con una lista en Excel de mi proveedor, quiero subir mi archivo directamente sin tener que adaptarlo a una plantilla estricta, y que los códigos de barras de marcas mexicanas se reconozcan al instante."*
- **Contexto y Justificación:** Los usuarios rechazan las importaciones cuando fallan por nombres de columnas ("Plantilla inválida"). El sistema debe permitir subir cualquier Excel con mapeo dinámico y contar con un catálogo semilla precargado de los Top 1,000 abarrotes de México (RF-01, RF-29 Tier 1).
- **Objetivo:** Desarrollar el servicio de parseo de hojas de cálculo con emparejamiento dinámico y el motor de consulta del catálogo semilla EAN-13.
- **Subtareas:**
  - **5.1.1 (2.5h) — Parser Dinámico de Archivos Excel/CSV con Mapeo:**
    - *Contexto:* Recibir un archivo `.xlsx` o `.csv` junto con un diccionario de mapeo JSON (`{"col_nombre": "A", "col_precio": "C", "col_stock": "D"}`).
    - *Objetivo:* Servicio en FastAPI con `openpyxl` que procesa e inserta miles de artículos en bloques transaccionales.
  - **5.1.2 (2.0h) — Base de Datos del Catálogo Semilla EAN-13 México (Tier 1):**
    - *Contexto:* Catálogo precargado de productos líderes (Bimbo, Coca-Cola, Sabritas, Lala, Maseca, etc.).
    - *Objetivo:* Carga y optimización de tabla estática `seed_products_catalog` con códigos GS1 oficiales de México.
  - **5.1.3 (1.5h) — Endpoint `/inventory/lookup-ean/{barcode}`:**
    - *Contexto:* Consulta ultra-rápida de código de barras para autocompletar en el escáner.
    - *Objetivo:* Endpoint optimizado que responde en < 5ms con nombre y categoría oficial del producto.

---

#### Tarea 5.2: UI de Mapeo Visual de Excel y Modo Góndola en Ráfaga
- **Responsable:** Eduardo
- **Tiempo Total Estimado:** 6 Horas
- **Dependencias:** Tarea 3.2, 5.1
- **Historia de Usuario / Caso de Uso:** `HU-10 / CU-10: Escaneo Continuo en Anaqueles y Mapeador Visual`  
  *"Como dueño de tienda, quiero caminar por los pasillos con mi celular escaneando código tras código para cargar mi inventario en minutos, o subir mi Excel con una interfaz que me pregunte qué columna es cada dato."*
- **Contexto y Justificación:** El setup físico de un negocio de abarrotes se logra caminando frente a los estantes. El "Modo Góndola" permite capturar productos continuamente sin tocar la pantalla entre lecturas (RF-30).
- **Objetivo:** Construir el asistente visual de mapeo de columnas de Excel y el modo de escaneo en ráfaga para anaqueles.
- **Subtareas:**
  - **5.2.1 (3.0h) — Interfaz de Mapeo Visual Interactivo de Columnas:**
    - *Contexto:* Pantalla donde el usuario arrastra o selecciona qué columna de su Excel corresponde al Nombre, Precio y Cantidad.
    - *Objetivo:* Wizard interactivo con tabla de previsualización de las primeras 5 filas antes de confirmar la importación.
  - **5.2.2 (3.0h) — Modo "Escaneo Continuo de Góndola" (Batch Mode):**
    - *Contexto:* Cámara encendida en modo ráfaga: detecta código EAN ➔ Si está en el catálogo semilla autocompleta el nombre ➔ Muestra teclado numérico grande para ingresar precio/stock ➔ Al dar "Enter" queda listo para el siguiente código sin salir de la cámara.
    - *Objetivo:* Pantalla de escaneo continuo con feedback auditivo ("beep") que permite digitalizar 100 artículos en 15 minutos.

---

### 🗓️ DÍA 6: POS Checkout, Máquina de Estados y Lazy Loading en Venta

#### Tarea 6.1: Backend de Checkout POS y Lazy Loading de Productos
- **Responsable:** Alan
- **Tiempo Total Estimado:** 6 Horas
- **Dependencias:** Tarea 3.1, 4.1
- **Historia de Usuario / Caso de Uso:** `HU-11 / CU-11: Cobro Transaccional Atómico y Creación al Vuelo en Venta`  
  *"Como cajero, quiero procesar una venta en mostrador de forma instantánea descontando el stock, y si un cliente me pide un producto que no está registrado, poder cobrarlo al momento pidiendo solo nombre y precio sin perder la venta."*
- **Contexto y Justificación:** El Punto de Venta es el corazón transaccional del negocio. No se puede detener una fila de clientes por falta de catálogo previo. El sistema debe permitir el "Lazy Loading / Inventario Orgánico" creando el producto silenciosamente en background (RF-09, RF-12).
- **Objetivo:** Desarrollar el endpoint principal de checkout transaccional con congelamiento de costos históricos y alta Just-in-Time.
- **Subtareas:**
  - **6.1.1 (2.0h) — Endpoint `POST /api/v1/sales/checkout` Atómico:**
    - *Contexto:* Transacción ACID que valida stock, crea la orden, congela `unit_cost_mxn` y descuenta inventario.
    - *Objetivo:* Controlador de checkout en FastAPI con manejo estricto de máquina de estados (`DRAFT` ➔ `PAID` ➔ `COMPLETED`).
  - **6.1.2 (2.0h) — Motor de Creación Orgánica "Sobre la Marcha" (Lazy Loading):**
    - *Contexto:* Si el payload de venta incluye un producto con `is_on_the_fly: true`, el backend lo crea en `products` antes de finalizar la venta.
    - *Objetivo:* Servicio que inserta silenciosamente el artículo en el inventario del tenant para que quede disponible en futuras consultas.
  - **6.1.3 (2.0h) — Pruebas de Concurrencia y Prevención de Bloqueos:**
    - *Contexto:* Evitar condiciones de carrera si dos cajas intentan vender el último artículo disponible al mismo milisegundo.
    - *Objetivo:* Tests de estrés con `pytest-asyncio` validando bloqueos optimistas `SELECT FOR UPDATE` en PostgreSQL.

---

#### Tarea 6.2: UI de Punto de Venta (POS), Carrito y Búsqueda Fuzzy
- **Responsable:** Eduardo
- **Tiempo Total Estimado:** 6 Horas
- **Dependencias:** Tarea 3.2
- **Historia de Usuario / Caso de Uso:** `HU-11 / CU-12: Terminal de Punto de Venta Móvil Ágil`  
  *"Como cajero, quiero una pantalla de venta intuitiva con escáner siempre activo, buscador de productos rápido, visualización clara del carrito y botón para agregar productos al vuelo."*
- **Contexto y Justificación:** El cajero opera bajo presión de tiempo con filas de clientes. La interfaz debe ser minimalista, con botones grandes, respuesta táctil instantánea y acceso inmediato al escáner de cámara (SR-04).
- **Objetivo:** Construir la pantalla principal de Punto de Venta (POS) en Flutter con carrito en vivo y buscador fuzzy.
- **Subtareas:**
  - **6.2.1 (2.0h) — Pantalla de Checkout POS (`CheckoutScreen`):**
    - *Contexto:* Buscador píldora superior con cámara integrada, lista de artículos escaneados con controles de incremento (+ / -) y subtotal en vivo en $ MXN.
    - *Objetivo:* Construir `CheckoutScreen` en `features/sales_pos/presentation/` modelada según el boceto aprobado.
  - **6.2.2 (2.0h) — Botón Flotante y Modal "+ Agregar Producto al Vuelo":**
    - *Contexto:* Botón destacado punteado que abre un diálogo rápido (Nombre y Precio MXN) para agregar un producto no registrado al carrito sin cancelar la venta.
    - *Objetivo:* Modal no bloqueante con foco automático en el teclado numérico.
  - **6.2.3 (2.0h) — Panel Inferior Fijo de Totales y Botón "Cobrar":**
    - *Contexto:* Barra fija inferior con desglose de ítems, Subtotal en `$ MXN` e indicador visual llamativo del botón "Cobrar $ XX.XX".
    - *Objetivo:* Componente responsivo que se adapta a pantallas de celular o tablet con navegación fluida al modal de pago.

---

### 🗓️ DÍA 7: Pagos Mixtos y Calculadora Rápida de Cambio MXN

#### Tarea 7.1: Backend de Pagos Mixtos y Registro Contable
- **Responsable:** Alan
- **Tiempo Total Estimado:** 6 Horas
- **Dependencias:** Tarea 6.1
- **Historia de Usuario / Caso de Uso:** `HU-13 / CU-13: Registro de Pagos Mixtos y Canales de Cobro en México`  
  *"Como cajero, quiero registrar cuando un cliente me paga una parte en efectivo y otra por transferencia SPEI o tarjeta Clip, para que la cuenta cuadre con exactitud."*
- **Contexto y Justificación:** En México es frecuente que una compra de $350 MXN se pague con $200 en efectivo y $150 vía transferencia SPEI o tarjeta de débito. El sistema debe soportar cobros fraccionados como registro contable estricto (RF-13, RF-14).
- **Objetivo:** Implementar la tabla de pagos `sale_payments` y la validación matemática de cobros mixtos en FastAPI.
- **Subtareas:**
  - **7.1.1 (2.0h) — Modelado de `sale_payments` y Tipos de Pago en México:**
    - *Contexto:* Soporte para enums `CASH_MXN`, `SPEI`, `CODI`, `CARD_TPV` y campos opcionales de referencia bancaria.
    - *Objetivo:* Definir modelo y relaciones en SQLAlchemy con validación de montos positivos en `modules/sales_pos/domain/`.
  - **7.1.2 (2.0h) — Servicio de Validación de Suma Exacta y Cambio Entregado:**
    - *Contexto:* El backend verifica que `suma(pagos) >= total_venta` y calcula el cambio exacto a devolver al cliente.
    - *Objetivo:* Lógica de liquidación que previene descuadres matemáticos en el registro de la venta.
  - **7.1.3 (2.0h) — Desacoplamiento de Validaciones Bancarias:**
    - *Contexto:* Cumplir la Constitución (Art. III): Nexus actúa como registro contable; no bloquea la venta esperando confirmación bancaria automática.
    - *Objetivo:* Validación manual del cajero registrada con timestamp y ID del empleado responsable.

---

#### Tarea 7.2: UI de Modal de Cobro y Calculadora de Vuelto MXN
- **Responsable:** Eduardo
- **Tiempo Total Estimado:** 6 Horas
- **Dependencias:** Tarea 6.2
- **Historia de Usuario / Caso de Uso:** `HU-13 / CU-14: Calculadora Rápida de Cambio con Billetes de México`  
  *"Como cajero, quiero que al cobrar en efectivo aparezcan botones de billetes mexicanos ($50, $100, $200, $500 MXN) para tocar el billete que me dio el cliente y saber el cambio de inmediato sin hacer cuentas mentales."*
- **Contexto y Justificación:** Los errores de cambio en efectivo generan pérdidas diarias en una tiendita. Los atajos táctiles de billetes nacionales aceleran el cobro a menos de 3 segundos (SR-04).
- **Objetivo:** Construir el modal de cobro interactivo con pestañas de métodos de pago y calculadora de billetes mexicanos en Flutter.
- **Subtareas:**
  - **7.2.1 (2.0h) — Modal de Cobro Multimétodo (Pestañas Interactivas):**
    - *Contexto:* Selector con pestañas: *Efectivo*, *SPEI / Transferencia*, *Tarjeta / TPV Clip*, *Pago Mixto*.
    - *Objetivo:* Widget modular en `features/sales_pos/presentation/` que conmuta vistas según el canal seleccionado.
  - **7.2.2 (2.0h) — Calculadora de Vuelto con Botones de Billetes Banxico:**
    - *Contexto:* Botones táctiles de **$50, $100, $200, $500 y $1,000 MXN** y botón "Monto Exacto".
    - *Objetivo:* Al presionar un billete, muestra en tipografía gigante el cambio exacto a entregar (ej. *"Cambio: $65.00 MXN"*).
  - **7.2.3 (2.0h) — Formulario de Captura de Referencia para SPEI / TPV:**
    - *Contexto:* Campo opcional para anotar la clave de rastreo bancaria o el número de autorización de la terminal Clip/Mercado Pago.
    - *Objetivo:* Campo de texto rápido que se guarda en el registro de la venta para auditoría posterior.

---

### 🗓️ DÍA 8: Notas de Venta (Ticket 58/80mm) y Comisiones de Empleados

#### Tarea 8.1: Backend de Comprobantes Internos y Comisiones Dinámicas
- **Responsable:** Alan
- **Tiempo Total Estimado:** 6 Horas
- **Dependencias:** Tarea 7.1
- **Historia de Usuario / Caso de Uso:** `HU-14 / CU-15: Emisión de Notas de Venta y Liquidación de Comisiones`  
  *"Como dueño de tienda, quiero emitir notas de venta con folio consecutivo para control administrativo y calcular automáticamente las comisiones que le corresponden a cada uno de mis vendedores."*
- **Contexto y Justificación:** Aunque el timbrado CFDI 4.0 está diferido a fases posteriores, el comercio minorista requiere comprobantes claros tipo "Nota de Venta" y un sistema que incentive a los empleados calculando sus comisiones por ventas (RF-08, RF-10).
- **Objetivo:** Desarrollar el generador de notas de venta estructuradas y el motor de comisiones dinámicas por usuario.
- **Subtareas:**
  - **8.1.1 (2.0h) — Generador de Comprobantes de Nota de Venta:**
    - *Contexto:* Estructura de comprobante con folio correlativo, fecha/hora, datos del comercio, detalle de ítems y desglose informativo de IVA (0% o 16%).
    - *Objetivo:* Endpoint `/sales/{id}/receipt` que retorna el modelo JSON y binario PDF listo para emitir.
  - **8.1.2 (2.0h) — Motor de Comisiones Dinámicas de Ventas:**
    - *Contexto:* Regla de comisión configurable por empleado (% sobre el total de ventas o % sobre el margen de ganancia neta).
    - *Objetivo:* Servicio que calcula e incrementa el saldo de comisión del vendedor al completarse cada venta.
  - **8.1.3 (2.0h) — Endpoints de Reporte y Liquidación de Comisiones:**
    - *Contexto:* Consultar cuánto ha ganado en comisiones un empleado en un turno, semana o mes.
    - *Objetivo:* Endpoint `/analytics/commissions` con filtros por vendedor y rango de fechas.

---

#### Tarea 8.2: UI de Ticket Imprimible, Compartir WhatsApp y Tablero de Comisiones
- **Responsable:** Eduardo
- **Tiempo Total Estimado:** 6 Horas
- **Dependencias:** Tarea 7.2
- **Historia de Usuario / Caso de Uso:** `HU-14 / CU-16: Formato de Ticket Térmico y Tablero de Rendimiento`  
  *"Como cajero, quiero ver el ticket de venta en formato térmico para imprimirlo o enviárselo al cliente por WhatsApp, y poder ver en mi perfil cuánto llevo acumulado de comisiones hoy."*
- **Contexto y Justificación:** La entrega del comprobante finaliza el ciclo de venta. El ticket debe adaptarse a impresoras térmicas estándar (58mm/80mm) y permitir el envío digital instantáneo (SR-05).
- **Objetivo:** Construir la vista de ticket de compra, el generador de comprobante digital y el tablero de comisiones en Flutter.
- **Subtareas:**
  - **8.2.1 (2.5h) — Formato Visual de Ticket Térmico (58mm / 80mm):**
    - *Contexto:* Diseño del comprobante en blanco y negro con tipografía monoespaciada para impresión térmica o pantalla.
    - *Objetivo:* Widget de ticket con logotipo, lista de productos, total en $ MXN, desglose de pago y código QR de validación.
  - **8.2.2 (1.5h) — Botón para Compartir Comprobante a WhatsApp:**
    - *Contexto:* Enviar el recibo en PDF o texto estructurado al WhatsApp del cliente con 1 solo toque.
    - *Objetivo:* Integración con `url_launcher` para abrir la app de WhatsApp con el comprobante adjunto.
  - **8.2.3 (2.0h) — Tablero de Rendimiento de Empleados (`EmployeePerformanceTab`):**
    - *Contexto:* Tarjeta visual en el perfil del usuario con métricas de ventas del día, metas alcanzadas y comisiones generadas en $ MXN.
    - *Objetivo:* Vista de gamificación laboral que motiva al personal de mostrador.

---

### 🗓️ DÍA 9: Apertura/Cierre de Caja y Desglose de Denominaciones Banxico

#### Tarea 9.1: Backend de Sesiones de Caja y Denominaciones Banxico
- **Responsable:** Alan
- **Tiempo Total Estimado:** 6 Horas
- **Dependencias:** Tarea 7.1
- **Historia de Usuario / Caso de Uso:** `HU-15 / CU-17: Apertura y Cierre de Turno con Cono Monetario Oficial`  
  *"Como cajero o supervisor, quiero abrir mi turno registrando mi fondo de caja en pesos y cerrarlo desglosando físicamente cada billete y moneda de México para que el arqueo sea exacto y transparente."*
- **Contexto y Justificación:** La caja registradora es el punto crítico de control de efectivo. Registrar el desglose exacto de cada denominación oficial del Banco de México (Banxico) elimina los errores de conteo y permite auditorías impecables (RF-18).
- **Objetivo:** Modelar e implementar la API de sesiones de caja y la tabla de conteo físico de denominaciones de Banxico.
- **Subtareas:**
  - **9.1.1 (2.0h) — Modelado de `cash_sessions` y `cash_session_denominations`:**
    - *Contexto:* Tablas para registrar apertura, fondo inicial, total teórico, conteo físico y columnas para cada denominación oficial (`bills_1000`, `bills_500`, `coins_20`, etc.).
    - *Objetivo:* Definir modelos SQLAlchemy con restricciones de integridad en `modules/cash_treasury/domain/`.
  - **9.1.2 (2.0h) — Endpoint `POST /api/v1/cash/open-session`:**
    - *Contexto:* Apertura formal del turno indicando cajero responsable, caja física y monto del fondo inicial en MXN.
    - *Objetivo:* Controlador que inicializa la sesión y bloquea aperturas duplicadas en la misma caja.
  - **9.1.3 (2.0h) — Endpoint `POST /api/v1/cash/close-session` (Conteo Banxico):**
    - *Contexto:* Recepción del conteo físico de billetes ($20-$1000) y monedas ($0.50-$20) y cálculo del total físico entregado.
    - *Objetivo:* Endpoint que almacena las denominaciones y liquida el estado de la sesión de caja.

---

#### Tarea 9.2: UI del Asistente Visual de Cierre de Caja (Wizard Banxico)
- **Responsable:** Eduardo
- **Tiempo Total Estimado:** 6 Horas
- **Dependencias:** Tarea 7.2
- **Historia de Usuario / Caso de Uso:** `HU-15 / CU-18: Asistente Visual de Arqueo de Caja (Wizard)`  
  *"Como cajero al final del turno, quiero un asistente visual guiado con fotos de los billetes y monedas mexicanas donde solo tenga que teclear cuántas piezas tengo de cada uno y el sistema sume todo automáticamente."*
- **Contexto y Justificación:** El arqueo de caja al final del día es tedioso y propenso a equivocaciones mentales. Un wizard interactivo con ilustraciones oficiales del cono monetario de Banxico hace que el cierre de turno tome menos de 3 minutos (RF-19, SR-07).
- **Objetivo:** Construir el asistente visual paso a paso para el conteo de billetes y monedas mexicanas en Flutter.
- **Subtareas:**
  - **9.2.1 (2.5h) — Paso 1 del Wizard: Conteo de Billetes Oficiales de Banxico:**
    - *Contexto:* Tarjetas interactivas con ilustraciones de billetes ($20, $50, $100, $200, $500, $1,000 MXN) y campos de conteo rápido.
    - *Objetivo:* Widget con sumatoria reactiva inmediata en $ MXN al ingresar la cantidad de piezas.
  - **9.2.2 (2.0h) — Paso 2 del Wizard: Conteo de Monedas Metálicas:**
    - *Contexto:* Tarjetas para monedas ($0.50, $1, $2, $5, $10, $20 MXN) con calculadora de fracciones de centavos.
    - *Objetivo:* Componente de conteo rápido que suma el total de moneda fraccionaria al total de billetes.
  - **9.2.3 (1.5h) — Paso 3 del Wizard: Resumen de Pagos Digitales:**
    - *Contexto:* Vista informativa de los cobros digitales acumulados en el turno (SPEI total, TPV Clip/tarjetas, CoDi) para cotejo del cajero.
    - *Objetivo:* Pantalla previa de confirmación antes de enviar el cierre definitivo al servidor.

---

### 🗓️ DÍA 10: Auditoría de Descuadres y Reporte de Cierre de Turno

#### Tarea 10.1: Backend de Conciliación de Caja y Detección de Descuadres
- **Responsable:** Alan
- **Tiempo Total Estimado:** 6 Horas
- **Dependencias:** Tarea 9.1
- **Historia de Usuario / Caso de Uso:** `HU-16 / CU-19: Auditoría de Caja, Faltantes/Sobrantes y Movimientos Menores`  
  *"Como dueño de negocio, quiero ver el balance exacto de cada turno para saber si el dinero físico coincide con lo vendido, registrar salidas de caja menor (ej. pagar el hielo o refrescos) y detectar si hubo faltantes o sobrantes."*
- **Contexto y Justificación:** El control del efectivo exige comparar el saldo teórico esperado versus el dinero real contado. Además, durante el día se realizan retiros para gastos menores que deben quedar formalmente justificados (RF-18).
- **Objetivo:** Implementar el algoritmo de conciliación matemática de turnos y la gestión de movimientos extraordinarios de efectivo.
- **Subtareas:**
  - **10.1.1 (2.0h) — Algoritmo de Conciliación Teórico vs. Físico:**
    - *Contexto:* Fórmula `Diferencia = Saldo Físico - (Fondo Inicial + Ventas Efectivo - Retiros + Entradas)`.
    - *Objetivo:* Servicio que clasifica el cierre en `CUADRE_EXACTO`, `FALTANTE` o `SOBRANTE` con auditoría de centavos.
  - **10.1.2 (2.0h) — Registro de Movimientos de Caja Menor (`cash_movements`):**
    - *Contexto:* Endpoints para registrar entradas de cambio o retiros de efectivo con descripción y autorización.
    - *Objetivo:* CRUD de movimientos de caja menor que impactan en tiempo real el saldo teórico esperado.
  - **10.1.3 (2.0h) — Generador de Reporte de Corte Z / X:**
    - *Contexto:* Reporte consolidado con total de ventas por método de pago, desglose de billetes, movimientos y balance final.
    - *Objetivo:* Endpoint `/cash/sessions/{id}/report` con métricas financieras del turno.

---

#### Tarea 10.2: UI de Reporte de Cuadre de Caja y Exportación
- **Responsable:** Eduardo
- **Tiempo Total Estimado:** 6 Horas
- **Dependencias:** Tarea 9.2, 10.1
- **Historia de Usuario / Caso de Uso:** `HU-16 / CU-20: Visualización de Corte de Caja e Impresión de Corte Z`  
  *"Como supervisor, quiero ver el resumen del cierre de turno en pantalla con indicadores claros en verde/rojo si cuadró o hubo descuadre, e imprimir el ticket de corte Z para graparlo al sobre de dinero."*
- **Contexto y Justificación:** La transparencia en los cortes de turno previene conflictos laborales entre cajeros y dueños. El reporte debe mostrar claramente cada peso contado y permitir la impresión física inmediata.
- **Objetivo:** Construir la pantalla de reporte de arqueo, el diálogo de caja chica y la exportación de corte Z en Flutter.
- **Subtareas:**
  - **10.2.1 (2.0h) — Pantalla de Resultado de Arqueo y Discrepancias:**
    - *Contexto:* Resumen visual con semáforo de estado (Verde: Cuadre perfecto, Rojo: Faltante, Azul: Sobrante) y desglose de dinero.
    - *Objetivo:* `CashSessionSummaryScreen` en `features/cash_treasury/presentation/`.
  - **10.2.2 (2.0h) — Modal de Registro de Movimientos de Caja Menor:**
    - *Contexto:* Diálogo para ingresar retiros para proveedores o recargas de cambio durante el día.
    - *Objetivo:* Formulario ágil con selector de tipo de movimiento y captura de motivo.
  - **10.2.3 (2.0h) — Generación e Impresión del Ticket de Corte Z:**
    - *Contexto:* Ticket en formato térmico para archivo físico del negocio con desglose de denominaciones Banxico.
    - *Objetivo:* Integración con impresora térmica y exportación del corte en PDF.

---

### 🗓️ DÍA 11: Módulo de Compras, Proveedores y Cuentas por Pagar

#### Tarea 11.1: Backend de Compras y Cuentas por Pagar a Proveedores
- **Responsable:** Alan
- **Tiempo Total Estimado:** 6 Horas
- **Dependencias:** Tarea 3.1
- **Historia de Usuario / Caso de Uso:** `HU-17 / CU-21: Registro de Compras, Abastecimiento y Cuentas por Pagar`  
  *"Como tendero, quiero registrar los pedidos de mercancía que le compro a mis distribuidores (Bimbo, Coca-Cola, Sabritas), que el stock aumente automáticamente al recibir la entrega y llevar la cuenta de lo que les debo a crédito."*
- **Contexto y Justificación:** El reabastecimiento alimenta el inventario. Manejar compras y cuentas por pagar a proveedores en pesos mexicanos permite saber los costos reales y evitar desabasto en la tienda (RF-15, RF-16).
- **Objetivo:** Desarrollar el módulo de compras, recepción de mercancía y cuentas por pagar en FastAPI.
- **Subtareas:**
  - **11.1.1 (2.0h) — Modelado de `suppliers`, `purchase_orders` y `accounts_payable`:**
    - *Contexto:* Tablas para proveedores nacionales, órdenes de compra, ítems recibidos con costo de compra en MXN y saldos adeudados.
    - *Objetivo:* Esquemas y modelos relacionales en `modules/purchasing_suppliers/domain/`.
  - **11.1.2 (2.0h) — Lógica de Recepción Automática al Inventario:**
    - *Contexto:* Al cambiar el estado de la compra a `RECEIVED`, el stock de cada producto se incrementa en el almacén seleccionado y se actualiza el costo promedio en Kardex.
    - *Objetivo:* Transacción ACID que sincroniza compras con inventario físico.
  - **11.1.3 (2.0h) — Módulo de Cuentas por Pagar a Crédito en MXN:**
    - *Contexto:* Seguimiento de facturas adeudadas a proveedores, plazos de pago y registro de abonos parciales.
    - *Objetivo:* Endpoints para consultar saldos pendientes y registrar pagos a proveedores.

---

#### Tarea 11.2: UI de Compras, Directorio de Proveedores y Cuentas por Pagar
- **Responsable:** Eduardo
- **Tiempo Total Estimado:** 6 Horas
- **Dependencias:** Tarea 3.2
- **Historia de Usuario / Caso de Uso:** `HU-17 / CU-22: Gestión Visual de Proveedores y Facturas por Pagar`  
  *"Como dueño, quiero una lista de mis proveedores con sus teléfonos para llamarlos rápido, ver mis facturas pendientes de pago con un semáforo de vencimientos y registrar nuevas compras fácilmente."*
- **Contexto y Justificación:** El tendero interactúa semanalmente con múltiples repartidores de empresas de consumo masivo. La interfaz debe facilitar el registro de remisiones y el seguimiento de deudas comerciales.
- **Objetivo:** Construir la interfaz de compras, directorio de proveedores y tablero de cuentas por pagar en Flutter.
- **Subtareas:**
  - **11.2.1 (2.0h) — Pantalla de Registro de Compras y Entradas:**
    - *Contexto:* Formulario para seleccionar proveedor, fecha, almacén de destino y agregar productos recibidos con costo y cantidad.
    - *Objetivo:* `PurchaseCreateScreen` en `features/purchases/presentation/`.
  - **11.2.2 (2.0h) — Directorio de Proveedores con Acceso Directo:**
    - *Contexto:* Listado de distribuidores con nombre del vendedor, teléfono con botón de llamada/WhatsApp y catálogo de productos que surte.
    - *Objetivo:* Vista de proveedores en Flutter con búsqueda rápida.
  - **11.2.3 (2.0h) — Tablero de Cuentas por Pagar con Semáforo:**
    - *Contexto:* Vista con tarjetas de facturas pendientes ordenadas por fecha de vencimiento (Verde: A tiempo, Amarillo: Vence pronto, Rojo: Vencida).
    - *Objetivo:* Modal interactivo para registrar abonos de dinero a las facturas adeudadas.

---

### 🗓️ DÍA 12: OCR On-Device de Facturas y Captura Asistida por Voz

#### Tarea 12.1: Backend Parser de Facturas y Normalización Heurística
- **Responsable:** Alan
- **Tiempo Total Estimado:** 6 Horas
- **Dependencias:** Tarea 11.1
- **Historia de Usuario / Caso de Uso:** `HU-18 / CU-23: Procesamiento Estructurado de Facturas de Proveedores`  
  *"Como comerciante, quiero que el texto extraído de la foto de la factura de mi proveedor se convierta automáticamente en una lista de productos con cantidad y costo listos para ingresar a mi inventario."*
- **Contexto y Justificación:** Las facturas y notas de entrega físicas de repartidores (Bimbo, Coca-Cola, Lala) contienen tablas con patrones de texto repetitivos. Un parser heurístico robusto en el backend estructura estos datos sin requerir LLMs o APIs en la nube de alto costo (RF-28).
- **Objetivo:** Desarrollar el algoritmo de parseo y normalización de líneas de factura física en FastAPI.
- **Subtareas:**
  - **12.1.1 (2.5h) — Algoritmo de Parseo Heurístico de Líneas de Factura:**
    - *Contexto:* Expresiones regulares y reglas heurísticas para extraer `[CANTIDAD]`, `[DESCRIPCIÓN/NOMBRE]`, `[PRECIO UNITARIO]` e `[IMPORTE TOTAL]`.
    - *Objetivo:* Servicio en Python que procesa bloques de texto OCR y retorna una estructura JSON normalizada.
  - **12.1.2 (2.0h) — Endpoint de Previsualización y Corrección Masiva:**
    - *Contexto:* Endpoint `/purchases/parse-receipt` que devuelve los productos detectados para que el usuario los revise antes de guardar.
    - *Objetivo:* API que vincula automáticamente descripciones con productos existentes mediante búsqueda por trigramas (`pg_trgm`).
  - **12.1.3 (1.5h) — Pruebas de Calibración con Facturas de Distribuidores Mexicanos:**
    - *Contexto:* Probar el parser con fotos de facturas reales de Bimbo, PepsiCo, Sigma Alimentos y Lala.
    - *Objetivo:* Asegurar una tasa de acierto superior al 90% en la detección de cantidades y costos.

---

#### Tarea 12.2: Frontend OCR On-Device (ML Kit) y Dictado de Voz Nativo
- **Responsable:** Eduardo
- **Tiempo Total Estimado:** 6 Horas
- **Dependencias:** Tarea 11.2, 12.1
- **Historia de Usuario / Caso de Uso:** `HU-18 / CU-24: Escaneo de Facturas con la Cámara del Celular y Dictado por Voz`  
  *"Como comerciante, quiero tomarle una foto a la factura de mi repartidor con la cámara de mi celular para que la app extraiga los datos sin conexión a internet y a costo cero, o dictarle por voz mis productos para no tener que escribir."*
- **Contexto y Justificación:** Cumpliendo con el principio Bootstrap (Art. IV), el OCR debe ejecutarse 100% en el procesador del smartphone mediante `google_mlkit_text_recognition` sin pagar por peticiones cloud. Asimismo, el dictado por voz nativo acelera la captura manual (RF-28, SR-09).
- **Objetivo:** Integrar Google ML Kit Text Recognition y el motor nativo de reconocimiento de voz en la aplicación Flutter.
- **Subtareas:**
  - **12.2.1 (2.5h) — Integración de Google ML Kit Text Recognition (On-Device):**
    - *Contexto:* Capturar foto con la cámara y procesar la extracción de texto localmente en el dispositivo Android sin consumir datos móviles.
    - *Objetivo:* Módulo en `lib/core/utils/ocr_helper.dart` que extrae bloques de texto y bounding boxes en menos de 1 segundo.
  - **12.2.2 (2.0h) — Pantalla de Revisión Interactiva de Factura:**
    - *Contexto:* Tabla visual donde el usuario ve la lista de productos extraídos por el OCR y puede corregir cantidades o precios antes de aprobar el ingreso.
    - *Objetivo:* `OcrReviewScreen` en `features/purchases/presentation/` con validación de subtotales.
  - **12.2.3 (1.5h) — Botón de Micrófono para Dictado de Voz Nativo:**
    - *Contexto:* Botón de voz en el formulario de productos que escucha *"Maruchan Pollo, precio 16, 36 piezas"* usando la API nativa de Android/Web.
    - *Objetivo:* Parser local en Dart que rellena los 3 campos vitales automáticamente a partir del audio dictado.

---

### 🗓️ DÍA 13: Catálogo Digital WhatsApp y Suscripciones SaaS

#### Tarea 13.1: Backend de Catálogo Público y Renderizado SSR
- **Responsable:** Alan
- **Tiempo Total Estimado:** 6 Horas
- **Dependencias:** Tarea 3.1
- **Historia de Usuario / Caso de Uso:** `HU-20 / CU-25: Catálogo Web Público y Pedidos Estructurados por WhatsApp`  
  *"Como cliente de la tiendita, quiero entrar a un enlace web desde mi celular, ver los productos y precios actualizados del negocio, armar mi carrito y mandar el pedido directamente al WhatsApp de la tienda."*
- **Contexto y Justificación:** La digitalización del pequeño comercio en México ocurre a través de WhatsApp. Un catálogo web público y responsivo sincronizado en tiempo real permite al tendero recibir pedidos estructurados sin pagar comisiones a apps de delivery (RF-23, RF-24, RF-25).
- **Objetivo:** Desarrollar los endpoints públicos de catálogo y el generador de mensajes estructurados para WhatsApp.
- **Subtareas:**
  - **13.1.1 (2.0h) — Endpoints Públicos de Catálogo `/catalog/{tenant_slug}`:**
    - *Contexto:* Rutas de solo lectura altamente optimizadas para miles de visitas simultáneas con caché en memoria.
    - *Objetivo:* Endpoint que lista productos activos, fotos y precios en $ MXN del comercio especificado.
  - **13.1.2 (2.0h) — Metadatos OpenGraph y Previews para WhatsApp:**
    - *Contexto:* Cuando el comerciante comparte su enlace en WhatsApp, debe verse una tarjeta enriquecida con foto, nombre de la tienda y descripción.
    - *Objetivo:* Inyección de etiquetas OpenGraph SSR (`og:title`, `og:image`, `og:description`) en la cabecera HTML.
  - **13.1.3 (2.0h) — Servicio de Formateo de Pedido para WhatsApp:**
    - *Contexto:* Transformar el carrito de compras en un mensaje de texto formateado con negritas y emojis listo para enviar.
    - *Objetivo:* Generador de texto estructurado con lista de ítems, subtotal en $ MXN, nombre del cliente y dirección de entrega.

---

#### Tarea 13.2: UI del Catálogo Web Móvil y Botón de Compartir
- **Responsable:** Eduardo
- **Tiempo Total Estimado:** 6 Horas
- **Dependencias:** Tarea 1.2, 13.1
- **Historia de Usuario / Caso de Uso:** `HU-20 / CU-26: Vitrina Digital Responsiva y Envío de Pedido a WhatsApp`  
  *"Como comerciante, quiero un botón para compartir el enlace de mi catálogo en mis estados de WhatsApp o Facebook, y que mis clientes tengan una experiencia de compra móvil limpia y rápida."*
- **Contexto y Justificación:** La página pública debe ser ultra liviana, cargar en menos de 1 segundo en smartphones con datos móviles y tener un botón prominente de "Pedir por WhatsApp" (RF-26, RF-27).
- **Objetivo:** Construir la vitrina pública web para clientes y las herramientas de difusión para el comerciante en Flutter.
- **Subtareas:**
  - **13.2.1 (2.5h) — Vitrina Web Responsiva para Clientes Finales:**
    - *Contexto:* Pantalla web pública con buscador de productos, tarjetas visuales con precio en $ MXN y botón "+ Agregar".
    - *Objetivo:* `PublicCatalogScreen` en `features/whatsapp_catalog/presentation/` optimizada para Flutter Web Mobile.
  - **13.2.2 (2.0h) — Carrito Flotante y Botón "Enviar Pedido por WhatsApp":**
    - *Contexto:* Barra flotante que muestra el total acumulado y modal para ingresar datos de entrega y lanzar WhatsApp con el mensaje armado.
    - *Objetivo:* Flujo de checkout web para clientes sin requerir registro ni contraseñas.
  - **13.2.3 (1.5h) — Panel de Difusión y Compartir Catálogo:**
    - *Contexto:* Botón en el panel del tendero para copiar enlace corto (`nexus.com/tienda/don-pepe`), descargar código QR o compartir directo en WhatsApp.
    - *Objetivo:* Widget con generación de código QR descargable e imprimible para mostrador.

---

### 🗓️ DÍA 14: Suscripciones SaaS (SPEI / OXXO Pay) y Panel de Fundadores

#### Tarea 14.1: Backend de Suscripciones SaaS, Webhooks SPEI y OXXO Pay
- **Responsable:** Alan
- **Tiempo Total Estimado:** 6 Horas
- **Dependencias:** Tarea 2.1
- **Historia de Usuario / Caso de Uso:** `HU-21 / CU-27: Cobro de Suscripciones SaaS y Conciliación Automática en México`  
  *"Como fundadores (Alan y Eduardo), queremos cobrar las mensualidades de los comercios mediante transferencias SPEI automatizadas con CLABE o pagos en efectivo en tiendas OXXO, y que las cuentas se activen automáticamente al confirmarse el pago."*
- **Contexto y Justificación:** La viabilidad del negocio SaaS en México depende de ofrecer métodos de pago familiares (SPEI y OXXO Pay) con conciliación automatizada por webhooks y control del ciclo de vida de la suscripción (Constitución Art. V y VI).
- **Objetivo:** Desarrollar el motor de suscripciones en MXN ($199, $399, $699), webhooks de pago y control de morosidad.
- **Subtareas:**
  - **14.1.1 (2.0h) — Modelado de `subscription_invoices` y Planes en MXN:**
    - *Contexto:* Tablas para planes Emprendedor ($199), Comercio ($399), Corporativo ($699), facturas de suscripción y tabla de idempotencia.
    - *Objetivo:* Esquemas y servicios en `modules/saas_billing/domain/` con control de duplicidad de webhooks.
  - **14.1.2 (2.0h) — Webhooks de Conciliación SPEI (STP) y OXXO Pay:**
    - *Contexto:* Endpoints receptores de webhooks que validan firmas criptográficas, acreditan el pago y renuevan el estado `ACTIVE` del tenant.
    - *Objetivo:* Controladores `/api/v1/saas/webhooks/spei` y `/api/v1/saas/webhooks/oxxo` con respuesta en < 200ms.
  - **14.1.3 (2.0h) — Cron Job de Ciclo de Vida y Notificaciones de Vencimiento:**
    - *Contexto:* Proceso diario que evalúa fechas de vencimiento y transiciona estados (`ACTIVE` ➔ `SOFT_LOCK` ➔ `HARD_LOCK`).
    - *Objetivo:* Worker asíncrono que actualiza el estado de las cuentas y genera avisos automáticos de cobro.

---

#### Tarea 14.2: UI del Panel de Administración SaaS y Gestión de Planes
- **Responsable:** Eduardo
- **Tiempo Total Estimado:** 6 Horas
- **Dependencias:** Tarea 1.2, 14.1
- **Historia de Usuario / Caso de Uso:** `HU-22 / CU-28: Panel Administrativo de Fundadores y Checkout de Suscripción`  
  *"Como comerciante, quiero una pantalla clara para pagar mi mensualidad viendo la cuenta CLABE para SPEI o el código de barras para OXXO; y como fundadores, queremos un panel exclusivo para ver nuestros ingresos mensuales (MRR) y comercios activos."*
- **Contexto y Justificación:** Los fundadores necesitan visibilidad financiera en tiempo real para gestionar el crecimiento del SaaS y los clientes necesitan una experiencia de pago sin trabas.
- **Objetivo:** Construir la pantalla de pago de suscripciones y el panel administrativo interno para fundadores en Flutter.
- **Subtareas:**
  - **14.2.1 (2.0h) — Pantalla de Pago de Suscripción para el Comerciante:**
    - *Contexto:* Vista de facturación con selección de plan, cuenta CLABE interbancaria dedicada con botón "Copiar" y código numérico/código de barras para pagar en OXXO.
    - *Objetivo:* `SubscriptionCheckoutScreen` en `features/saas_admin/presentation/`.
  - **14.2.2 (2.5h) — Panel de Control de Fundadores (Alan y Eduardo):**
    - *Contexto:* Dashboard exclusivo para fundadores con métricas de MRR en `$ MXN`, total de tenants activos, tasa de retención y bandeja de aprobación de pagos manuales.
    - *Objetivo:* `FounderAdminDashboardScreen` con filtros y acciones de reactivación rápida.
  - **14.2.3 (1.5h) — Pantallas de Bloqueo por Morosidad (Soft Lock / Hard Lock):**
    - *Contexto:* Banner informativo de morosidad en Soft Lock y pantalla de bloqueo completo en Hard Lock con enlace directo a pago.
    - *Objetivo:* Componentes de advertencia reactivos vinculados al estado de la cuenta.

---

### 🗓️ DÍA 15: Red Comunitaria con Consenso de 3 Comercios y Clonación

#### Tarea 15.1: Backend del Motor de Consenso Comunitario y Clonación
- **Responsable:** Alan
- **Tiempo Total Estimado:** 6 Horas
- **Dependencias:** Tarea 5.1
- **Historia de Usuario / Caso de Uso:** `HU-23 / CU-29: Red Comunitaria con Consenso de 3 Comercios y Clonación`  
  *"Como comerciante, quiero que si otros 3 comercios ya registraron un código de barras nuevo, el sistema me sugiera el nombre verificado automáticamente para no tener que escribirlo; y si abro una segunda tienda, poder clonar mi catálogo en 1 clic."*
- **Contexto y Justificación:** Para que la base de datos crezca sola sin que Alan y Eduardo tengan que moderar productos manualmente, se implementa el algoritmo de consenso automático: una sugerencia solo se hace pública cuando al menos 3 comercios independientes coinciden en el mismo código y nombre (RF-29 Tier 2, RF-31).
- **Objetivo:** Desarrollar el motor de agregación anónima con consenso de 3 tenants y el servicio de clonación de catálogos en FastAPI.
- **Subtareas:**
  - **15.1.1 (2.5h) — Motor de Consenso Automático de 3 Tenants:**
    - *Contexto:* Tablas `community_catalog_submissions` y `community_verified_catalog`.
    - *Objetivo:* Trigger/servicio asíncrono que evalúa similitud de trigramas (`pg_trgm` > 80%) y promueve automáticamente productos al alcanzar $\ge 3$ comercios independientes distintos.
  - **15.1.2 (2.0h) — Servicio de Clonación de Catálogo Maestro:**
    - *Contexto:* Duplicar la estructura de productos (nombres, SKUs, categorías, precios) de una tienda origen hacia una nueva tienda o sucursal con existencias en 0.
    - *Objetivo:* Endpoint `/inventory/clone-catalog` con validación de permisos de sucursal.
  - **15.1.3 (1.5h) — Endpoints de Analítica Avanzada y Rentabilidad Histórica:**
    - *Contexto:* Cálculo de utilidad bruta y neta utilizando los costos congelados históricos de `sale_items.unit_cost_mxn`.
    - *Objetivo:* Endpoints `/analytics/profitability` con gráficos de rentabilidad para el Plan Corporativo (RF-20).

---

#### Tarea 15.2: UI de Sugerencias Comunitarias, Clonación y Dashboard Analítico
- **Responsable:** Eduardo
- **Tiempo Total Estimado:** 6 Horas
- **Dependencias:** Tarea 6.2, 15.1
- **Historia de Usuario / Caso de Uso:** `HU-23 / CU-30: Experiencia de Autocompletado Colaborativo y Reportes de Ganancias`  
  *"Como cajero, quiero ver un distintivo cuando un producto sugerido proviene de la comunidad de Nexus para confiar en el nombre, y como dueño, ver gráficas claras de mis ganancias netas del mes."*
- **Contexto y Justificación:** La interfaz debe comunicar confianza al usuario mostrando el origen de las sugerencias y entregar analítica de negocio clara en pesos mexicanos (SR-02, RF-21).
- **Objetivo:** Construir los componentes visuales de sugerencias comunitarias, el diálogo de clonación y el dashboard analítico en Flutter.
- **Subtareas:**
  - **15.2.1 (2.0h) — Badge y Autocompletado de la Red Comunitaria en POS:**
    - *Contexto:* Chip visual con icono de comunidad (*"Sugerencia Verificada de la Comunidad Nexus"*) al escanear un código nuevo en el checkout.
    - *Objetivo:* Integración reactiva en el buscador de ventas que permite aceptar la sugerencia con 1 solo toque.
  - **15.2.2 (2.0h) — Diálogo de Clonación de Catálogo a Nueva Tienda:**
    - *Contexto:* Asistente para seleccionar tienda origen y clonar productos hacia una nueva sucursal aliada.
    - *Objetivo:* Wizard interactivo con barra de progreso de duplicación.
  - **15.2.3 (2.0h) — Dashboard Analítico y Reportes de Rentabilidad:**
    - *Contexto:* Gráficos interactivos de ventas diarias, productos más vendidos, margen de ganancia neta en `$ MXN` y comparativa mensual.
    - *Objetivo:* `AnalyticsDashboardScreen` en `features/analytics/presentation/`.

---

### 🗓️ DÍA 16: Hardening de Seguridad RLS, Testing E2E y Despliegue Piloto

#### Tarea 16.1: Hardening de Seguridad, Optimización PostgreSQL y CI/CD
- **Responsable:** Alan
- **Tiempo Total Estimado:** 6 Horas
- **Dependencias:** Todos los módulos Backend
- **Historia de Usuario / Caso de Uso:** `HU-25 / CU-31: Blindaje de Seguridad, Rendimiento y Despliegue en Servidor`  
  *"Como equipo fundador, queremos asegurar que el backend soporte la carga en producción sin lentitud, tenga copias de seguridad diarias automáticas y que ninguna consulta vulnere el aislamiento multi-tenant."*
- **Contexto y Justificación:** Antes de lanzar el piloto con comercios reales, es imperativo auditar la seguridad, optimizar consultas pesadas y automatizar los backups en la nube a costo $0 (Constitución Art. IV).
- **Objetivo:** Realizar el hardening final de seguridad, optimización de base de datos y configuración del despliegue en producción.
- **Subtareas:**
  - **16.1.1 (2.0h) — Auditoría Integral de Seguridad RLS y Suite de Pruebas Pytest:**
    - *Contexto:* Revisión exhaustiva de todas las políticas de Row-Level Security en PostgreSQL y ejecución de pruebas E2E automatizadas.
    - *Objetivo:* Cobertura superior al 85% en módulos críticos con 0 vulnerabilidades de fuga multi-tenant.
  - **16.1.2 (2.0h) — Optimización de Índices de Base de Datos y Backups Diarios:**
    - *Contexto:* Creación de índices compuestos `(tenant_id, created_at)` y script cron de respaldo diario comprimido hacia Cloudflare R2 / Backblaze B2.
    - *Objetivo:* Script de backup automatizado con retención de 30 días a costo $0.
  - **16.1.3 (2.0h) — Pipeline CI/CD en GitHub Actions y Despliegue en VPS:**
    - *Contexto:* Despliegue automatizado del backend FastAPI en servidor VPS (Hetzner/Contabo) con Docker y Nginx SSL.
    - *Objetivo:* Servidor de producción en línea con certificado HTTPS y reinicio automático ante fallos.

---

#### Tarea 16.2: Pruebas de Humo UI, Validación en Smartphones Reales y Release
- **Responsable:** Eduardo
- **Tiempo Total Estimado:** 6 Horas
- **Dependencias:** Todos los módulos Frontend
- **Historia de Usuario / Caso de Uso:** `HU-25 / CU-32: Validación de Experiencia de Usuario en Campo y Release del MVP`  
  *"Como equipo fundador, queremos probar la aplicación completa en teléfonos Android reales de gama baja en tienditas piloto para asegurar que la cámara escanee rápido, la app no se trabe y el comerciante pueda vender sin problemas."*
- **Contexto y Justificación:** La prueba de fuego del software ocurre en el mostrador real frente a los clientes. Se debe verificar la fluidez de la app en hardware modesto antes de la entrega final (Constitución Art. I, Principio 5).
- **Objetivo:** Ejecutar pruebas de humo integrales, compilar la versión final de producción y poner en marcha el piloto con las primeras 3 tienditas en México.
- **Subtareas:**
  - **16.2.1 (2.0h) — Pruebas de Humo E2E de Flujos Críticos:**
    - *Contexto:* Validación completa del flujo integral: *Login ➔ Onboarding ➔ Carga Inventario ➔ Escaneo Góndola ➔ Venta POS ➔ Cobro Vuelto MXN ➔ Arqueo Caja con Cono Banxico*.
    - *Objetivo:* Comprobar que no existan bloqueos de UI, errores de navegación ni pérdidas de estado en Riverpod.
  - **16.2.2 (2.0h) — Pruebas de Rendimiento en Smartphones Android Reales:**
    - *Contexto:* Instalación en dispositivos Android de gama baja/media (2-3GB RAM) probando velocidad del escáner `mobile_scanner` y OCR con Google ML Kit.
    - *Objetivo:* Garantizar respuesta táctil en < 100ms y reconocimiento de códigos de barras en < 1 segundo.
  - **16.2.3 (2.0h) — Compilación de Release APK y Despliegue de Flutter Web:**
    - *Contexto:* Generación de binarios APK optimizados y firmados para Android y publicación del frontend web en Vercel/Cloudflare Pages.
    - *Objetivo:* Entrega formal del MVP de Nexus v3.0 listo para operar en comercios minoristas mexicanos.

---

## 📊 RESUMEN DE DISTRIBUCIÓN HORARIA Y COBERTURA DE REQUISITOS

| Módulo Funcional | Tareas Alan (Backend) | Tareas Eduardo (Frontend) | Total Horas | Historias de Usuario / Casos de Uso Cubiertos |
|---|---|---|---|---|
| **M01: Core, Auth & Onboarding** | 12.0 h | 12.0 h | **24.0 h** | `HU-01`, `HU-02`, `HU-03`, `HU-04` / `CU-01` a `CU-04` |
| **M02: Inventario & Góndola** | 18.0 h | 18.0 h | **36.0 h** | `HU-05`, `HU-06`, `HU-07`, `HU-08`, `HU-09`, `HU-10` / `CU-05` a `CU-10` |
| **M03: POS, Checkout & Vuelto** | 18.0 h | 18.0 h | **36.0 h** | `HU-11`, `HU-12`, `HU-13`, `HU-14` / `CU-11` a `CU-16` |
| **M04: Caja & Cono Banxico** | 12.0 h | 12.0 h | **24.0 h** | `HU-15`, `HU-16` / `CU-17` a `CU-20` |
| **M05: Compras, Proveedores & OCR** | 12.0 h | 12.0 h | **24.0 h** | `HU-17`, `HU-18`, `HU-19` / `CU-21` a `CU-24` |
| **M06: Catálogo Web WhatsApp** | 6.0 h | 6.0 h | **12.0 h** | `HU-20` / `CU-25`, `CU-26` |
| **M07: Suscripciones SaaS** | 6.0 h | 6.0 h | **12.0 h** | `HU-21`, `HU-22` / `CU-27`, `CU-28` |
| **M08: Red Comunitaria & Consenso** | 6.0 h | 6.0 h | **12.0 h** | `HU-23`, `HU-24` / `CU-29`, `CU-30` |
| **M09: Hardening, Release & Piloto** | 6.0 h | 6.0 h | **12.0 h** | `HU-25` / `CU-31`, `CU-32` |
| **TOTAL GENERAL** | **96.0 h** | **96.0 h** | **192.0 h** | **100% Requisitos SDD y Constitución** |
