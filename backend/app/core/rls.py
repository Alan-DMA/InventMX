import contextvars
from typing import Optional
from uuid import UUID

# ContextVar para almacenar de manera segura el tenant_id de la petición actual
_current_tenant_ctx = contextvars.ContextVar("current_tenant", default=None)

def set_current_tenant(tenant_id: Optional[UUID]) -> contextvars.Token:
    """Establece el tenant_id en el contexto de la petición actual."""
    # Convertimos a string para simplificar el manejo en base de datos
    val = str(tenant_id) if tenant_id is not None else None
    return _current_tenant_ctx.set(val)

def get_current_tenant() -> Optional[str]:
    """Obtiene el tenant_id del contexto de la petición actual."""
    return _current_tenant_ctx.get()

def reset_current_tenant(token: contextvars.Token) -> None:
    """Restablece el contexto al valor anterior."""
    _current_tenant_ctx.reset(token)
