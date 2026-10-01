"""
Sesión de soporte de sólo lectura — etapa 4 del Centro de soporte (P37–P39).

Con la concesión del dueño vigente, un operador abre una sesión con motivo y
ve la tienda en la app real del tendero (una pestaña aparte), como la ve el
dueño y sin poder cambiar nada:

1. Panel: `start` crea la sesión y un enlace de un solo uso (10 min). Sólo se
   guarda la huella del enlace; el código viaja una vez al panel.
2. Pestaña: `open_with_code` canjea el enlace por un token del comercio que
   actúa como el dueño y lleva dentro al operador. El reloj de 30 min empieza
   aquí, la primera vez; "Abrir de nuevo" da otro enlace sin reiniciarlo.
3. Cada petición con ese token pasa por `check_request`: sesión, concesión y
   operador vigentes; si no, 401 `SUPPORT_ACCESS_ENDED`. La escritura la
   rechaza antes el middleware `SupportReadOnlyMiddleware` (403).
4. "Seguir 30 min más" cuando quedan 10 min o menos, nunca más allá de la
   concesión. "Terminar" desde la pestaña o el panel; salir del panel termina
   las del operador.

El dueño ve en Acceso de soporte quién entró, cuándo, cuánto duró, el motivo y
las secciones consultadas (P38).
"""
import hashlib
import secrets
import uuid
from contextlib import asynccontextmanager
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from typing import Dict, List, Optional, Sequence

from pydantic import BaseModel, Field
from sqlalchemy import select, text
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.core.config.settings import settings
from app.core.database.session import AsyncSessionLocal, set_tenant_context
from app.core.exceptions.base import AppException
from app.core.security.jwt import create_support_access_token
from app.modules.auth_tenancy.domain.tenant import Tenant
from app.modules.auth_tenancy.domain.user import User
from app.modules.platform_admin.domain.audit_log import AuditAction
from app.modules.platform_admin.domain.operator import PlatformOperator
from app.modules.platform_admin.domain.support import SessionEndReason, SupportAccessGrant, SupportSession
from app.modules.platform_admin.repositories.audit_repository import AuditRepository, RequestMeta
from app.modules.platform_admin.schemas.platform_schemas import SessionState, SupportSessionRead
from app.modules.support_cases.domain.models import SupportCase

SESSION_MINUTES = 30
LINK_MINUTES = 10
EXTEND_WHEN_REMAINING = timedelta(minutes=10)

_API = settings.API_V1_STR

# Secciones de la app que el dueño lee en su historial (P38), por la primera
# parte de la ruta. Lo que no está aquí (sesión, /auth/me…) no se anota.
SECTIONS: Dict[str, str] = {
    "inventory": "Inventario",
    "sales": "Ventas",
    "cash": "Caja",
    "customers": "Clientes y fiados",
    "suppliers": "Compras y proveedores",
    "purchase-orders": "Compras y proveedores",
    "accounts-payable": "Compras y proveedores",
    "purchases": "Compras y proveedores",
    "analytics": "Reportes",
    "users": "Equipo",
    "roles": "Equipo",
    "permissions": "Equipo",
    "catalog-orders": "Catálogo y pedidos",
    "catalog-settings": "Catálogo y pedidos",
    "subscription": "Suscripción",
    "billing": "Suscripción",
    "support": "Soporte",
    "b2b": "Red de comercios",
}

# Ni siquiera para leer: respaldos y salud del sistema no son "lo que ve el dueño".
BLOCKED_PREFIXES = (f"{_API}/admin",)

END_TEXT = {
    SessionEndReason.OPERATOR: "Soporte la terminó",
    SessionEndReason.SIGNED_OUT: "Soporte salió del panel",
    SessionEndReason.EXPIRED: "Se acabó el tiempo",
    SessionEndReason.GRANT_ENDED: "Terminó tu permiso",
    SessionEndReason.NOT_OPENED: "No se llegó a abrir",
    SessionEndReason.OPERATOR_INACTIVE: "Terminó por seguridad",
}


