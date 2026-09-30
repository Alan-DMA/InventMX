"""
Apartado de Soporte, estilo Steam (P23–P25).

Tres puertas al mismo caso:
- `CaseService`: el tendero en su app. Corre con su contexto RLS; cada quien ve
  sus casos y el dueño los de toda la tienda (P25).
- `PublicCaseService`: el formulario sin sesión (P24). Nunca revela si el
  correo existe: responde igual siempre, con tope por correo e IP y un campo
  trampa contra bots (sin CAPTCHA, por accesibilidad).
- `CaseDeskService`: el panel. Lee y escribe entre comercios con el salto de RLS
  local a la transacción; cada respuesta y cambio de estado va a la bitácora.

Los correos (respuesta de soporte, acuse del formulario sin sesión) se
devuelven a quien llama para enviarse **después** de responder la petición.
"""
import uuid
from datetime import datetime, timedelta, timezone
from typing import Dict, List, Optional, Sequence, Tuple

from fastapi import HTTPException, status
from sqlalchemy import case as sql_case, func, or_, select, text
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database.session import set_tenant_context
from app.core.email.sender import EmailMessage
from app.core.email.templates import case_reply_email, public_case_received_email
from app.modules.auth_tenancy.domain.tenant import Tenant
from app.modules.auth_tenancy.domain.user import User
from app.modules.auth_tenancy.repositories.user_repository import UserRepository
from app.modules.platform_admin.domain.audit_log import AuditAction
from app.modules.platform_admin.domain.operator import PlatformOperator
from app.modules.platform_admin.repositories.audit_repository import AuditRepository, RequestMeta
from app.modules.platform_admin.repositories.operator_repository import OperatorRepository
from app.modules.support_cases.domain.models import (
    AuthorKind,
    CaseChannel,
    CaseStatus,
    HelpTopic,
    SupportCase,
    SupportCaseMessage,
    TopicAudience,
)
from app.modules.support_cases.schemas import (
    Answer,
    CaseCreate,
    CaseDetail,
    CaseSummary,
    DeskCaseDetail,
    DeskCasePage,
    DeskCaseSummary,
    DeskReply,
    DeskStoreContext,
    HelpTopicAdmin,
    HelpTopicRead,
    HelpTopicUpsert,
    MessageRead,
    PublicCaseCreate,
)

PUBLIC_CASES_PER_DAY = 3
ANSWER_MAX_LENGTH = 500
PREVIEW_LENGTH = 140
PUBLIC_ACCEPTED = (
    "Recibimos tu mensaje. Si los datos son correctos, te escribimos al correo de contacto que nos diste."
)


def _unprocessable(detail: str) -> HTTPException:
    return HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_CONTENT, detail=detail)


def _not_found() -> HTTPException:
    return HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Caso no encontrado.")


def validate_answers(topic: HelpTopic, answers: Dict[str, str]) -> List[dict]:
    """
    Respuestas contra el formulario vigente del tema. Se guardan con la etiqueta
    que tenían al enviarse: editar el tema después no cambia casos viejos.
    """
    cleaned: List[dict] = []
    for spec in topic.form_fields or []:
        value = str(answers.get(spec["key"], "") or "").strip()[:ANSWER_MAX_LENGTH]
        if not value:
            if spec.get("required"):
                raise _unprocessable(f"Falta responder: {spec['label']}")
            continue
        if spec.get("type") == "select" and value not in (spec.get("options") or []):
            raise _unprocessable(f"Elige una de las opciones en: {spec['label']}")
        cleaned.append({"key": spec["key"], "label": spec["label"], "value": value})
    return cleaned


def topic_read(topic: HelpTopic) -> HelpTopicRead:
    return HelpTopicRead(
        key=topic.key,
        title=topic.title,
        summary=topic.summary,
        body=topic.body,
        actions=topic.actions or [],
        form_fields=topic.form_fields or [],
    )


def _preview(body: str) -> str:
    """Primera línea con texto, sin saltos ni espacios de más, cortada a PREVIEW_LENGTH."""
    line = next((ln.strip() for ln in body.splitlines() if ln.strip()), "")
    line = " ".join(line.split())
    return line if len(line) <= PREVIEW_LENGTH else line[: PREVIEW_LENGTH - 1].rstrip() + "…"


def _answers(case: SupportCase) -> List[Answer]:
    return [Answer(**a) for a in (case.details or {}).get("answers", [])]


