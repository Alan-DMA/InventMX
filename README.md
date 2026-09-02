# NEXUS v3.0 — Gestión Comercial Modular (Retail México)

Sistema de gestión comercial y control de inventario SaaS Multi-tenant optimizado para el comercio minorista en México (tienditas de abarrotes, misceláneas, minisuper y comercios independientes).

---

## 🏛️ Arquitectura del Repositorio

El proyecto implementa una arquitectura modular con estricta **separación de responsabilidades por capas**, tanto en el Backend como en el Frontend.

```text
nexus_v3/
├── docs/                             # Documentación de arquitectura, base de datos y APIs
│   ├── architecture/
│   ├── database/
│   └── api/
├── backend/                          # Backend FastAPI (Modular Clean Architecture)
│   ├── app/
│   │   ├── core/                     # Configuración transversal, DB, seguridad y middleware
│   │   │   ├── config/
│   │   │   ├── database/
│   │   │   ├── security/
│   │   │   ├── middleware/
│   │   │   └── exceptions/
│   │   ├── modules/                  # Módulos de Dominio / Funcionales
│   │   │   ├── auth_tenancy/         # Autenticación, multi-tenancy RLS y roles RBAC
│   │   │   ├── inventory/            # Inventario, productos, stock multi-almacén y combos
│   │   │   ├── sales_pos/            # Punto de venta, checkout rápido y cálculo de cambio MXN
│   │   │   ├── cash_treasury/        # Control de caja y arqueo con cono monetario Banxico
│   │   │   ├── purchasing_suppliers/ # Compras, proveedores y cuentas por pagar
│   │   │   ├── whatsapp_catalog/     # Catálogo público y pedidos estructurados por WhatsApp
│   │   │   ├── analytics_reports/    # Métricas operativas y reportes de rentabilidad
│   │   │   ├── saas_billing/         # Suscripciones SaaS (SPEI, OXXO Pay, Mercado Pago)
│   │   │   └── community_catalog/    # Catálogo semilla EAN-13 y red comunitaria con consenso
│   │   └── shared/                   # Paginación, constantes y utilidades compartidas
│   ├── migrations/                   # Migraciones de base de datos Alembic
│   ├── tests/                        # Pruebas unitarias, de integración y E2E
│   └── scripts/                      # Scripts de mantenimiento y seeds
│
└── frontend/                         # Frontend Flutter (Feature-First Layered Architecture)
    ├── lib/
    │   ├── core/                     # Tema visual, cliente de red, almacenamiento y router
    │   │   ├── theme/
    │   │   ├── network/
    │   │   ├── storage/
    │   │   ├── router/
    │   │   ├── utils/
    │   │   ├── constants/
    │   │   └── widgets/
    │   ├── features/                 # Módulos Funcionales (Feature-First)
    │   │   ├── auth/                 # Autenticación y sesión
    │   │   ├── onboarding/           # Onboarding gamificado y setup asistido
    │   │   ├── inventory/            # Catálogo de productos, OCR facturas y góndola
    │   │   ├── sales_pos/            # Terminal de venta y cobro con vuelto en MXN
    │   │   ├── cash_treasury/        # Wizard de arqueo con denominaciones Banxico
    │   │   ├── purchases/            # Compras y proveedores
    │   │   ├── whatsapp_catalog/     # Catálogo digital WhatsApp
    │   │   ├── analytics/            # Dashboard y reportes
    │   │   └── saas_admin/           # Panel administrativo SaaS para fundadores
    │   └── assets/                   # Iconos, imágenes y catálogo semilla offline
    └── test/                         # Pruebas unitarias, de widgets e integración
```

---

## 📦 Separación de Capas por Módulo

### Capas del Backend (`backend/app/modules/<module_name>/`)
1. **`domain/`**: Entidades y modelos de datos (SQLAlchemy / Reglas de negocio puras).
2. **`schemas/`**: DTOs y validaciones de entrada/salida (Pydantic models).
3. **`repositories/`**: Consultas directas a la base de datos PostgreSQL y aislamiento RLS.
4. **`services/`**: Casos de uso y lógica de aplicación.
5. **`api/`**: Controladores de endpoints y rutas de FastAPI.

### Capas del Frontend (`frontend/lib/features/<feature_name>/`)
1. **`presentation/`**: Vistas (Screens), Widgets UI interactivos y manejadores de estado (Riverpod StateNotifier / Notifier).
2. **`domain/`**: Modelos de datos y contratos de repositorios.
3. **`data/`**: Fuentes de datos remotas/locales, modelos DTO y repositorios de red.

---

## 🇲🇽 Especificaciones Mexicanas Clave
- **Moneda Base:** Pesos Mexicanos (MXN).
- **Arqueo de Caja:** Denominaciones oficiales del Banco de México (Billetes $20-$1000, Monedas $0.50-$20).
- **Pasarelas SaaS:** SPEI (STP / CLABE interbancaria) y OXXO Pay (referencias de 14 dígitos).
- **Onboarding sin Fricción:** Formulario de 3 campos vitales, escáner continuo de góndola, OCR On-Device local y catálogo semilla EAN-13 GS1 México.
- **Marco Fiscal:** Notas de venta y comprobantes administrativos internos (sin timbrado CFDI 4.0 / SAT en esta fase).