def section_for(path: str) -> Optional[str]:
    if not path.startswith(_API + "/"):
        return None
    first = path[len(_API) + 1:].split("/", 1)[0]
    return SECTIONS.get(first)


def _hash(code: str) -> str:
    return hashlib.sha256(code.encode("utf-8")).hexdigest()


def _ended(reason: str, message: Optional[str] = None) -> AppException:
    return AppException(
        message=message or "El acceso de soporte terminó.",
        code="SUPPORT_ACCESS_ENDED",
        status_code=401,
        details={"end_reason": reason},
    )


def _conflict(message: str) -> AppException:
    return AppException(message=message, code="SUPPORT_SESSION_CONFLICT", status_code=409)


def _end_event(
    session: SupportSession, grant: Optional[SupportAccessGrant], operator: Optional[PlatformOperator], now: datetime
) -> Optional[tuple]:
    """(cuándo, por qué) dejó de valer la sesión: lo que ocurrió primero. None si sigue."""
    if session.ended_at is not None:
        return session.ended_at, session.end_reason
    events = []
    if operator is None or not operator.is_active:
        events.append((now, SessionEndReason.OPERATOR_INACTIVE))
    if grant is None:
        events.append((now, SessionEndReason.GRANT_ENDED))
    else:
        cut = grant.revoked_at or grant.expires_at
        if cut <= now:
            events.append((cut, SessionEndReason.GRANT_ENDED))
    if session.opened_at is None:
        if session.link_expires_at is None or session.link_expires_at <= now:
            events.append((session.link_expires_at or now, SessionEndReason.NOT_OPENED))
    elif session.expires_at is None or session.expires_at <= now:
        events.append((session.expires_at or now, SessionEndReason.EXPIRED))
    return min(events, key=lambda e: e[0]) if events else None


def effective_end(session, grant, operator, now: datetime) -> Optional[str]:
    """Por qué ya no vale la sesión (aunque nadie lo haya anotado aún), o None si sigue."""
    event = _end_event(session, grant, operator, now)
    return event[1] if event else None


def _settle(session: SupportSession, grant, operator, now: datetime) -> Optional[str]:
    """Anota el final si ya ocurrió. Devuelve el motivo si la sesión ya no vale."""
    event = _end_event(session, grant, operator, now)
    if event is None:
        return None
    if session.ended_at is None:
        session.ended_at, session.end_reason = event
        session.link_hash = None
        session.link_expires_at = None
    return event[1]


# ── Lecturas ───────────────────────────────────────────────────────────────

class SessionLink(BaseModel):
    """El código del enlace sale una sola vez; el panel arma la URL de la pestaña."""
    session: SupportSessionRead
    link_code: str
    link_expires_at: datetime


class SupportSessionStatus(BaseModel):
    """Lo que el marco de la pestaña muestra."""
    session_id: str
    tenant_name: str
    operator_name: str
    reason: str
    opened_at: datetime
    expires_at: datetime
    grant_expires_at: datetime
    extensions: int
    can_extend: bool


class OpenedSupportSession(BaseModel):
    access_token: str
    token_type: str = "bearer"
    status: SupportSessionStatus


class OwnerSessionRead(BaseModel):
    """Lo que el dueño ve de cada entrada de soporte (P38)."""
    id: str
    by: str
    reason: str
    active: bool
    opened_at: Optional[datetime] = None
    ended_at: Optional[datetime] = None
    minutes: Optional[int] = Field(None, description="Cuánto duró (o lleva, si sigue)")
    sections: List[str] = []
    end_text: Optional[str] = None


class StartSessionRequest(BaseModel):
    reason: str = Field(..., min_length=10, max_length=500, description="Por qué entra soporte (lo lee el dueño)")
    case_id: Optional[uuid.UUID] = Field(None, description="Caso de la tienda que motiva la entrada")


def _state(session: SupportSession, end: Optional[str]) -> SessionState:
    if end is not None:
        return "ENDED"
    return "WAITING_OPEN" if session.opened_at is None else "OPEN"


