# Importación de fecha y hora (ventana de duplicados, filtro `since`)
from datetime import datetime, timedelta
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
from app.modules.auth_tenancy.domain.user import User
from app.modules.inventory.domain.category import Category
from app.modules.inventory.domain.product import Product
from app.modules.inventory.domain.product_stock import ProductStock
from app.modules.whatsapp_catalog.domain.catalog_order import CatalogOrder
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

    async def get_tenant_by_id(self, tenant_id: uuid.UUID) -> Optional[Tenant]:
        """Obtiene el comercio de la sesión (para exponer nombre y slug en la configuración)."""
        stmt = select(Tenant).where(Tenant.id == tenant_id)
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
            if not hasattr(settings, field):
                continue
            # Los campos de texto se pueden borrar mandando cadena vacía (el
            # cliente Flutter lo usa para quitar el número de WhatsApp); los
            # demás ignoran None para no violar NOT NULL.
            if field in self._TEXT_FIELDS:
                cleaned = value.strip() if isinstance(value, str) else value
                setattr(settings, field, cleaned or None)
            elif value is not None:
                setattr(settings, field, value)
        await self.session.flush()
        await self.session.refresh(settings)
        return settings

    _TEXT_FIELDS = frozenset({"whatsapp_number", "welcome_message", "business_hours"})

    # -------------------------------------------------------------------------
    # Pedidos registrados desde la vitrina (RF-24)
    # -------------------------------------------------------------------------

    async def folio_exists(self, tenant_id: uuid.UUID, folio: str) -> bool:
        """Indica si el folio ya está tomado en este comercio."""
        stmt = select(CatalogOrder.id).where(
            CatalogOrder.tenant_id == tenant_id,
            CatalogOrder.folio == folio,
        )
        result = await self.session.execute(stmt)
        return result.scalar_one_or_none() is not None

    async def create_order(self, order: CatalogOrder) -> CatalogOrder:
        """Persiste el pedido y lo devuelve con su estampa de tiempo."""
        self.session.add(order)
        await self.session.flush()
        await self.session.refresh(order)
        return order

    async def get_order_by_folio_and_key(
        self, tenant_id: uuid.UUID, folio: str, access_key: str
    ) -> Optional[CatalogOrder]:
        """Ticket público: folio + clave del enlace (sin clave no hay ticket)."""
        stmt = select(CatalogOrder).where(
            CatalogOrder.tenant_id == tenant_id,
            func.upper(CatalogOrder.folio) == folio.strip().upper(),
            CatalogOrder.access_key == access_key.strip(),
        )
        result = await self.session.execute(stmt)
        return result.scalar_one_or_none()

    async def get_order_by_folio(self, tenant_id: uuid.UUID, folio: str) -> Optional[CatalogOrder]:
        """Obtiene un pedido del comercio por su folio (insensible a mayúsculas)."""
        stmt = select(CatalogOrder).where(
            CatalogOrder.tenant_id == tenant_id,
            func.upper(CatalogOrder.folio) == folio.strip().upper(),
        )
        result = await self.session.execute(stmt)
        return result.scalar_one_or_none()

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

    # -------------------------------------------------------------------------
    # Pedidos del lado del tendero (ciclo de vida, migración 0020)
    # -------------------------------------------------------------------------

    ACTIVE_STATUSES = ("NEW", "READY")

    async def list_orders(
        self,
        tenant_id: uuid.UUID,
        scope: str = "active",
        since: Optional[datetime] = None,
        limit: int = 50,
    ) -> List[CatalogOrder]:
        """
        `active` = NEW + READY (lo que falta atender); `history` = DELIVERED +
        CANCELLED; `all` = todo. `since` filtra por `updated_at` para que la app
        recupere lo que cambió mientras el socket estuvo caído.
        """
        stmt = select(CatalogOrder).where(CatalogOrder.tenant_id == tenant_id)
        if scope == "active":
            stmt = stmt.where(CatalogOrder.status.in_(self.ACTIVE_STATUSES))
        elif scope == "history":
            stmt = stmt.where(CatalogOrder.status.notin_(self.ACTIVE_STATUSES))
        if since is not None:
            stmt = stmt.where(CatalogOrder.updated_at > since)
        stmt = stmt.order_by(CatalogOrder.created_at.desc()).limit(limit)
        result = await self.session.execute(stmt)
        return list(result.scalars().all())

    async def count_orders(self, tenant_id: uuid.UUID, scope: str) -> int:
        """Conteo total del alcance (para paginar y para el badge)."""
        stmt = select(func.count(CatalogOrder.id)).where(CatalogOrder.tenant_id == tenant_id)
        if scope == "active":
            stmt = stmt.where(CatalogOrder.status.in_(self.ACTIVE_STATUSES))
        elif scope == "history":
            stmt = stmt.where(CatalogOrder.status.notin_(self.ACTIVE_STATUSES))
        return int((await self.session.execute(stmt)).scalar_one())

    async def count_new_unseen(self, tenant_id: uuid.UUID) -> int:
        """Badge: pedidos NEW que nadie ha abierto todavía."""
        stmt = select(func.count(CatalogOrder.id)).where(
            CatalogOrder.tenant_id == tenant_id,
            CatalogOrder.status == "NEW",
            CatalogOrder.seen_at.is_(None),
        )
        return int((await self.session.execute(stmt)).scalar_one())

    async def find_possible_duplicate(self, order: CatalogOrder, window_minutes: int = 15) -> Optional[str]:
        """
        Folio de otro pedido del mismo cliente con los mismos renglones en los
        últimos minutos — el cliente tocó "enviar" dos veces. Sólo se marca, nunca
        se fusiona: podría ser un segundo pedido legítimo.
        """
        if not order.created_at:
            return None
        since = order.created_at - timedelta(minutes=window_minutes)
        stmt = (
            select(CatalogOrder)
            .where(
                CatalogOrder.tenant_id == order.tenant_id,
                CatalogOrder.id != order.id,
                CatalogOrder.created_at >= since,
                CatalogOrder.created_at <= order.created_at,
                func.lower(CatalogOrder.customer_name) == order.customer_name.lower(),
                CatalogOrder.total_mxn == order.total_mxn,
            )
            .order_by(CatalogOrder.created_at.desc())
        )
        for candidate in (await self.session.execute(stmt)).scalars().all():
            if self._same_lines(candidate.items, order.items):
                return candidate.folio
        return None

    @staticmethod
    def _same_lines(a: List[Any], b: List[Any]) -> bool:
        def key(items: List[Any]) -> List[Tuple[str, str]]:
            return sorted((str(i.get("product_id")), str(i.get("quantity"))) for i in (items or []))
        return key(a) == key(b)

    async def get_user_names(self, user_ids: List[Optional[uuid.UUID]]) -> Dict[uuid.UUID, str]:
        """Nombres para "Lo vio Juan" / "Editado por Ana" en una sola consulta."""
        ids = {u for u in user_ids if u}
        if not ids:
            return {}
        stmt = select(User.id, User.full_name).where(User.id.in_(ids))
        rows = (await self.session.execute(stmt)).all()
        return {row[0]: row[1] for row in rows}

    async def save_order(self, order: CatalogOrder) -> CatalogOrder:
        """Persiste cambios del pedido y lo devuelve con `updated_at` fresco."""
        await self.session.flush()
        await self.session.refresh(order)
        return order
