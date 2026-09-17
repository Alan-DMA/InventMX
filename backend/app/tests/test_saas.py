"""Tests del módulo SaaS (Tarea 14.2): suscripción del comerciante, aviso de
pago manual, panel de fundadores y máquina de estados de morosidad.

Mismo patrón que test_sales.py: datos propios sembrados con el superusuario,
cliente ASGI y tokens firmados directamente. Usa los planes del seed
(00000000-…-0001/0002/0003)."""
import pytest
from httpx import AsyncClient, ASGITransport
from sqlalchemy import select, text
from decimal import Decimal
from datetime import datetime, timedelta

from app.main import app
from app.core.config import settings
from sqlalchemy.ext.asyncio import create_async_engine, async_sessionmaker, AsyncSession
from sqlalchemy.pool import NullPool
from app.core.security import get_password_hash, create_access_token
from app.models.models import (
    Tenant, User, Role, Permission, role_permissions, Plan,
    SubscriptionInvoice, SubscriptionPaymentValidation,
)

pytestmark = pytest.mark.asyncio


@pytest.fixture(scope="module")
def anyio_backend():
    return "asyncio"


superuser_url = settings.SUPERUSER_DATABASE_URL
superuser_engine = create_async_engine(superuser_url, echo=False, poolclass=NullPool)
SuperuserSessionLocal = async_sessionmaker(bind=superuser_engine, class_=AsyncSession, expire_on_commit=False)

TENANT_SHOP = "b0000000-0000-0000-0000-0000000000bb"   # comercio de prueba
TENANT_NEXUS = "b0000000-0000-0000-0000-0000000000cc"  # tenant de los fundadores
ROLE_OWNER_SHOP = "d0000000-0000-0000-0000-0000000000bb"
ROLE_CASHIER_SHOP = "d0000000-0000-0000-0000-0000000000bd"
ROLE_OWNER_NEXUS = "d0000000-0000-0000-0000-0000000000cc"
USER_OWNER = "e0000000-0000-0000-0000-0000000000bb"
USER_CASHIER = "e0000000-0000-0000-0000-0000000000bd"
USER_FOUNDER = "e0000000-0000-0000-0000-0000000000cc"
PLAN_EMPRENDEDOR = "00000000-0000-0000-0000-000000000001"
PLAN_COMERCIO = "00000000-0000-0000-0000-000000000002"


async def _upsert(session, model, **values):
    existing = (await session.execute(select(model).where(model.id == values["id"]))).scalars().first()
    if existing is None:
        session.add(model(**values))
    else:
        for k, v in values.items():
            setattr(existing, k, v)
    await session.commit()


async def _ensure_plans(session):
    for pid, name, price in [
        (PLAN_EMPRENDEDOR, "Emprendedor", Decimal("199.00")),
        (PLAN_COMERCIO, "Comercio", Decimal("399.00")),
    ]:
        existing = (await session.execute(select(Plan).where(Plan.id == pid))).scalars().first()
        if existing is None:
            session.add(Plan(id=pid, name=name, price=price, max_users=5, max_warehouses=3))
    await session.commit()


async def _ensure_permission(session, name):
    perm = (await session.execute(select(Permission).where(Permission.name == name))).scalars().first()
    if perm is None:
        perm = Permission(name=name, description=name)
        session.add(perm)
        await session.commit()
    return perm


async def _grant(session, role_id, perm_names):
    await session.execute(role_permissions.delete().where(role_permissions.c.role_id == role_id))
    rows = []
    for n in perm_names:
        perm = await _ensure_permission(session, n)
        rows.append({"role_id": role_id, "permission_id": perm.id})
    if rows:
        await session.execute(role_permissions.insert(), rows)
    await session.commit()