def session_read(session: SupportSession, operator_name: str, end: Optional[str]) -> SupportSessionRead:
    return SupportSessionRead(
        id=str(session.id),
        tenant_id=str(session.tenant_id),
        operator_id=str(session.operator_id),
        operator_name=operator_name,
        reason=session.reason,
        case_id=str(session.case_id) if session.case_id else None,
        state=_state(session, end),
        created_at=session.created_at,
        opened_at=session.opened_at,
        expires_at=session.expires_at,
        link_expires_at=session.link_expires_at if end is None else None,
        extensions=session.extensions,
        sections=list(session.sections or []),
        ended_at=session.ended_at,
        end_reason=end,
    )


@dataclass
class _Loaded:
    session: SupportSession
    grant: Optional[SupportAccessGrant]
    operator: Optional[PlatformOperator]


async def _load(db: AsyncSession, sessions: Sequence[SupportSession]) -> List[_Loaded]:
    grant_ids = {s.grant_id for s in sessions}
    op_ids = {s.operator_id for s in sessions}
    grants = {
        g.id: g for g in (await db.execute(select(SupportAccessGrant).where(SupportAccessGrant.id.in_(grant_ids)))).scalars()
    } if grant_ids else {}
    ops = {
        o.id: o for o in (await db.execute(select(PlatformOperator).where(PlatformOperator.id.in_(op_ids)))).scalars()
    } if op_ids else {}
    return [_Loaded(s, grants.get(s.grant_id), ops.get(s.operator_id)) for s in sessions]


@asynccontextmanager
async def _cross_tenant(db: AsyncSession):
    """Salto de RLS local a la transacción (las dos tablas lo aceptan)."""
    await db.execute(text("SELECT set_config('app.bypass_rls', 'on', true);"))
    try:
        yield
    finally:
        await db.execute(text("SELECT set_config('app.bypass_rls', 'off', true);"))


def _status(loaded: _Loaded, tenant_name: str, now: datetime) -> SupportSessionStatus:
    s, grant = loaded.session, loaded.grant
    remaining = s.expires_at - now
    return SupportSessionStatus(
        session_id=str(s.id),
        tenant_name=tenant_name,
        operator_name=loaded.operator.full_name if loaded.operator else "Soporte",
        reason=s.reason,
        opened_at=s.opened_at,
        expires_at=s.expires_at,
        grant_expires_at=grant.expires_at,
        extensions=s.extensions,
        can_extend=remaining <= EXTEND_WHEN_REMAINING and grant.expires_at > s.expires_at,
    )


def _token(loaded: _Loaded, owner: User) -> str:
    s = loaded.session
    return create_support_access_token(
        subject=owner.id,
        tenant_id=s.tenant_id,
        role=owner.role.name if owner.role else "OWNER",
        tenant_status=owner.tenant.status.value if owner.tenant else "ACTIVE",
        session_id=s.id,
        operator_id=s.operator_id,
        expires_at=s.expires_at,
    )


# ── Panel ──────────────────────────────────────────────────────────────────

