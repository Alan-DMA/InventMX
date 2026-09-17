import os

# ---------------------------------------------------------------------------
# Configuración del cobro de suscripciones SaaS (Tarea 14.2)
#
# Nexus no tiene proveedor de pagos (STP / OXXO Pay) en el MVP: la
# conciliación es manual (Constitución Art. V, §5.2 "SPEI Manual"). Los
# datos bancarios de Nexus llegan por entorno para que ningún documento del
# repo tenga que conocerlos; los defaults son placeholders de desarrollo.
# ---------------------------------------------------------------------------

# CLABE interbancaria fija de Nexus a la que transfieren todos los comercios.
NEXUS_SPEI_CLABE: str = os.getenv("NEXUS_SPEI_CLABE", "000000000000000000")
NEXUS_SPEI_BANK: str = os.getenv("NEXUS_SPEI_BANK", "Banco por definir")
NEXUS_SPEI_HOLDER: str = os.getenv("NEXUS_SPEI_HOLDER", "Nexus")

# Correos con acceso al panel de fundadores (D7). Vacío = solo se exige el
# permiso `saas.manage`, que el seed de Alan otorga a todo TENANT_OWNER.
NEXUS_FOUNDER_EMAILS: frozenset[str] = frozenset(
    e.strip().lower()
    for e in os.getenv("NEXUS_FOUNDER_EMAILS", "").split(",")
    if e.strip()
)

# Días de gracia antes de cada transición de morosidad (Constitución Art. VI §6.3).
SOFT_LOCK_DAYS: int = 10  # días 1-10 tras vencer → solo lectura
HARD_LOCK_FROM_DAY: int = 11  # día 11+ → bloqueo total