async def _messages(
    db: AsyncSession, case: SupportCase, requester_names: Dict[uuid.UUID, str]
) -> List[MessageRead]:
    rows = (await db.execute(
        select(SupportCaseMessage)
        .where(SupportCaseMessage.case_id == case.id)
        .order_by(SupportCaseMessage.created_at.asc())
    )).scalars().all()
    operator_names = await OperatorRepository(db).names_by_id(list({m.operator_id for m in rows if m.operator_id}))
    fallback = case.contact_name or case.contact_email
    return [
        MessageRead(
            id=m.id,
            author_kind=m.author_kind,
            author_name=(
                f"Soporte Nexus · {operator_names.get(m.operator_id, 'equipo')}"
                if m.author_kind == AuthorKind.SUPPORT
                else requester_names.get(m.author_user_id, fallback)
            ),
            body=m.body,
            created_at=m.created_at,
        )
        for m in rows
    ]


async def _active_topic(db: AsyncSession, key: str) -> Optional[HelpTopic]:
    return (await db.execute(
        select(HelpTopic).where(HelpTopic.key == key, HelpTopic.is_active.is_(True))
    )).scalar_one_or_none()


# ─────────────────────────────────────────────────────────────────────────────
# El tendero en su app
# ─────────────────────────────────────────────────────────────────────────────