class PanelSupportSessions:
    """Lo que el operador hace desde el panel. Lee entre comercios (salta RLS)."""

    def __init__(self, db: AsyncSession, operator: PlatformOperator, meta: RequestMeta = RequestMeta()):
        self.db = db
        self.operator = operator
        self.meta = meta
        self.audit = AuditRepository(db)

    async def start(self, tenant_id: uuid.UUID, data: StartSessionRequest) -> SessionLink:
        now = datetime.now(timezone.utc)
        async with _cross_tenant(self.db):
            tenant = (await self.db.execute(select(Tenant).where(Tenant.id == tenant_id))).scalar_one_or_none()
            if tenant is None:
                raise AppException(message="Tienda no encontrada.", code="NOT_FOUND", status_code=404)
            grant = (await self.db.execute(
                select(SupportAccessGrant)
                .where(
                    SupportAccessGrant.tenant_id == tenant_id,
                    SupportAccessGrant.revoked_at.is_(None),
                    SupportAccessGrant.expires_at > now,
                )
                .order_by(SupportAccessGrant.expires_at.desc())
                .limit(1)
            )).scalar_one_or_none()
            if grant is None:
                raise _conflict("El dueño no ha dado acceso de soporte, o ya venció. Pídeselo desde su caso.")
            owner = (await self.db.execute(
                select(User).where(User.id == grant.granted_by_user_id)
            )).scalar_one_or_none()
            if owner is None or not owner.is_active:
                raise _conflict("Quien concedió el acceso ya no está activo en la tienda.")
            if data.case_id is not None:
                case_tenant = (await self.db.execute(
                    select(SupportCase.tenant_id).where(SupportCase.id == data.case_id)
                )).scalar_one_or_none()
                if case_tenant != tenant_id:
                    raise AppException(message="Ese caso no es de esta tienda.", code="VALIDATION_ERROR", status_code=422)
            mine = (await self.db.execute(
                select(SupportSession).where(
                    SupportSession.tenant_id == tenant_id,
                    SupportSession.operator_id == self.operator.id,
                    SupportSession.ended_at.is_(None),
                )
            )).scalars().all()
            for loaded in await _load(self.db, mine):
                if _settle(loaded.session, loaded.grant, loaded.operator, now) is None:
                    raise _conflict("Ya tienes una sesión abierta en esta tienda: usa «Abrir de nuevo».")

            code = secrets.token_urlsafe(32)
            session = SupportSession(
                tenant_id=tenant_id,
                grant_id=grant.id,
                operator_id=self.operator.id,
                acting_user_id=owner.id,
                reason=data.reason.strip(),
                case_id=data.case_id,
                link_hash=_hash(code),
                link_expires_at=now + timedelta(minutes=LINK_MINUTES),
                sections=[],
                created_at=now,
            )
            self.db.add(session)
            await self.db.flush()
        await self.audit.append(
            AuditAction.SUPPORT_SESSION_STARTED,
            operator_id=self.operator.id,
            target_tenant_id=tenant_id,
            target_type="support_session",
            target_id=str(session.id),
            reason=session.reason,
            details={"caso": str(data.case_id) if data.case_id else None, "minutos": SESSION_MINUTES},
            meta=self.meta,
        )
        await self.db.commit()
        return SessionLink(
            session=session_read(session, self.operator.full_name, None),
            link_code=code,
            link_expires_at=session.link_expires_at,
        )

    async def new_link(self, session_id: uuid.UUID) -> SessionLink:
        """"Abrir de nuevo": otro enlace para la misma sesión, sin pedir motivo ni reiniciar el reloj."""
        now = datetime.now(timezone.utc)
        async with _cross_tenant(self.db):
            loaded = await self._mine_or_404(session_id)
            end = _settle(loaded.session, loaded.grant, loaded.operator, now)
            if end is not None:
                await self.db.commit()
                raise _ended(end, "Esta sesión ya terminó. Abre una nueva con su motivo.")
            code = secrets.token_urlsafe(32)
            loaded.session.link_hash = _hash(code)
            loaded.session.link_expires_at = now + timedelta(minutes=LINK_MINUTES)
            await self.db.flush()
            read = session_read(loaded.session, self.operator.full_name, None)
        await self.db.commit()
        return SessionLink(session=read, link_code=code, link_expires_at=loaded.session.link_expires_at)

    async def end(self, session_id: uuid.UUID, reason: str = SessionEndReason.OPERATOR) -> SupportSessionRead:
        now = datetime.now(timezone.utc)
        async with _cross_tenant(self.db):
            loaded = await self._mine_or_404(session_id)
            ended_now = await self._end(loaded, reason, now)
            read = session_read(loaded.session, self.operator.full_name, loaded.session.end_reason)
        if ended_now:
            await self._audit_end(loaded.session)
        await self.db.commit()
        return read

    async def end_all_mine(self) -> int:
        """Al salir del panel, sus sesiones abiertas terminan (SIGNED_OUT)."""
        now = datetime.now(timezone.utc)
        async with _cross_tenant(self.db):
            rows = (await self.db.execute(
                select(SupportSession).where(
                    SupportSession.operator_id == self.operator.id, SupportSession.ended_at.is_(None)
                )
            )).scalars().all()
            ended = []
            for loaded in await _load(self.db, rows):
                if await self._end(loaded, SessionEndReason.SIGNED_OUT, now):
                    ended.append(loaded.session)
        for session in ended:
            await self._audit_end(session)
        await self.db.commit()
        return len(ended)

    async def _end(self, loaded: _Loaded, reason: str, now: datetime) -> bool:
        """Termina con `reason` si seguía vigente. True si la terminó esta llamada."""
        s = loaded.session
        if s.ended_at is not None:
            return False
        if _settle(s, loaded.grant, loaded.operator, now) is not None:
            return False  # ya había terminado sola: se anota su motivo real
        s.ended_at = now
        s.end_reason = reason
        s.link_hash = None
        s.link_expires_at = None
        await self.db.flush()
        return True

    async def _audit_end(self, session: SupportSession) -> None:
        await self.audit.append(
            AuditAction.SUPPORT_SESSION_ENDED,
            operator_id=self.operator.id,
            target_tenant_id=session.tenant_id,
            target_type="support_session",
            target_id=str(session.id),
            details={"fin": session.end_reason, "secciones": list(session.sections or [])},
            meta=self.meta,
        )

    async def _mine_or_404(self, session_id: uuid.UUID) -> _Loaded:
        session = (await self.db.execute(
            select(SupportSession).where(SupportSession.id == session_id)
        )).scalar_one_or_none()
        if session is None or session.operator_id != self.operator.id:
            raise AppException(message="Sesión no encontrada.", code="NOT_FOUND", status_code=404)
        return (await _load(self.db, [session]))[0]


