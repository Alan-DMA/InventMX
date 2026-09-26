"""
Personalización de roles por comercio — Fase B de permisos (Sep 2026).

Los cuatro roles del sistema (`tenant_id IS NULL`) son la plantilla y nadie los
modifica. En cuanto el dueño de un comercio cambia un permiso, su tienda se
queda con **su propia copia** de ese rol (clone-on-write) y los empleados que lo
tenían pasan a ella; "restablecer" borra la copia y los devuelve al estándar.

Reglas, acordadas con Eduardo el Sep 23:
- sólo el dueño reparte permisos (`require_owner` en la capa de API);
- el rol OWNER no se edita ni se clona: el servidor le deja pasar todas las
  puertas por definición, así que una copia recortada sería mentira;
- ningún rol se queda sin `inventory.view`, para que nadie acabe con la app en
  blanco sin explicación.
"""
# Importación de UUID para identificadores tipados
import uuid
# Importación de tipos para anotaciones
from typing import List

# Importación de la sesión asíncrona de SQLAlchemy
from sqlalchemy import select, update
from sqlalchemy.ext.asyncio import AsyncSession

# Importación de excepciones de negocio
from app.core.exceptions.base import BadRequestException, NotFoundException
# Importación de modelos de dominio
from app.modules.auth_tenancy.domain.role import Role
from app.modules.auth_tenancy.domain.user import User
# Importación del repositorio de roles
from app.modules.auth_tenancy.repositories.role_repository import RoleRepository
# Importación del esquema de lectura: la respuesta se arma antes del commit
from app.modules.auth_tenancy.schemas.role import PermissionRead, RoleRead

# Permiso que todo rol conserva: sin él la app no muestra nada y el empleado
# no entiende qué le pasó (decisión de Eduardo, Sep 23).
MINIMUM_PERMISSION = "inventory.view"

# Rol intocable: el dueño ya pasa todas las puertas por definición.
PROTECTED_ROLE = "OWNER"


class RoleService:
    """Servicio de personalización de roles dentro de un comercio."""

    def __init__(self, db: AsyncSession):
        self.db = db
        self.repo = RoleRepository(db)

    @staticmethod
    def _snapshot(role: Role) -> RoleRead:
        """
        Copia en memoria de lo que hay que responder, tomada **antes** del
        commit.

        Releer después de cerrar la transacción es frágil con RLS: el contexto
        de tenant vive en la conexión, y al terminar la transacción la sesión
        puede tomar otra — entonces el SELECT no ve ni la copia recién creada y
        SQLAlchemy revienta al refrescar la entidad. Con la respuesta ya armada
        no hace falta volver a leer.
        """
        return RoleRead(
            id=role.id,
            name=role.name,
            description=role.description,
            tenant_id=role.tenant_id,
            permissions=[
                PermissionRead(id=p.id, code=p.code, description=p.description)
                for p in role.permissions
            ],
        )

    async def update_permissions(
        self,
        role_id: uuid.UUID,
        codes: List[str],
        current_user: User,
    ) -> RoleRead:
        """
        Deja el rol con exactamente [codes]. Si era un rol global del sistema,
        primero crea la copia del comercio y migra a los empleados que lo
        tenían; si ya era propio, sólo actualiza sus permisos.
        """
        tenant_id = current_user.tenant_id

        role = await self.repo.get_by_id(role_id)
        if not role:
            raise NotFoundException(f"El rol con ID '{role_id}' no existe.")

        # Un comercio no toca roles de otro (además de la política RLS)
        if role.tenant_id is not None and role.tenant_id != tenant_id:
            raise NotFoundException(f"El rol con ID '{role_id}' no existe.")

        if role.name == PROTECTED_ROLE:
            raise BadRequestException(
                "El rol Dueño no se puede modificar: tiene acceso total por definición."
            )

        # Códigos pedidos: normalizados, sin repetidos y todos del catálogo
        requested = sorted({c.strip() for c in codes if c and c.strip()})
        if MINIMUM_PERMISSION not in requested:
            raise BadRequestException(
                f"Todo rol debe conservar '{MINIMUM_PERMISSION}': sin él, quien lo "
                "tenga entraría a una aplicación vacía."
            )

        permissions = await self.repo.get_permissions_by_codes(requested)
        if len(permissions) != len(requested):
            encontrados = {p.code for p in permissions}
            faltantes = ", ".join(sorted(set(requested) - encontrados))
            raise BadRequestException(f"Permisos inexistentes: {faltantes}.")

        # Clone-on-write: la primera edición de un rol del sistema crea la copia
        if role.tenant_id is None:
            source = role
            # Idempotente a propósito: si el comercio ya tiene su copia de este
            # rol se reutiliza en vez de crear otra. Sin esto, pedir dos veces
            # la personalización del rol estándar —un reintento tras un error,
            # o dos toques seguidos— dejaba **dos** roles con el mismo nombre y
            # el listado mostraba dos "Cajero" (visto en el QA del Sep 23).
            existente = await self.repo.get_own_by_name(source.name, tenant_id)
            if existente is not None:
                role = existente
            else:
                role = await self.repo.clone_for_tenant(source, tenant_id)
            # Los empleados que tenían el rol estándar pasan a la copia: el
            # dueño piensa "mis cajeros ahora pueden X", no "los de mañana".
            await self.db.execute(
                update(User)
                .where(User.tenant_id == tenant_id, User.role_id == source.id)
                .values(role_id=role.id)
            )

        role.permissions = permissions
        await self.db.flush()
        respuesta = self._snapshot(role)
        await self.db.commit()
        return respuesta

    async def reset_role(self, role_id: uuid.UUID, current_user: User) -> RoleRead:
        """
        Devuelve un rol personalizado al estándar del sistema: los empleados
        vuelven al rol global del mismo nombre y la copia desaparece.
        """
        tenant_id = current_user.tenant_id

        role = await self.repo.get_by_id(role_id)
        if not role or role.tenant_id != tenant_id:
            raise NotFoundException(f"El rol con ID '{role_id}' no existe.")

        standard = await self.repo.get_global_by_name(role.name)
        if not standard:
            raise BadRequestException(
                f"No hay un rol estándar '{role.name}' al que volver."
            )

        # Primero los empleados, luego la copia: nadie queda sin rol
        await self.db.execute(
            update(User)
            .where(User.tenant_id == tenant_id, User.role_id == role.id)
            .values(role_id=standard.id)
        )
        # La respuesta se arma antes de cerrar la transacción (ver `_snapshot`)
        respuesta = self._snapshot(standard)
        await self.db.delete(role)
        await self.db.commit()
        return respuesta

    async def count_users_with_role(
        self, role_id: uuid.UUID, tenant_id: uuid.UUID
    ) -> int:
        """Cuántos empleados del comercio tienen ese rol asignado."""
        result = await self.db.execute(
            select(User.id).where(User.tenant_id == tenant_id, User.role_id == role_id)
        )
        return len(list(result.scalars().all()))