async def setup_saas_test_data():
    async with SuperuserSessionLocal() as session:
        await session.execute(text("SELECT set_config('app.current_tenant', '', false)"))
        await _ensure_plans(session)

        # Limpieza de corridas previas
        for tid in (TENANT_SHOP, TENANT_NEXUS):
            await session.execute(text(f"DELETE FROM subscription_payment_validations WHERE tenant_id = '{tid}'"))
            await session.execute(text(f"DELETE FROM subscription_invoices WHERE tenant_id = '{tid}'"))
        await session.commit()

        await _upsert(session, Tenant, id=TENANT_SHOP, name="Abarrotes Prueba SaaS", code="SAAS01",
                      plan_id=PLAN_COMERCIO, subscription_status="ACTIVE",
                      created_at=datetime.utcnow() - timedelta(days=5))
        await _upsert(session, Tenant, id=TENANT_NEXUS, name="Nexus HQ", code="NEXUS0",
                      plan_id=PLAN_COMERCIO, subscription_status="ACTIVE")

        await _upsert(session, Role, id=ROLE_OWNER_SHOP, tenant_id=TENANT_SHOP, name="TENANT_OWNER")
        await _upsert(session, Role, id=ROLE_CASHIER_SHOP, tenant_id=TENANT_SHOP, name="CASHIER")
        await _upsert(session, Role, id=ROLE_OWNER_NEXUS, tenant_id=TENANT_NEXUS, name="TENANT_OWNER")

        # El dueño de la tiendita NO tiene saas.manage; el fundador sí (D7)
        await _grant(session, ROLE_OWNER_SHOP, ["ventas.ver"])
        await _grant(session, ROLE_CASHIER_SHOP, ["ventas.ver"])
        await _grant(session, ROLE_OWNER_NEXUS, ["saas.manage"])

        await _upsert(session, User, id=USER_OWNER, tenant_id=TENANT_SHOP, username="owner_saas",
                      email="owner_saas@test.com", password_hash=get_password_hash("password123"),
                      role_id=ROLE_OWNER_SHOP, is_active=True)
        await _upsert(session, User, id=USER_CASHIER, tenant_id=TENANT_SHOP, username="cashier_saas",
                      email="cashier_saas@test.com", password_hash=get_password_hash("password123"),
                      role_id=ROLE_CASHIER_SHOP, is_active=True)
        await _upsert(session, User, id=USER_FOUNDER, tenant_id=TENANT_NEXUS, username="founder_saas",
                      email="founder_saas@test.com", password_hash=get_password_hash("password123"),
                      role_id=ROLE_OWNER_NEXUS, is_active=True)


def _auth(user_id):
    return {"Authorization": f"Bearer {create_access_token(subject=user_id)}"}


async def _set_status(tenant_id, status_value):
    async with SuperuserSessionLocal() as session:
        await session.execute(text("SELECT set_config('app.current_tenant', '', false)"))
        await session.execute(
            text("UPDATE tenants SET subscription_status = :s WHERE id = :id"),
            {"s": status_value, "id": tenant_id},
        )
        await session.commit()


async def _set_due_date(tenant_id, due):
    async with SuperuserSessionLocal() as session:
        await session.execute(text("SELECT set_config('app.current_tenant', '', false)"))
        await session.execute(
            text("UPDATE subscription_invoices SET due_date = :d WHERE tenant_id = :id AND status = 'PENDIENTE'"),
            {"d": due, "id": tenant_id},
        )
        await session.commit()


async def test_merchant_subscription_lazy_invoice_and_instructions():
    await setup_saas_test_data()
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        me = await ac.get("/api/v1/saas/me", headers=_auth(USER_OWNER))
        assert me.status_code == 200
        assert me.json()["is_founder"] is False
        assert me.json()["tenant"]["code"] == "SAAS01"

        res = await ac.get("/api/v1/saas/subscription", headers=_auth(USER_OWNER))
        assert res.status_code == 200
        data = res.json()
        assert data["status"] == "ACTIVE"
        assert data["plan"]["name"] == "Comercio"
        # Facturación perezosa: primera factura al plan actual, vence 30 días tras el alta
        inv = data["pending_invoice"]
        assert inv is not None and inv["status"] == "PENDIENTE"
        plan_price = Decimal(str(data["plan"]["price"]))
        assert Decimal(str(inv["amount"])) == plan_price
        assert data["days_overdue"] == 0
        assert data["payment_instructions"]["concept"] == "SAAS01"
        assert Decimal(str(data["payment_instructions"]["amount"])) == plan_price
        assert data["oxxo"] is None

        # Segunda lectura no duplica la factura
        again = await ac.get("/api/v1/saas/subscription", headers=_auth(USER_OWNER))
        assert again.json()["pending_invoice"]["id"] == inv["id"]
        invoices = await ac.get("/api/v1/saas/invoices", headers=_auth(USER_OWNER))
        assert len(invoices.json()) == 1