async def open_sessions(
    db: AsyncSession, tenant_id: Optional[uuid.UUID] = None
) -> List[SupportSessionRead]:
    """Sesiones vigentes (esperando abrirse o abiertas), para la ficha y el feed. Sólo lee."""
    now = datetime.now(timezone.utc)
    conditions = [SupportSession.ended_at.is_(None)]
    if tenant_id is not None:
        conditions.append(SupportSession.tenant_id == tenant_id)
    async with _cross_tenant(db):
        rows = (await db.execute(
            select(SupportSession).where(*conditions).order_by(SupportSession.created_at.desc())
        )).scalars().all()
        loaded = await _load(db, rows)
    reads = []
    for item in loaded:
        end = effective_end(item.session, item.grant, item.operator, now)
        if end is None:
            reads.append(session_read(item.session, item.operator.full_name, None))
    return reads


# ── Pestaña de soporte ─────────────────────────────────────────────────────

class TabSupportSession:
    """Lo que hace la pestaña: canjear el enlace, ver su estado, extender, terminar."""

    def __init__(self, db: AsyncSession, meta: RequestMeta = RequestMeta()):
        self.db = db
        self.meta = meta
        self.audit = AuditRepository(db)

    async def open_with_code(self, code: str) -> OpenedSupportSession:
        now = datetime.now(timezone.utc)
        async with _cross_tenant(self.db):
            session = (await self.db.execute(
                select(SupportSession).where(SupportSession.link_hash == _hash(code.strip()))
            )).scalar_one_or_none()
            if session is None:
                raise AppException(
                    message="Este enlace ya se usó o no es válido. Ábrelo de nuevo desde el panel.",
                    code="SUPPORT_LINK_INVALID",
                    status_code=410,
                )
            loaded = (await _load(self.db, [session]))[0]
            if session.link_expires_at is None or now >= session.link_expires_at:
                # Un enlace vencido no abre nada; si la sesión nunca se abrió, ahí termina
                if session.opened_at is None:
                    _settle(session, loaded.grant, loaded.operator, now)
                session.link_hash = None
                session.link_expires_at = None
                await self.db.commit()
                raise AppException(
                    message="Este enlace venció. Ábrelo de nuevo desde el panel.",
                    code="SUPPORT_LINK_EXPIRED",
                    status_code=410,
                )
            end = _settle(session, loaded.grant, loaded.operator, now)
            if end is not None:
                await self.db.commit()
                raise _ended(end)
            owner = (await self.db.execute(
                select(User)
                .where(User.id == session.acting_user_id)
                .options(selectinload(User.role), selectinload(User.tenant))
            )).scalar_one_or_none()
            if owner is None or not owner.is_active:
                raise _ended(SessionEndReason.GRANT_ENDED, "Quien concedió el acceso ya no está activo en la tienda.")
            if session.opened_at is None:
                session.opened_at = now
                session.expires_at = min(now + timedelta(minutes=SESSION_MINUTES), loaded.grant.expires_at)
            session.link_hash = None
            session.link_expires_at = None
            await self.db.flush()
            status = _status(loaded, owner.tenant.name if owner.tenant else "Tienda", now)
            token = _token(loaded, owner)
        await self.db.commit()
        return OpenedSupportSession(access_token=token, status=status)

    async def status(self, payload: dict) -> SupportSessionStatus:
        loaded, owner, now = await self._current(payload)
        return _status(loaded, owner.tenant.name if owner.tenant else "Tienda", now)

    async def extend(self, payload: dict) -> OpenedSupportSession:
        """+30 min sobre lo que queda, sólo con 10 min o menos y nunca más allá de la concesión."""
        loaded, owner, now = await self._current(payload)
        s = loaded.session
        status = _status(loaded, owner.tenant.name if owner.tenant else "Tienda", now)
        if not status.can_extend:
            raise _conflict(
                "Todavía no: se puede seguir cuando falten 10 minutos o menos."
                if s.expires_at - now > EXTEND_WHEN_REMAINING
                else "El permiso del dueño termina antes: no se puede extender más."
            )
        s.expires_at = min(s.expires_at + timedelta(minutes=SESSION_MINUTES), loaded.grant.expires_at)
        s.extensions += 1
        await self.audit.append(
            AuditAction.SUPPORT_SESSION_EXTENDED,
            operator_id=s.operator_id,
            target_tenant_id=s.tenant_id,
            target_type="support_session",
            target_id=str(s.id),
            details={"vence": s.expires_at.isoformat(), "extension": s.extensions},
            meta=self.meta,
        )
        status = _status(loaded, owner.tenant.name if owner.tenant else "Tienda", now)
        token = _token(loaded, owner)
        await self.db.commit()
        return OpenedSupportSession(access_token=token, status=status)

    async def end(self, payload: dict) -> None:
        """"Terminar" desde la pestaña. Si ya había terminado, no hace nada."""
        now = datetime.now(timezone.utc)
        session_id, tenant_id = _ids(payload)
        await set_tenant_context(self.db, tenant_id)
        session = (await self.db.execute(
            select(SupportSession).where(SupportSession.id == session_id)
        )).scalar_one_or_none()
        if session is None or session.ended_at is not None:
            return
        loaded = (await _load(self.db, [session]))[0]
        if _settle(session, loaded.grant, loaded.operator, now) is None:
            session.ended_at = now
            session.end_reason = SessionEndReason.OPERATOR
            session.link_hash = None
            session.link_expires_at = None
            await self.audit.append(
                AuditAction.SUPPORT_SESSION_ENDED,
                operator_id=session.operator_id,
                target_tenant_id=session.tenant_id,
                target_type="support_session",
                target_id=str(session.id),
                details={"fin": session.end_reason, "secciones": list(session.sections or [])},
                meta=self.meta,
            )
        await self.db.commit()

    async def _current(self, payload: dict):
        now = datetime.now(timezone.utc)
        session_id, tenant_id = _ids(payload)
        await set_tenant_context(self.db, tenant_id)
        session = (await self.db.execute(
            select(SupportSession).where(SupportSession.id == session_id)
        )).scalar_one_or_none()
        if session is None:
            raise _ended(SessionEndReason.GRANT_ENDED)
        loaded = (await _load(self.db, [session]))[0]
        end = _settle(session, loaded.grant, loaded.operator, now)
        if end is not None:
            await self.db.commit()
            raise _ended(end)
        owner = (await self.db.execute(
            select(User)
            .where(User.id == session.acting_user_id)
            .options(selectinload(User.role), selectinload(User.tenant))
        )).scalar_one_or_none()
        if owner is None or not owner.is_active:
            raise _ended(SessionEndReason.GRANT_ENDED)
        return loaded, owner, now


