import uuid
from typing import Optional, List
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload
from app.modules.auth_tenancy.domain.user import User
from app.modules.auth_tenancy.domain.role import Role


class UserRepository:
    def __init__(self, db: AsyncSession):
        self.db = db

    async def get_by_id(self, user_id: uuid.UUID) -> Optional[User]:
        stmt = (
            select(User)
            .where(User.id == user_id)
            .options(selectinload(User.role).selectinload(Role.permissions), selectinload(User.tenant))
        )
        result = await self.db.execute(stmt)
        return result.scalar_one_or_none()

    async def get_by_email_and_tenant(self, email: str, tenant_id: uuid.UUID) -> Optional[User]:
        stmt = (
            select(User)
            .where(User.email == email, User.tenant_id == tenant_id)
            .options(selectinload(User.role).selectinload(Role.permissions), selectinload(User.tenant))
        )
        result = await self.db.execute(stmt)
        return result.scalar_one_or_none()

    async def get_by_email_global(self, email: str) -> Optional[User]:
        stmt = (
            select(User)
            .where(User.email == email)
            .options(selectinload(User.role).selectinload(Role.permissions), selectinload(User.tenant))
        )
        result = await self.db.execute(stmt)
        return result.scalar_one_or_none()

    async def create(
        self,
        tenant_id: uuid.UUID,
        email: str,
        hashed_password: str,
        full_name: str,
        role_id: uuid.UUID,
        is_active: bool = True,
    ) -> User:
        user = User(
            id=uuid.uuid4(),
            tenant_id=tenant_id,
            email=email,
            hashed_password=hashed_password,
            full_name=full_name,
            role_id=role_id,
            is_active=is_active,
        )
        self.db.add(user)
        await self.db.flush()
        return user