async def test_change_plan_recalculates_pending_invoice_and_requires_owner():
    await setup_saas_test_data()
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        await ac.get("/api/v1/saas/subscription", headers=_auth(USER_OWNER))

        denied = await ac.post("/api/v1/saas/subscription/change-plan",
                               json={"plan_id": PLAN_EMPRENDEDOR}, headers=_auth(USER_CASHIER))
        assert denied.status_code == 403

        res = await ac.post("/api/v1/saas/subscription/change-plan",
                            json={"plan_id": PLAN_EMPRENDEDOR}, headers=_auth(USER_OWNER))
        assert res.status_code == 200
        assert res.json()["plan"]["name"] == "Emprendedor"
        assert Decimal(str(res.json()["pending_invoice"]["amount"])) == Decimal(str(res.json()["plan"]["price"]))


async def test_report_payment_then_founder_approves_and_reactivates():
    await setup_saas_test_data()
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        sub = (await ac.get("/api/v1/saas/subscription", headers=_auth(USER_OWNER))).json()
        invoice_id = sub["pending_invoice"]["id"]

        # Comercio bloqueado por morosidad: debe poder reportar el pago igual
        await _set_status(TENANT_SHOP, "HARD_LOCK")

        rep = await ac.post("/api/v1/saas/payment-validations", headers=_auth(USER_OWNER),
                            json={"invoice_id": invoice_id, "payment_method": "SPEI",
                                  "reference_number": "RAST123456"})
        assert rep.status_code == 201
        validation_id = rep.json()["id"]
        assert rep.json()["status"] == "PENDIENTE"

        dup = await ac.post("/api/v1/saas/payment-validations", headers=_auth(USER_OWNER),
                            json={"invoice_id": invoice_id, "payment_method": "SPEI",
                                  "reference_number": "OTRA"})
        assert dup.status_code == 422

        sub2 = (await ac.get("/api/v1/saas/subscription", headers=_auth(USER_OWNER))).json()
        assert sub2["pending_validation"]["id"] == validation_id
        assert sub2["status"] == "HARD_LOCK"

        # El dueño de la tiendita no entra al panel
        forbidden = await ac.get("/api/v1/saas/admin/metrics", headers=_auth(USER_OWNER))
        assert forbidden.status_code == 403

        inbox = await ac.get("/api/v1/saas/admin/payment-validations", headers=_auth(USER_FOUNDER))
        assert inbox.status_code == 200
        ids = [v["id"] for v in inbox.json()]
        assert validation_id in ids
        row = next(v for v in inbox.json() if v["id"] == validation_id)
        assert row["tenant_code"] == "SAAS01"
        assert Decimal(str(row["invoice_amount"])) == Decimal(str(sub["pending_invoice"]["amount"]))

        ok = await ac.post(f"/api/v1/saas/admin/payment-validations/{validation_id}/approve",
                           headers=_auth(USER_FOUNDER), json={"validation_notes": "Visto en el banco"})
        assert ok.status_code == 200
        assert ok.json()["validation"]["status"] == "APROBADA"
        assert ok.json()["invoice"]["status"] == "PAGADA"
        assert ok.json()["tenant"]["subscription_status"] == "ACTIVE"

        twice = await ac.post(f"/api/v1/saas/admin/payment-validations/{validation_id}/approve",
                              headers=_auth(USER_FOUNDER), json={})
        assert twice.status_code == 422

        # Siguiente periodo: nueva factura pendiente un mes después de la pagada
        sub3 = (await ac.get("/api/v1/saas/subscription", headers=_auth(USER_OWNER))).json()
        assert sub3["status"] == "ACTIVE"
        assert sub3["pending_invoice"]["id"] != invoice_id
        assert sub3["pending_validation"] is None
        paid_due = datetime.fromisoformat(sub["pending_invoice"]["due_date"])
        next_due = datetime.fromisoformat(sub3["pending_invoice"]["due_date"])
        assert (next_due.year, next_due.month) == ((paid_due.year + (paid_due.month // 12)), paid_due.month % 12 + 1)
        assert next_due.day == min(paid_due.day, 28) or next_due.day == paid_due.day


async def test_reject_requires_notes_and_keeps_invoice_pending():
    await setup_saas_test_data()
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        sub = (await ac.get("/api/v1/saas/subscription", headers=_auth(USER_OWNER))).json()
        invoice_id = sub["pending_invoice"]["id"]
        rep = await ac.post("/api/v1/saas/payment-validations", headers=_auth(USER_OWNER),
                            json={"invoice_id": invoice_id, "payment_method": "OXXO",
                                  "reference_number": "98765432109876"})
        vid = rep.json()["id"]

        no_notes = await ac.post(f"/api/v1/saas/admin/payment-validations/{vid}/reject",
                                 headers=_auth(USER_FOUNDER), json={})
        assert no_notes.status_code == 422

        rej = await ac.post(f"/api/v1/saas/admin/payment-validations/{vid}/reject",
                            headers=_auth(USER_FOUNDER), json={"validation_notes": "No aparece en el banco"})
        assert rej.status_code == 200
        assert rej.json()["validation"]["status"] == "RECHAZADA"
        assert rej.json()["invoice"]["status"] == "PENDIENTE"

        # Tras el rechazo puede volver a avisar
        again = await ac.post("/api/v1/saas/payment-validations", headers=_auth(USER_OWNER),
                              json={"invoice_id": invoice_id, "payment_method": "SPEI",
                                    "reference_number": "RAST999"})
        assert again.status_code == 201


async def test_lifecycle_escalates_and_founder_actions():
    await setup_saas_test_data()
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        await ac.get("/api/v1/saas/subscription", headers=_auth(USER_OWNER))

        # Vencida hace 3 días → SOFT_LOCK al leer
        await _set_due_date(TENANT_SHOP, datetime.utcnow() - timedelta(days=3))
        sub = (await ac.get("/api/v1/saas/subscription", headers=_auth(USER_OWNER))).json()
        assert sub["status"] == "SOFT_LOCK"
        assert sub["days_overdue"] == 3

        # Vencida hace 12 días → HARD_LOCK vía el "cron" de fundadores
        await _set_due_date(TENANT_SHOP, datetime.utcnow() - timedelta(days=12))
        run = await ac.post("/api/v1/saas/admin/lifecycle/run", headers=_auth(USER_FOUNDER))
        assert run.status_code == 200
        assert TENANT_SHOP in run.json()["to_hard_lock"]

        tenants = (await ac.get("/api/v1/saas/admin/tenants", params={"q": "SAAS01"},
                                headers=_auth(USER_FOUNDER))).json()
        assert len(tenants) == 1 and tenants[0]["subscription_status"] == "HARD_LOCK"
        assert tenants[0]["days_overdue"] == 12
        assert tenants[0]["owner_email"] == "owner_saas@test.com"

        metrics = (await ac.get("/api/v1/saas/admin/metrics", headers=_auth(USER_FOUNDER))).json()
        assert metrics["tenants_hard_lock"] >= 1
        assert metrics["tenants_total"] >= 2

        # Reactivación rápida: vuelve a ACTIVE y corre el vencimiento 7 días
        react = await ac.post(f"/api/v1/saas/admin/tenants/{TENANT_SHOP}/status",
                              headers=_auth(USER_FOUNDER), json={"status": "ACTIVE"})
        assert react.status_code == 200
        assert react.json()["subscription_status"] == "ACTIVE"
        assert react.json()["days_overdue"] == 0

        # Extender plazo
        ext = await ac.post(f"/api/v1/saas/admin/tenants/{TENANT_SHOP}/extend-due",
                            headers=_auth(USER_FOUNDER), json={"days": 10})
        assert ext.status_code == 200
        due = datetime.fromisoformat(ext.json()["due_date"])
        assert due > datetime.utcnow() + timedelta(days=16)

        # Suspensión manual
        susp = await ac.post(f"/api/v1/saas/admin/tenants/{TENANT_SHOP}/status",
                             headers=_auth(USER_FOUNDER), json={"status": "SOFT_LOCK"})
        assert susp.json()["subscription_status"] == "SOFT_LOCK"
        # MRR excluye al suspendido
        m2 = (await ac.get("/api/v1/saas/admin/metrics", headers=_auth(USER_FOUNDER))).json()
        assert m2["tenants_soft_lock"] >= 1
