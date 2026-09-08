import uuid
import pytest
from sqlalchemy import select, update, delete, text
from sqlalchemy.ext.asyncio import AsyncSession
from app.modules.auth_tenancy.domain.user import User


@pytest.mark.asyncio
async def test_tenant_a_can_only_see_own_users(
    db_session: AsyncSession, setup_tenants_and_users: dict
):
    """
    HU-01 / CU-01:
    Verifica que al establecer el contexto en Tenant A, la consulta SELECT
    retorna exclusivamente los usuarios pertenecientes al Tenant A.
    """
    tenant_a = setup_tenants_and_users["tenant_a"]
    user_a = setup_tenants_and_users["user_a"]

    # Inyectar contexto de Tenant A
    await db_session.execute(text(f"SET app.current_tenant = '{tenant_a.id}'"))

    # Ejecutar consulta
    stmt = select(User)
    result = await db_session.execute(stmt)
    users = result.scalars().all()

    # Aserciones de aislamiento
    user_ids = [u.id for u in users]
    assert user_a.id in user_ids
    assert all(u.tenant_id == tenant_a.id for u in users)


@pytest.mark.asyncio
async def test_tenant_b_cannot_see_tenant_a_users(
    db_session: AsyncSession, setup_tenants_and_users: dict
):
    """
    HU-01 / CU-01:
    Verifica que al establecer el contexto en Tenant B, los usuarios de Tenant A
    son invisibles para PostgreSQL (0% fuga de datos).
    """
    tenant_b = setup_tenants_and_users["tenant_b"]
    user_a = setup_tenants_and_users["user_a"]
    user_b = setup_tenants_and_users["user_b"]

    # Inyectar contexto de Tenant B
    await db_session.execute(text(f"SET app.current_tenant = '{tenant_b.id}'"))

    stmt = select(User)
    result = await db_session.execute(stmt)
    users = result.scalars().all()

    user_ids = [u.id for u in users]
    assert user_b.id in user_ids
    assert user_a.id not in user_ids


@pytest.mark.asyncio
async def test_no_tenant_context_returns_empty_set(
    db_session: AsyncSession, setup_tenants_and_users: dict
):
    """
    HU-01 / CU-01:
    Verifica que si no se provee un contexto app.current_tenant,
    la política RLS deniega el acceso y retorna 0 filas.
    """
    await db_session.execute(text("RESET app.current_tenant"))

    stmt = select(User)
    result = await db_session.execute(stmt)
    users = result.scalars().all()

    assert len(users) == 0


@pytest.mark.asyncio
async def test_cross_tenant_update_prevented_by_rls(
    db_session: AsyncSession, setup_tenants_and_users: dict
):
    """
    HU-01 / CU-01:
    Verifica que un intento malicioso o erróneo de actualizar un registro de Tenant B
    desde la sesión de Tenant A no afecta ninguna fila (0 filas actualizadas).
    """
    tenant_a = setup_tenants_and_users["tenant_a"]
    user_b = setup_tenants_and_users["user_b"]

    # Conectar como Tenant A
    await db_session.execute(text(f"SET app.current_tenant = '{tenant_a.id}'"))

    # Intentar modificar el usuario de Tenant B
    stmt = (
        update(User)
        .where(User.id == user_b.id)
        .values(full_name="Hacked Name")
    )
    result = await db_session.execute(stmt)
    await db_session.commit()

    # RLS oculta la fila del UPDATE; rowcount debe ser 0
    assert result.rowcount == 0


@pytest.mark.asyncio
async def test_cross_tenant_delete_prevented_by_rls(
    db_session: AsyncSession, setup_tenants_and_users: dict
):
    """
    HU-01 / CU-01:
    Verifica que un intento de eliminar un usuario de Tenant B desde la sesión de Tenant A
    es ignorado por la política RLS (0 filas eliminadas).
    """
    tenant_a = setup_tenants_and_users["tenant_a"]
    user_b = setup_tenants_and_users["user_b"]

    # Conectar como Tenant A
    await db_session.execute(text(f"SET app.current_tenant = '{tenant_a.id}'"))

    # Intentar borrar el usuario de Tenant B
    stmt = delete(User).where(User.id == user_b.id)
    result = await db_session.execute(stmt)
    await db_session.commit()

    assert result.rowcount == 0