class CaseService:
    """Con el contexto RLS del usuario (lo fija `get_current_user`)."""

    def __init__(self, db: AsyncSession, user: User):
        self.db = db
        self.user = user
        self.is_owner = bool(user.role and user.role.name == "OWNER")

    # ── Temas ──────────────────────────────────────────────────────────────

    async def topics(self) -> List[HelpTopicRead]:
        audiences = [TopicAudience.ALL] + ([TopicAudience.OWNER] if self.is_owner else [])
        rows = (await self.db.execute(
            select(HelpTopic)
            .where(HelpTopic.is_active.is_(True), HelpTopic.audience.in_(audiences))
            .order_by(HelpTopic.sort_order, HelpTopic.title)
        )).scalars().all()
        return [topic_read(t) for t in rows]

    # ── Casos ──────────────────────────────────────────────────────────────

    async def create(self, data: CaseCreate) -> CaseDetail:
        topic = await _active_topic(self.db, data.topic_key)
        allowed = {TopicAudience.ALL} | ({TopicAudience.OWNER} if self.is_owner else set())
        if topic is None or topic.audience not in allowed:
            raise _unprocessable("Ese tema no está disponible.")
        answers = validate_answers(topic, data.answers)
        now = datetime.now(timezone.utc)
        case = SupportCase(
            tenant_id=self.user.tenant_id,
            author_user_id=self.user.id,
            channel=CaseChannel.APP,
            topic_key=topic.key,
            topic_title=topic.title,
            details={"answers": answers},
            status=CaseStatus.WAITING_SUPPORT,
            contact_email=self.user.email,
            contact_name=self.user.full_name,
            last_message_at=now,
        )
        self.db.add(case)
        await self.db.flush()
        self.db.add(SupportCaseMessage(
            case_id=case.id,
            tenant_id=self.user.tenant_id,
            author_kind=AuthorKind.REQUESTER,
            author_user_id=self.user.id,
            body=data.description,
        ))
        await self._commit()
        return await self.detail(case.id)

    async def list(self) -> List[CaseSummary]:
        rows = (await self.db.execute(
            select(SupportCase)
            .where(*self._visible())
            .order_by(SupportCase.last_message_at.desc())
            .limit(100)
        )).scalars().all()
        names = await self._names([c.author_user_id for c in rows])
        return [self._summary(c, names) for c in rows]

    async def detail(self, case_id: uuid.UUID) -> CaseDetail:
        case = await self._case_or_404(case_id)
        if case.requester_unread and self._clears_unread(case):
            case.requester_unread = False
            await self._commit()
            case = await self._case_or_404(case_id)
        names = await self._names([case.author_user_id])
        summary = self._summary(case, names)
        message_names = await self._message_author_names(case)
        return CaseDetail(
            **summary.model_dump(),
            answers=_answers(case),
            messages=await _messages(self.db, case, message_names),
        )

    async def reply(self, case_id: uuid.UUID, body: str) -> CaseDetail:
        """Responder reabre un caso resuelto: le vuelve a tocar a soporte."""
        case = await self._case_or_404(case_id)
        now = datetime.now(timezone.utc)
        self.db.add(SupportCaseMessage(
            case_id=case.id,
            tenant_id=case.tenant_id,
            author_kind=AuthorKind.REQUESTER,
            author_user_id=self.user.id,
            body=body,
        ))
        case.status = CaseStatus.WAITING_SUPPORT
        case.last_message_at = now
        case.updated_at = now
        if self._clears_unread(case):
            case.requester_unread = False
        await self._commit()
        return await self.detail(case_id)

    async def resolve(self, case_id: uuid.UUID) -> CaseDetail:
        case = await self._case_or_404(case_id)
        if case.status != CaseStatus.RESOLVED:
            case.status = CaseStatus.RESOLVED
            case.updated_at = datetime.now(timezone.utc)
            await self._commit()
        return await self.detail(case_id)

    async def unread_count(self) -> int:
        """La insignia de ☰ · Soporte: respuestas de soporte sin abrir en mis casos."""
        rows = (await self.db.execute(
            select(SupportCase).where(*self._visible(), SupportCase.requester_unread.is_(True))
        )).scalars().all()
        return sum(1 for c in rows if self._clears_unread(c))

    # ── Apoyo ──────────────────────────────────────────────────────────────

    def _visible(self) -> list:
        conditions = [SupportCase.tenant_id == self.user.tenant_id]
        if not self.is_owner:
            conditions.append(SupportCase.author_user_id == self.user.id)
        return conditions

    def _clears_unread(self, case: SupportCase) -> bool:
        """Lo "no leído" es de quien escribió (o del dueño si esa persona ya no está)."""
        if case.author_user_id == self.user.id:
            return True
        return case.author_user_id is None and self.is_owner

    async def _case_or_404(self, case_id: uuid.UUID) -> SupportCase:
        case = (await self.db.execute(
            select(SupportCase)
            .where(SupportCase.id == case_id, *self._visible())
            .execution_options(populate_existing=True)
        )).scalar_one_or_none()
        if case is None:
            raise _not_found()
        return case

    async def _commit(self) -> None:
        # Tras el commit la conexión puede ser otra: se vuelve a fijar el contexto
        await self.db.commit()
        await set_tenant_context(self.db, self.user.tenant_id)

    async def _names(self, ids: Sequence[Optional[uuid.UUID]]) -> Dict[uuid.UUID, str]:
        wanted = [i for i in set(ids) if i]
        if not wanted:
            return {}
        rows = (await self.db.execute(select(User.id, User.full_name).where(User.id.in_(wanted)))).all()
        return {r[0]: r[1] for r in rows}

    async def _message_author_names(self, case: SupportCase) -> Dict[uuid.UUID, str]:
        ids = (await self.db.execute(
            select(SupportCaseMessage.author_user_id).where(SupportCaseMessage.case_id == case.id)
        )).scalars().all()
        return await self._names(list(ids))

    def _summary(self, case: SupportCase, names: Dict[uuid.UUID, str]) -> CaseSummary:
        return CaseSummary(
            id=case.id,
            number=case.number,
            topic_key=case.topic_key,
            topic_title=case.topic_title,
            status=case.status,
            unread=case.requester_unread and self._clears_unread(case),
            author_name=names.get(case.author_user_id) or case.contact_name,
            is_mine=case.author_user_id == self.user.id,
            created_at=case.created_at,
            last_message_at=case.last_message_at,
        )


# ─────────────────────────────────────────────────────────────────────────────
# Formulario sin sesión (P24)
# ─────────────────────────────────────────────────────────────────────────────

