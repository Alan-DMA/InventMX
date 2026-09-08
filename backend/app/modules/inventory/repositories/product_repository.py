# Importación del módulo random para generación de sufijos en SKU
import random
# Importación del módulo decimal para cantidades de stock y dinero
from decimal import Decimal
# Importación de tipado estático
from typing import List, Optional, Tuple
# Importación de UUID para claves primarias
import uuid
# Importación de constructores de consulta y funciones de SQLAlchemy
from sqlalchemy import func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

# Importación de modelos de dominio
from app.modules.inventory.domain.category import Category
from app.modules.inventory.domain.product import Product
from app.modules.inventory.domain.product_stock import ProductStock
from app.modules.inventory.domain.warehouse import Warehouse


class ProductRepository:
    """
    Repositorio de acceso a datos para la entidad Product y sus existencias (ProductStock).
    Encapsula consultas complejas, búsquedas difusas con trigramas e inserciones atómicas.
    """

    def __init__(self, db: AsyncSession):
        # Asignación de la sesión asíncrona de base de datos
        self.db = db

    async def get_by_id(self, product_id: uuid.UUID) -> Optional[Product]:
        """
        Obtiene un producto por su UUID, cargando de forma anticipada (eager-loading)
        su categoría y desglose de existencias por almacén.
        """
        stmt = (
            select(Product)
            .where(Product.id == product_id)
            .options(
                selectinload(Product.category),
                selectinload(Product.stocks).selectinload(ProductStock.warehouse),
            )
            .execution_options(populate_existing=True)
        )
        result = await self.db.execute(stmt)
        return result.scalar_one_or_none()

    async def get_by_sku(self, sku: str, tenant_id: uuid.UUID) -> Optional[Product]:
        """
        Busca un producto por su código SKU dentro de un tenant específico.
        """
        stmt = (
            select(Product)
            .where(Product.tenant_id == tenant_id, Product.sku == sku)
            .options(
                selectinload(Product.category),
                selectinload(Product.stocks).selectinload(ProductStock.warehouse),
            )
            .execution_options(populate_existing=True)
        )
        result = await self.db.execute(stmt)
        return result.scalar_one_or_none()

    async def get_by_barcode(self, barcode: str, tenant_id: uuid.UUID) -> Optional[Product]:
        """
        Busca un producto por su código de barras EAN/UPC dentro de un tenant específico.
        """
        stmt = (
            select(Product)
            .where(Product.tenant_id == tenant_id, Product.barcode == barcode)
            .options(
                selectinload(Product.category),
                selectinload(Product.stocks).selectinload(ProductStock.warehouse),
            )
            .execution_options(populate_existing=True)
        )
        result = await self.db.execute(stmt)
        return result.scalar_one_or_none()

    async def generate_unique_sku(self, tenant_id: uuid.UUID) -> str:
        """
        Genera un código SKU único con el formato sagrado 'NEX-XXXXX' (SR-08 / Const. Art. 7.3).
        Verifica que no colisione con ningún SKU existente del comercio.
        """
        max_attempts = 10
        for _ in range(max_attempts):
            # Generar número secuencial o aleatorio de 5 dígitos
            number_part = f"{random.randint(10000, 99999)}"
            candidate_sku = f"NEX-{number_part}"

            # Verificar si ya existe en la base de datos
            existing = await self.get_by_sku(candidate_sku, tenant_id)
            if not existing:
                return candidate_sku

        # Fallback con UUID abreviado si hay colisión reiterada
        return f"NEX-{uuid.uuid4().hex[:5].upper()}"

    async def list_products(
        self,
        tenant_id: uuid.UUID,
        category_id: Optional[uuid.UUID] = None,
        is_active: Optional[bool] = None,
        query: Optional[str] = None,
        skip: int = 0,
        limit: int = 100,
    ) -> List[Product]:
        """
        Retorna la lista de productos del comercio aplicando filtros opcionales
        y búsqueda por texto difuso (pg_trgm) o código de barras.
        """
        stmt = (
            select(Product)
            .where(Product.tenant_id == tenant_id)
            .options(
                selectinload(Product.category),
                selectinload(Product.stocks).selectinload(ProductStock.warehouse),
            )
            .order_by(Product.name.asc())
        )

        # Filtro por categoría
        if category_id is not None:
            stmt = stmt.where(Product.category_id == category_id)

        # Filtro por estado activo
        if is_active is not None:
            stmt = stmt.where(Product.is_active == is_active)

        # Filtro de búsqueda por texto o código de barras
        if query:
            clean_query = query.strip()
            # Búsqueda coincidente por código de barras exacto, SKU o subcadena de nombre
            stmt = stmt.where(
                or_(
                    Product.barcode == clean_query,
                    Product.sku.ilike(f"%{clean_query}%"),
                    Product.name.ilike(f"%{clean_query}%"),
                )
            )

        # Paginación
        stmt = stmt.offset(skip).limit(limit)

        result = await self.db.execute(stmt)
        return list(result.scalars().all())

    async def create_with_stock(
        self,
        tenant_id: uuid.UUID,
        name: str,
        price_mxn: Decimal,
        initial_stock: Decimal,
        warehouse_id: uuid.UUID,
        sku: str,
        cost_mxn: Decimal = Decimal("0.00"),
        cost_usd_import: Optional[Decimal] = None,
        barcode: Optional[str] = None,
        category_id: Optional[uuid.UUID] = None,
        min_stock_alert: Decimal = Decimal("5.00"),
        image_url: Optional[str] = None,
        is_active: bool = True,
    ) -> Product:
        """
        Crea atómicamente un nuevo Producto y su correspondiente registro inicial
        de existencias (ProductStock) en el almacén especificado.
        """
        product_id = uuid.uuid4()

        # 1. Crear la entidad Producto
        product = Product(
            id=product_id,
            tenant_id=tenant_id,
            category_id=category_id,
            name=name,
            price_mxn=price_mxn,
            cost_mxn=cost_mxn,
            cost_usd_import=cost_usd_import,
            sku=sku,
            barcode=barcode,
            min_stock_alert=min_stock_alert,
            image_url=image_url,
            is_active=is_active,
        )
        self.db.add(product)

        # 2. Crear el registro de stock inicial (Campo Vital 3)
        stock = ProductStock(
            id=uuid.uuid4(),
            tenant_id=tenant_id,
            product_id=product_id,
            warehouse_id=warehouse_id,
            current_stock=initial_stock,
            reserved_stock=Decimal("0.00"),
        )
        self.db.add(stock)

        # 3. Enviar cambios a la base de datos
        await self.db.flush()
        return product

    async def update(
        self,
        product: Product,
        name: Optional[str] = None,
        price_mxn: Optional[Decimal] = None,
        cost_mxn: Optional[Decimal] = None,
        cost_usd_import: Optional[Decimal] = None,
        sku: Optional[str] = None,
        barcode: Optional[str] = None,
        category_id: Optional[uuid.UUID] = None,
        min_stock_alert: Optional[Decimal] = None,
        image_url: Optional[str] = None,
        is_active: Optional[bool] = None,
    ) -> Product:
        """
        Actualiza los campos proporcionados de un producto existente.
        """
        if name is not None:
            product.name = name
        if price_mxn is not None:
            product.price_mxn = price_mxn
        if cost_mxn is not None:
            product.cost_mxn = cost_mxn
        if cost_usd_import is not None:
            product.cost_usd_import = cost_usd_import
        if sku is not None:
            product.sku = sku
        if barcode is not None:
            product.barcode = barcode
        if category_id is not None:
            product.category_id = category_id
        if min_stock_alert is not None:
            product.min_stock_alert = min_stock_alert
        if image_url is not None:
            product.image_url = image_url
        if is_active is not None:
            product.is_active = is_active

        await self.db.flush()
        return product

    async def delete(self, product: Product) -> None:
        """
        Elimina físicamente un producto y sus existencias asociadas por cascade.
        """
        await self.db.delete(product)
        await self.db.flush()