def _ids(payload: dict):
    try:
        return uuid.UUID(str(payload["support_session"])), uuid.UUID(str(payload["tenant_id"]))
    except (KeyError, ValueError) as exc:
        raise _ended(SessionEndReason.GRANT_ENDED) from exc


# ── Cada petición con token de soporte ─────────────────────────────────────

async def check_request(db: AsyncSession, payload: dict, user: User, path: str) -> None:
    """
    Lo llama `get_current_user` con el contexto RLS del comercio ya fijado. La
    sesión en la base manda sobre el token: retirar el permiso corta aquí.
    """
    if path.startswith(BLOCKED_PREFIXES):
        raise AppException(
            message="Esto no está disponible en modo soporte.", code="SUPPORT_NOT_ALLOWED", status_code=403
        )
    now = datetime.now(timezone.utc)
    session_id, tenant_id = _ids(payload)
    session = (await db.execute(
        select(SupportSession).where(SupportSession.id == session_id)
    )).scalar_one_or_none()
    if session is None or session.tenant_id != tenant_id or session.acting_user_id != user.id:
        raise _ended(SessionEndReason.GRANT_ENDED)
    loaded = (await _load(db, [session]))[0]
    if session.opened_at is None:
        raise _ended(SessionEndReason.NOT_OPENED)
    end = effective_end(session, loaded.grant, loaded.operator, now)
    if end is not None:
        await _write(tenant_id, session_id, settle=True)
        raise _ended(end)
    label = section_for(path)
    if label and label not in (session.sections or []):
        await _write(tenant_id, session_id, section=label)


