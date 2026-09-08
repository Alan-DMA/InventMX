# Importación de UUID para tipado de identificadores
import uuid
# Importación de tipado estático
from typing import List, Optional
# Importación de funciones y sentencias de SQLAlchemy
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

# Importación del modelo de dominio Category
from app.modules.inventory.domain.category import Category


class CategoryRepository:
    """
    Repositorio de acceso a datos para la entidad Category.
    Encapsula operaciones de lectura, escritura y búsqueda de categorías respetando el contexto RLS.
    """

    def __init__(self, db: AsyncSession):
        # Asignación de la sesión de base de datos activa
        self.db = db

    async def get_by_id(self, category_id: uuid.UUID) -> Optional[Category]:
        """
        Obtiene una categoría por su identificador único UUID.
        """
        # Sentencia de selección filtrando por ID de categoría
        stmt = (
            select(Category)
            .where(Category.id == category_id)
            .execution_options(populate_existing=True)
        )
        result = await self.db.execute(stmt)
        return result.scalar_one_or_none()

    async def get_by_name(self, name: str, tenant_id: uuid.UUID) -> Optional[Category]:
        """
        Busca una categoría por nombre exacto dentro del tenant actual.
        """
        stmt = (
            select(Category)
            .where(Category.tenant_id == tenant_id, Category.name == name)
            .execution_options(populate_existing=True)
        )
        result = await self.db.execute(stmt)
        return result.scalar_one_or_none()

    async def get_or_create_default(self, tenant_id: uuid.UUID, default_name: str = "General") -> Category:
        """
        Obtiene o crea automáticamente la categoría por defecto 'General' para el tenant.
        """
        # Buscar si ya existe la categoría por defecto
        existing = await self.get_by_name(default_name, tenant_id)
        if existing:
            return existing

        # Si no existe, crearla e insertarla
        default_cat = Category(
            id=uuid.uuid4(),
            tenant_id=tenant_id,
            name=default_name,
            description="Categoría general predeterminada del sistema",
        )
        self.db.add(default_cat)
        await self.db.flush()
        return default_cat

    async def list_by_tenant(self, tenant_id: uuid.UUID) -> List[Category]:
        """
        Retorna la lista de todas las categorías pertenecientes a un comercio.
        """
        stmt = (
            select(Category)
            .where(Category.tenant_id == tenant_id)
            .order_by(Category.name.asc())
        )
        result = await self.db.execute(stmt)
        return list(result.scalars().all())

    async def create(
        self,
        tenant_id: uuid.UUID,
        name: str,
        description: Optional[str] = None,
    ) -> Category:
        """
        Crea e inserta una nueva categoría en la base de datos.
        """
        category = Category(
            id=uuid.uuid4(),
            tenant_id=tenant_id,
            name=name,
            description=description,
        )
        self.db.add(category)
        await self.db.flush()
        return category

    async def update(
        self,
        category: Category,
        name: Optional[str] = None,
        description: Optional[str] = None,
    ) -> Category:
        """
        Actualiza los atributos de una categoría existente.
        """
        if name is not None:
            category.name = name
        if description is not None:
            category.description = description

        await self.db.flush()
        return category

    async def delete(self, category: Category) -> None:
        """
        Elimina físicamente una categoría de la base de datos.
        """
        await self.db.delete(category)
        await self.db.flush()
