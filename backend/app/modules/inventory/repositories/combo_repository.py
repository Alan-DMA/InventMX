# Importación del módulo decimal para precios y cantidades
from decimal import Decimal
# Importación de tipado estático
from typing import List, Optional
# Importación de UUID para claves
import uuid
# Importación de constructores y funciones de SQLAlchemy
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

# Importación de modelos de dominio
from app.modules.inventory.domain.combo import Combo, ComboItem
from app.modules.inventory.domain.product import Product
from app.modules.inventory.schemas.combo import ComboItemCreate


class ComboRepository:
    """
    Repositorio de acceso a datos para la entidad Combo y sus ítems componentes (ComboItem).
    Maneja la persistencia y carga anticipada (eager-loading) de promociones.
    """

    def __init__(self, db: AsyncSession):
        # Asignación de la sesión asíncrona de base de datos
        self.db = db

    async def get_by_id(self, combo_id: uuid.UUID) -> Optional[Combo]:
        """
        Obtiene un combo por su UUID cargando anticipadamente sus ítems y productos individuales.
        """
        stmt = (
            select(Combo)
            .where(Combo.id == combo_id)
            .options(
                selectinload(Combo.items).selectinload(ComboItem.product).selectinload(Product.stocks),
            )
            .execution_options(populate_existing=True)
        )
        result = await self.db.execute(stmt)
        return result.scalar_one_or_none()

    async def get_by_sku(self, sku: str, tenant_id: uuid.UUID) -> Optional[Combo]:
        """
        Busca un combo por SKU dentro de un tenant específico.
        """
        stmt = (
            select(Combo)
            .where(Combo.tenant_id == tenant_id, Combo.sku == sku)
            .options(
                selectinload(Combo.items).selectinload(ComboItem.product).selectinload(Product.stocks),
            )
            .execution_options(populate_existing=True)
        )
        result = await self.db.execute(stmt)
        return result.scalar_one_or_none()

    async def get_by_barcode(self, barcode: str, tenant_id: uuid.UUID) -> Optional[Combo]:
        """
        Busca un combo por código de barras dentro de un tenant específico.
        """
        stmt = (
            select(Combo)
            .where(Combo.tenant_id == tenant_id, Combo.barcode == barcode)
            .options(
                selectinload(Combo.items).selectinload(ComboItem.product).selectinload(Product.stocks),
            )
            .execution_options(populate_existing=True)
        )
        result = await self.db.execute(stmt)
        return result.scalar_one_or_none()

    async def list_by_tenant(
        self,
        tenant_id: uuid.UUID,
        is_active: Optional[bool] = None,
        skip: int = 0,
        limit: int = 100,
    ) -> List[Combo]:
        """
        Retorna la lista de combos pertenecientes a un comercio.
        """
        stmt = (
            select(Combo)
            .where(Combo.tenant_id == tenant_id)
            .options(
                selectinload(Combo.items).selectinload(ComboItem.product).selectinload(Product.stocks),
            )
            .order_by(Combo.name.asc())
        )

        if is_active is not None:
            stmt = stmt.where(Combo.is_active == is_active)

        stmt = stmt.offset(skip).limit(limit)
        result = await self.db.execute(stmt)
        return list(result.scalars().all())

    async def create(
        self,
        tenant_id: uuid.UUID,
        name: str,
        price_mxn: Decimal,
        sku: str,
        items_data: List[ComboItemCreate],
        description: Optional[str] = None,
        barcode: Optional[str] = None,
        image_url: Optional[str] = None,
        is_active: bool = True,
    ) -> Combo:
        """
        Crea atómicamente un nuevo Combo y sus correspondientes registros de ítems componentes.
        """
        combo_id = uuid.uuid4()

        # 1. Crear entidad padre Combo
        combo = Combo(
            id=combo_id,
            tenant_id=tenant_id,
            name=name,
            description=description,
            price_mxn=price_mxn,
            sku=sku,
            barcode=barcode,
            image_url=image_url,
            is_active=is_active,
        )
        self.db.add(combo)

        # 2. Crear los registros de ítems de combo
        for item in items_data:
            combo_item = ComboItem(
                id=uuid.uuid4(),
                tenant_id=tenant_id,
                combo_id=combo_id,
                product_id=item.product_id,
                quantity=item.quantity,
            )
            self.db.add(combo_item)

        await self.db.flush()
        return combo

    async def update(
        self,
        combo: Combo,
        name: Optional[str] = None,
        description: Optional[str] = None,
        price_mxn: Optional[Decimal] = None,
        sku: Optional[str] = None,
        barcode: Optional[str] = None,
        image_url: Optional[str] = None,
        is_active: Optional[bool] = None,
        items_data: Optional[List[ComboItemCreate]] = None,
    ) -> Combo:
        """
        Actualiza los campos de un combo existente y sincroniza sus componentes si fueron provistos.
        """
        if name is not None:
            combo.name = name
        if description is not None:
            combo.description = description
        if price_mxn is not None:
            combo.price_mxn = price_mxn
        if sku is not None:
            combo.sku = sku
        if barcode is not None:
            combo.barcode = barcode
        if image_url is not None:
            combo.image_url = image_url
        if is_active is not None:
            combo.is_active = is_active

        # Si se envían nuevos componentes, reemplazar los existentes
        if items_data is not None:
            # Eliminar ítems previos
            for old_item in combo.items:
                await self.db.delete(old_item)

            # Insertar nuevos ítems
            for item in items_data:
                new_item = ComboItem(
                    id=uuid.uuid4(),
                    tenant_id=combo.tenant_id,
                    combo_id=combo.id,
                    product_id=item.product_id,
                    quantity=item.quantity,
                )
                self.db.add(new_item)

        await self.db.flush()
        return combo

    async def delete(self, combo: Combo) -> None:
        """
        Elimina físicamente un combo del catálogo.
        """
        await self.db.delete(combo)
        await self.db.flush()