async def _write(tenant_id: uuid.UUID, session_id: uuid.UUID, settle: bool = False, section: Optional[str] = None):
    """
    Escribe en su propia transacción: la petición en curso es de lectura y su
    sesión no se confirma. Anotar una sección es idempotente en SQL (dos
    peticiones a la vez no la duplican).
    """
    async with AsyncSessionLocal() as db:
        await set_tenant_context(db, tenant_id)
        if section:
            await db.execute(
                text(
                    "UPDATE support_sessions SET sections = sections || to_jsonb(CAST(:s AS text)) "
                    "WHERE id = :id AND NOT (sections ? :s)"
                ),
                {"s": section, "id": session_id},
            )
        if settle:
            session = (await db.execute(
                select(SupportSession).where(SupportSession.id == session_id)
            )).scalar_one_or_none()
            if session is not None:
                loaded = (await _load(db, [session]))[0]
                _settle(session, loaded.grant, loaded.operator, datetime.now(timezone.utc))
        await db.commit()


# ── Lo que ve el dueño ─────────────────────────────────────────────────────

async def sessions_for_owner(db: AsyncSession, tenant_id: uuid.UUID, limit: int = 10) -> List[OwnerSessionRead]:
    """Con el contexto RLS del dueño fijado (lo hace `get_current_user`)."""
    now = datetime.now(timezone.utc)
    rows = (await db.execute(
        select(SupportSession)
        .where(SupportSession.tenant_id == tenant_id, SupportSession.opened_at.is_not(None))
        .order_by(SupportSession.opened_at.desc())
        .limit(limit)
    )).scalars().all()
    reads = []
    for item in await _load(db, rows):
        s = item.session
        end = effective_end(s, item.grant, item.operator, now)
        event = _end_event(s, item.grant, item.operator, now)
        ended_at = event[0] if event else None
        minutes = max(1, round(((ended_at or now) - s.opened_at).total_seconds() / 60))
        name = item.operator.full_name if item.operator else "equipo"
        reads.append(OwnerSessionRead(
            id=str(s.id),
            by=f"Soporte Nexus · {name}",
            reason=s.reason,
            active=end is None,
            opened_at=s.opened_at,
            ended_at=ended_at,
            minutes=minutes,
            sections=list(s.sections or []),
            end_text=END_TEXT.get(end) if end else None,
        ))
    return reads
