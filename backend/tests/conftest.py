import asyncio
import uuid
import pytest
import pytest_asyncio
from httpx import AsyncClient, ASGITransport
from sqlalchemy import text, pool
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine

from app.core.config.settings import settings
from app.core.database.base import Base
from app.core.database.session import set_tenant_context
from app.main import app
from app.modules.auth_tenancy.domain.tenant import Tenant, TenantPlan, TenantStatus
from app.modules.auth_tenancy.domain.role import Role
from app.modules.auth_tenancy.domain.user import User


@pytest_asyncio.fixture
async def test_engine():
    """Motor asíncrono con NullPool para evitar colisiones de conexiones concurrentes."""
    engine = create_async_engine(
        settings.DATABASE_URL,
        echo=False,
        poolclass=pool.NullPool,
        connect_args={
            "server_settings": {
                "search_path": "inventmx,public"
            }
        },
    )
    yield engine
    await engine.dispose()


@pytest_asyncio.fixture
async def db_session(test_engine) -> AsyncSession:
    """Provee una sesión asíncrona aislada para cada prueba."""
    async_session = async_sessionmaker(
        bind=test_engine,
        class_=AsyncSession,
        expire_on_commit=False,
        autocommit=False,
        autoflush=False,
    )
    async with async_session() as session:
        yield session
        await session.rollback()


@pytest_asyncio.fixture
async def client() -> AsyncClient:
    """Cliente HTTP asíncrono para probar endpoints FastAPI."""
    async with AsyncClient(
        transport=ASGITransport(app=app),
        base_url="http://testserver",
    ) as ac:
        yield ac


@pytest_asyncio.fixture
async def setup_tenants_and_users(db_session: AsyncSession):
    """
    Crea dos comercios (Tenant A y Tenant B) con usuarios respectivos
    para validar el aislamiento RLS estricto.
    """
    tenant_a_id = uuid.uuid4()
    tenant_b_id = uuid.uuid4()
    owner_role_id = uuid.UUID("a0000000-0000-0000-0000-000000000001")

    # 1. Crear los dos tenants
    tenant_a = Tenant(
        id=tenant_a_id,
        name="Abarrotes Don Pepe (Tenant A)",
        slug=f"abarrotes-pepe-{uuid.uuid4().hex[:6]}",
        plan_id=TenantPlan.EMPRENDEDOR,
        status=TenantStatus.ACTIVE,
    )
    tenant_b = Tenant(
        id=tenant_b_id,
        name="Farmacia La Paz (Tenant B)",
        slug=f"farmacia-la-paz-{uuid.uuid4().hex[:6]}",
        plan_id=TenantPlan.COMERCIO,
        status=TenantStatus.ACTIVE,
    )

    db_session.add(tenant_a)
    db_session.add(tenant_b)
    await db_session.flush()

    # 2. Insertar Usuario de Tenant A bajo el contexto de Tenant A
    await set_tenant_context(db_session, tenant_a_id)
    user_a = User(
        id=uuid.uuid4(),
        tenant_id=tenant_a_id,
        email=f"pepe_{uuid.uuid4().hex[:4]}@donpepe.mx",
        hashed_password="hashed_secret_a",
        full_name="Don Pepe",
        role_id=owner_role_id,
        is_active=True,
    )
    db_session.add(user_a)
    await db_session.flush()

    # 3. Insertar Usuario de Tenant B bajo el contexto de Tenant B
    await set_tenant_context(db_session, tenant_b_id)
    user_b = User(
        id=uuid.uuid4(),
        tenant_id=tenant_b_id,
        email=f"carlos_{uuid.uuid4().hex[:4]}@farmacialapaz.mx",
        hashed_password="hashed_secret_b",
        full_name="Carlos Ruiz",
        role_id=owner_role_id,
        is_active=True,
    )
    db_session.add(user_b)
    await db_session.flush()

    # Resetear contexto a vacío
    await db_session.execute(text("RESET app.current_tenant"))

    return {
        "tenant_a": tenant_a,
        "tenant_b": tenant_b,
        "user_a": user_a,
        "user_b": user_b,
    }