class PublicCaseService:
    def __init__(self, db: AsyncSession):
        self.db = db

    async def topics(self) -> List[HelpTopicRead]:
        rows = (await self.db.execute(
            select(HelpTopic)
            .where(HelpTopic.is_active.is_(True), HelpTopic.audience == TopicAudience.ANONYMOUS)
            .order_by(HelpTopic.sort_order, HelpTopic.title)
        )).scalars().all()
        return [topic_read(t) for t in rows]

    async def create(self, data: PublicCaseCreate, ip: Optional[str]) -> Optional[EmailMessage]:
        """
        Devuelve el acuse por enviar, o None si se descartó en silencio (bot,
        tope). La respuesta HTTP es la misma en todos los casos: no delata si el
        correo existe ni si alguien topó el límite.
        """
        if data.website:
            return None
        topic = await _active_topic(self.db, data.topic_key)
        if topic is None or topic.audience != TopicAudience.ANONYMOUS:
            raise _unprocessable("Ese tema no está disponible.")
        answers = validate_answers(topic, data.answers)

        contact = str(data.contact_email).strip().lower()
        now = datetime.now(timezone.utc)
        await self._bypass()
        recent_conditions = [SupportCase.contact_email == contact]
        if ip:
            recent_conditions.append(SupportCase.requester_ip == ip)
        recent = (await self.db.execute(
            select(func.count(SupportCase.id)).where(
                SupportCase.channel == CaseChannel.PUBLIC,
                SupportCase.created_at > now - timedelta(days=1),
                or_(*recent_conditions),
            )
        )).scalar_one()
        if recent >= PUBLIC_CASES_PER_DAY:
            return None

        # Para que soporte valide (P21): el comercio cuyo correo coincide. Sólo
        # lo ve el panel; el caso no entra a la app de esa tienda (quien escribe
        # sin sesión podría no ser su dueño).
        account = await UserRepository(self.db).get_by_email_global(str(data.account_email).strip())
        await self._bypass()
        case = SupportCase(
            tenant_id=None,
            channel=CaseChannel.PUBLIC,
            topic_key=topic.key,
            topic_title=topic.title,
            details={"answers": answers, "account_email": str(data.account_email)},
            status=CaseStatus.WAITING_SUPPORT,
            contact_email=contact,
            contact_name=(data.contact_name or "").strip() or None,
            claimed_store_name=data.store_name.strip(),
            suggested_tenant_id=account.tenant_id if account else None,
            requester_ip=ip,
            last_message_at=now,
        )
        self.db.add(case)
        await self.db.flush()
        self.db.add(SupportCaseMessage(case_id=case.id, author_kind=AuthorKind.REQUESTER, body=data.description))
        await self.db.commit()
        return public_case_received_email(contact, case.contact_name, case.number)

    async def _bypass(self) -> None:
        await self.db.execute(text("SELECT set_config('app.bypass_rls', 'on', true);"))


# ─────────────────────────────────────────────────────────────────────────────
# El panel (etapa 3 pone la pantalla; aquí la API)
# ─────────────────────────────────────────────────────────────────────────────

