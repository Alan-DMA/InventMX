# Importación de precisión decimal para cálculos de existencias
from decimal import Decimal
# Importación de tipado estático
from typing import Any, Dict, List, Optional, Tuple
# Importación de identificadores únicos UUID
import uuid

# Importación de constructs de SQLAlchemy
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

# Importación de entidades de dominio
from app.modules.auth_tenancy.domain.tenant import Tenant, TenantStatus
from app.modules.inventory.domain.category import Category
from app.modules.inventory.domain.product import Product
from app.modules.inventory.domain.product_stock import ProductStock
from app.modules.whatsapp_catalog.domain.catalog_settings import CatalogSettings


class CatalogRepository:
    """
    Repositorio de acceso a datos para el Catálogo Digital de WhatsApp Web (RF-23, RF-26).
    Maneja consultas públicas por slug de tienda y configuraciones del comercio.
    """

    def __init__(self, session: AsyncSession) -> None:
        # Inyección de la sesión asíncrona de base de datos
        self.session = session

    async def get_tenant_by_slug(self, slug: str) -> Optional[Tenant]:
        """Obtiene un comercio activo por su identificador URL amigable (slug)."""
        stmt = select(Tenant).where(
            Tenant.slug == slug.lower().strip(),
            Tenant.status == TenantStatus.ACTIVE,
        )
        result = await self.session.execute(stmt)
        return result.scalar_one_or_none()

    async def get_catalog_settings(self, tenant_id: uuid.UUID) -> Optional[CatalogSettings]:
        """Obtiene la configuración del catálogo digital para el comercio."""
        stmt = select(CatalogSettings).where(CatalogSettings.tenant_id == tenant_id)
        result = await self.session.execute(stmt)
        return result.scalar_one_or_none()

    async def get_or_create_settings(self, tenant_id: uuid.UUID) -> CatalogSettings:
        """Obtiene la configuración existente o inicializa una con valores por defecto."""
        settings = await self.get_catalog_settings(tenant_id)
        if not settings:
            settings = CatalogSettings(
                tenant_id=tenant_id,
                is_catalog_enabled=True,
                min_order_amount_mxn=Decimal("0.00"),
                delivery_fee_mxn=Decimal("0.00"),
                delivery_enabled=True,
                pickup_enabled=True,
            )
            self.session.add(settings)
            await self.session.flush()
            await self.session.refresh(settings)
        return settings

    async def update_settings(
        self,
        tenant_id: uuid.UUID,
        update_data: Dict[str, Any],
    ) -> CatalogSettings:
        """Actualiza la configuración del catálogo digital del comercio."""
        settings = await self.get_or_create_settings(tenant_id)
        for field, value in update_data.items():
            if value is not None and hasattr(settings, field):
                setattr(settings, field, value)
        await self.session.flush()
        await self.session.refresh(settings)
        return settings

    async def get_public_categories(self, tenant_id: uuid.UUID) -> List[Tuple[Category, int]]:
        """
        Obtiene las categorías del comercio que contienen al menos un producto activo visible.
        Retorna lista de tuplas (Category, conteo_de_productos).
        """
        stmt = (
            select(
                Category,
                func.count(Product.id).label("prod_count"),
            )
            .join(Product, Product.category_id == Category.id)
            .where(
                Category.tenant_id == tenant_id,
                Product.tenant_id == tenant_id,
                Product.is_active == True,
                Product.show_in_catalog == True,
            )
            .group_by(Category.id)
            .order_by(Category.name.asc())
        )
        result = await self.session.execute(stmt)
        return list(result.all())

    async def get_public_products(
        self,
        tenant_id: uuid.UUID,
        category_id: Optional[uuid.UUID] = None,
        search: Optional[str] = None,
    ) -> List[Tuple[Product, Decimal, Optional[str]]]:
        """
        Obtiene los productos activos y visibles en el catálogo web con su stock total y nombre de categoría.
        Retorna lista de tuplas (Product, total_stock, category_name).
        """
        # Subconsulta de suma de existencias físicas
        stock_subq = (
            select(
                ProductStock.product_id,
                func.coalesce(func.sum(ProductStock.current_stock), Decimal("0.00")).label("total_stock"),
            )
            .where(ProductStock.tenant_id == tenant_id)
            .group_by(ProductStock.product_id)
            .subquery()
        )

        stmt = (
            select(
                Product,
                func.coalesce(stock_subq.c.total_stock, Decimal("0.00")).label("stock_qty"),
                Category.name.label("cat_name"),
            )
            .outerjoin(stock_subq, stock_subq.c.product_id == Product.id)
            .outerjoin(Category, Category.id == Product.category_id)
            .where(
                Product.tenant_id == tenant_id,
                Product.is_active == True,
                Product.show_in_catalog == True,
            )
        )

        # Filtro opcional por categoría
        if category_id:
            stmt = stmt.where(Product.category_id == category_id)

        # Filtro opcional por búsqueda textual o SKU
        if search:
            search_pattern = f"%{search.strip().lower()}%"
            stmt = stmt.where(
                func.lower(Product.name).ilike(search_pattern)
                | func.lower(Product.sku).ilike(search_pattern)
            )

        stmt = stmt.order_by(Product.name.asc())
        result = await self.session.execute(stmt)
        return list(result.all())

    async def get_public_product_by_id(
        self,
        tenant_id: uuid.UUID,
        product_id: uuid.UUID,
    ) -> Optional[Tuple[Product, Decimal, Optional[str]]]:
        """
        Obtiene el detalle individual de un producto público con su stock disponible.
        """
        stock_subq = (
            select(
                ProductStock.product_id,
                func.coalesce(func.sum(ProductStock.current_stock), Decimal("0.00")).label("total_stock"),
            )
            .where(ProductStock.tenant_id == tenant_id)
            .group_by(ProductStock.product_id)
            .subquery()
        )

        stmt = (
            select(
                Product,
                func.coalesce(stock_subq.c.total_stock, Decimal("0.00")).label("stock_qty"),
                Category.name.label("cat_name"),
            )
            .outerjoin(stock_subq, stock_subq.c.product_id == Product.id)
            .outerjoin(Category, Category.id == Product.category_id)
            .where(
                Product.tenant_id == tenant_id,
                Product.id == product_id,
                Product.is_active == True,
                Product.show_in_catalog == True,
            )
        )
        result = await self.session.execute(stmt)
        return result.first()