class CaseDeskService:
    def __init__(self, db: AsyncSession, operator: PlatformOperator, meta: RequestMeta = RequestMeta()):
        self.db = db
        self.operator = operator
        self.meta = meta
        self.audit = AuditRepository(db)

    async def _bypass(self) -> None:
        # Local a la transacción: se apaga sola en el commit
        await self.db.execute(text("SELECT set_config('app.bypass_rls', 'on', true);"))

    # ── Casos ──────────────────────────────────────────────────────────────

    async def list(
        self, status_filter: Optional[str], tenant_id: Optional[uuid.UUID], q: Optional[str], limit: int, offset: int,
    ) -> DeskCasePage:
        """Lo que espera a soporte primero (lo más antiguo arriba); luego lo demás, lo reciente arriba."""
        await self._bypass()
        conditions = []
        if status_filter:
            conditions.append(SupportCase.status == status_filter)
        if tenant_id:
            conditions.append(or_(SupportCase.tenant_id == tenant_id, SupportCase.suggested_tenant_id == tenant_id))
        if q:
            term = q.strip()
            like = f"%{term}%"
            matches = [
                SupportCase.contact_email.ilike(like),
                SupportCase.claimed_store_name.ilike(like),
                SupportCase.topic_title.ilike(like),
            ]
            if term.isdigit():
                matches.append(SupportCase.number == int(term))
            conditions.append(or_(*matches))
        waiting = SupportCase.status == CaseStatus.WAITING_SUPPORT
        total = (await self.db.execute(select(func.count(SupportCase.id)).where(*conditions))).scalar_one()
        rows = (await self.db.execute(
            select(SupportCase)
            .where(*conditions)
            .order_by(
                (SupportCase.status != CaseStatus.WAITING_SUPPORT),
                sql_case((waiting, SupportCase.last_message_at)).asc(),
                SupportCase.last_message_at.desc(),
            )
            .limit(limit)
            .offset(offset)
        )).scalars().all()
        stores = await self._store_names(rows)
        previews = await self._last_messages([c.id for c in rows])
        return DeskCasePage(items=[self._summary(c, stores, previews) for c in rows], total=int(total))

    async def waiting(self) -> List[SupportCase]:
        """Para el feed: casos que esperan respuesta de soporte."""
        await self._bypass()
        return list((await self.db.execute(
            select(SupportCase)
            .where(SupportCase.status == CaseStatus.WAITING_SUPPORT)
            .order_by(SupportCase.last_message_at.asc())
        )).scalars().all())

    async def created_between(self, since: datetime, until: datetime) -> List[SupportCase]:
        await self._bypass()
        return list((await self.db.execute(
            select(SupportCase).where(SupportCase.created_at >= since, SupportCase.created_at < until)
        )).scalars().all())

    async def detail(self, case_id: uuid.UUID) -> DeskCaseDetail:
        await self._bypass()
        case = await self._case_or_404(case_id)
        stores = await self._store_names([case])
        ids = (await self.db.execute(
            select(SupportCaseMessage.author_user_id).where(SupportCaseMessage.case_id == case.id)
        )).scalars().all()
        wanted = [i for i in set(ids) if i]
        names = {}
        if wanted:
            names = {r[0]: r[1] for r in (await self.db.execute(
                select(User.id, User.full_name).where(User.id.in_(wanted))
            )).all()}
        return DeskCaseDetail(
            **self._summary(case, stores, await self._last_messages([case.id])).model_dump(),
            answers=_answers(case),
            messages=await _messages(self.db, case, names),
            store=await self._store_context(case),
        )

    async def reply(self, case_id: uuid.UUID, data: DeskReply) -> Tuple[DeskCaseDetail, EmailMessage]:
        await self._bypass()
        case = await self._case_or_404(case_id)
        now = datetime.now(timezone.utc)
        self.db.add(SupportCaseMessage(
            case_id=case.id,
            tenant_id=case.tenant_id,
            author_kind=AuthorKind.SUPPORT,
            operator_id=self.operator.id,
            body=data.body,
        ))
        previous = case.status
        case.status = CaseStatus.RESOLVED if data.resolve else CaseStatus.ANSWERED
        case.requester_unread = True
        case.last_message_at = now
        case.updated_at = now
        await self.audit.append(
            AuditAction.CASE_REPLIED,
            operator_id=self.operator.id,
            target_tenant_id=case.tenant_id or case.suggested_tenant_id,
            target_type="case",
            target_id=str(case.id),
            details={"caso": case.number, "de": previous, "a": case.status, "canal": case.channel},
            meta=self.meta,
        )
        await self.db.commit()
        email = case_reply_email(
            case.contact_email, case.contact_name, case.number, case.topic_title, data.body,
            in_app=case.channel == CaseChannel.APP,
        )
        return await self.detail(case_id), email

    async def set_status(self, case_id: uuid.UUID, new_status: str) -> DeskCaseDetail:
        await self._bypass()
        case = await self._case_or_404(case_id)
        if case.status == new_status:
            raise _unprocessable("El caso ya está en ese estado.")
        previous = case.status
        case.status = new_status
        case.updated_at = datetime.now(timezone.utc)
        await self.audit.append(
            AuditAction.CASE_STATUS_CHANGED,
            operator_id=self.operator.id,
            target_tenant_id=case.tenant_id or case.suggested_tenant_id,
            target_type="case",
            target_id=str(case.id),
            details={"caso": case.number, "de": previous, "a": new_status},
            meta=self.meta,
        )
        await self.db.commit()
        return await self.detail(case_id)

    # ── Temas de ayuda (contenido editable) ────────────────────────────────

    async def help_topics(self) -> List[HelpTopicAdmin]:
        rows = (await self.db.execute(select(HelpTopic).order_by(HelpTopic.sort_order, HelpTopic.title))).scalars().all()
        return [self._topic_admin(t) for t in rows]

    async def upsert_help_topic(self, key: str, data: HelpTopicUpsert) -> HelpTopicAdmin:
        topic = (await self.db.execute(select(HelpTopic).where(HelpTopic.key == key))).scalar_one_or_none()
        created = topic is None
        if created:
            topic = HelpTopic(key=key)
            self.db.add(topic)
        topic.title = data.title.strip()
        topic.summary = data.summary.strip()
        topic.body = data.body.strip()
        topic.actions = [a.model_dump() for a in data.actions]
        topic.form_fields = [f.model_dump() for f in data.form_fields]
        topic.audience = data.audience
        topic.sort_order = data.sort_order
        topic.is_active = data.is_active
        topic.updated_at = datetime.now(timezone.utc)
        topic.updated_by = self.operator.id
        await self.db.flush()
        await self.audit.append(
            AuditAction.HELP_TOPIC_UPDATED,
            operator_id=self.operator.id,
            target_type="help_topic",
            target_id=key,
            reason=data.reason.strip(),
            details={"tema": topic.title, "nuevo": created, "activo": topic.is_active},
            meta=self.meta,
        )
        await self.db.commit()
        return self._topic_admin(topic)

    # ── Apoyo ──────────────────────────────────────────────────────────────

    async def _case_or_404(self, case_id: uuid.UUID) -> SupportCase:
        case = (await self.db.execute(
            select(SupportCase).where(SupportCase.id == case_id).execution_options(populate_existing=True)
        )).scalar_one_or_none()
        if case is None:
            raise _not_found()
        return case

    async def _last_messages(self, case_ids: Sequence[uuid.UUID]) -> Dict[uuid.UUID, Tuple[str, bool]]:
        """Último mensaje de cada caso (una consulta, `DISTINCT ON`): su primera línea y si es de soporte."""
        if not case_ids:
            return {}
        rows = (await self.db.execute(
            select(SupportCaseMessage.case_id, SupportCaseMessage.body, SupportCaseMessage.author_kind)
            .where(SupportCaseMessage.case_id.in_(list(case_ids)))
            .distinct(SupportCaseMessage.case_id)
            .order_by(SupportCaseMessage.case_id, SupportCaseMessage.created_at.desc())
        )).all()
        return {r[0]: (_preview(r[1]), r[2] == AuthorKind.SUPPORT) for r in rows}

    async def _store_context(self, case: SupportCase) -> Optional[DeskStoreContext]:
        """Metadatos de la tienda del caso (o la sugerida, sin sesión). Leerlos aquí no registra
        una "tienda vista" en la bitácora: eso queda para la ficha (decisión 3 de la Fase 1)."""
        target = case.tenant_id or case.suggested_tenant_id
        if target is None:
            return None
        tenant = (await self.db.execute(select(Tenant).where(Tenant.id == target))).scalar_one_or_none()
        if tenant is None:
            return None
        return DeskStoreContext(
            tenant_id=tenant.id,
            name=tenant.name,
            status=getattr(tenant.status, "value", tenant.status),
            plan=getattr(tenant.plan_id, "value", tenant.plan_id),
            paid_until=tenant.paid_until,
            lock_reason=getattr(tenant.lock_reason, "value", tenant.lock_reason),
            suggested=case.tenant_id is None,
        )

    async def _store_names(self, cases: Sequence[SupportCase]) -> Dict[uuid.UUID, str]:
        ids = {c.tenant_id for c in cases if c.tenant_id} | {c.suggested_tenant_id for c in cases if c.suggested_tenant_id}
        if not ids:
            return {}
        rows = (await self.db.execute(select(Tenant.id, Tenant.name).where(Tenant.id.in_(list(ids))))).all()
        return {r[0]: r[1] for r in rows}

    @staticmethod
    def _summary(
        case: SupportCase,
        stores: Dict[uuid.UUID, str],
        previews: Optional[Dict[uuid.UUID, Tuple[str, bool]]] = None,
    ) -> DeskCaseSummary:
        preview = (previews or {}).get(case.id)
        return DeskCaseSummary(
            id=case.id,
            number=case.number,
            channel=case.channel,
            tenant_id=case.tenant_id,
            tenant_name=stores.get(case.tenant_id) if case.tenant_id else None,
            topic_key=case.topic_key,
            topic_title=case.topic_title,
            status=case.status,
            contact_email=case.contact_email,
            contact_name=case.contact_name,
            claimed_store_name=case.claimed_store_name,
            suggested_tenant_id=case.suggested_tenant_id,
            suggested_tenant_name=stores.get(case.suggested_tenant_id) if case.suggested_tenant_id else None,
            created_at=case.created_at,
            last_message_at=case.last_message_at,
            last_message_preview=preview[0] if preview else None,
            last_message_by_support=preview[1] if preview else None,
        )

    @staticmethod
    def _topic_admin(topic: HelpTopic) -> HelpTopicAdmin:
        return HelpTopicAdmin(
            **topic_read(topic).model_dump(),
            audience=topic.audience,
            sort_order=topic.sort_order,
            is_active=topic.is_active,
            updated_at=topic.updated_at,
        )
