# Importación del módulo decimal para cálculos monetarios y porcentajes
from decimal import Decimal
# Importación de tipado estático
from typing import List, Optional
# Importación de UUID para identificación de entidades
import uuid
# Importación de la sesión asíncrona de SQLAlchemy
from sqlalchemy.ext.asyncio import AsyncSession

# Importación de utilidades de base de datos e inyección RLS
from app.core.database.session import set_tenant_context
# Importación de excepciones de negocio del sistema
from app.core.exceptions.base import (
    BadRequestException,
    ConflictException,
    NotFoundException,
)
# Importación de modelos de dominio
from app.modules.auth_tenancy.domain.user import User
from app.modules.inventory.domain.category import Category
from app.modules.inventory.domain.product import Product
from app.modules.inventory.domain.warehouse import Warehouse
# Importación de repositorios de datos
from app.modules.inventory.repositories.category_repository import CategoryRepository
from app.modules.inventory.repositories.product_repository import ProductRepository
from app.modules.inventory.repositories.warehouse_repository import WarehouseRepository
# Importación de esquemas Pydantic
from app.modules.inventory.schemas.category import CategoryCreate, CategoryResponse
from app.modules.inventory.schemas.product import (
    ProductCreateVital,
    ProductListItem,
    ProductResponse,
    ProductStockResponse,
    ProductUpdate,
)
from app.modules.inventory.schemas.warehouse import WarehouseCreate, WarehouseResponse


class InventoryService:
    """
    Servicio de lógica de negocio para el Módulo de Inventario y Catálogo (Core).
    Implementa la regla de los 3 Campos Vitales (SR-08 / Const. Art. 7.3), autogeneración de SKU,
    soporte multi-almacén, cálculo de margen comercial en MXN y búsquedas de alta velocidad.
    """

    def __init__(self, db: AsyncSession):
        # Inyección de la sesión asíncrona de base de datos
        self.db = db
        # Instanciación de repositorios del módulo
        self.product_repo = ProductRepository(db)
        self.category_repo = CategoryRepository(db)
        self.warehouse_repo = WarehouseRepository(db)

    def _build_product_response(self, product: Product) -> ProductResponse:
        """
        Método auxiliar para construir la respuesta completa de un Producto
        calculando existencias acumuladas, alertas de stock bajo y margen comercial en MXN.
        """
        # Calcular existencias físicas totales sumando todos los almacenes
        total_stock = sum((s.current_stock for s in product.stocks), Decimal("0.00"))

        # Determinar si el producto se encuentra en nivel crítico de stock
        is_low_stock = total_stock <= product.min_stock_alert

        # Calcular margen de ganancia bruto: ((Precio - Costo) / Precio) * 100
        margin_percentage: Optional[Decimal] = None
        if product.price_mxn > Decimal("0.00"):
            profit = product.price_mxn - product.cost_mxn
            margin_percentage = Decimal(round((profit / product.price_mxn) * Decimal("100.00"), 2))

        # Construir desglose de existencias por almacén
        stocks_response: List[ProductStockResponse] = [
            ProductStockResponse(
                id=s.id,
                warehouse_id=s.warehouse_id,
                current_stock=s.current_stock,
                reserved_stock=s.reserved_stock,
                updated_at=s.updated_at,
            )
            for s in product.stocks
        ]

        # Retornar DTO de respuesta con datos enriquecidos
        return ProductResponse(
            id=product.id,
            tenant_id=product.tenant_id,
            category_id=product.category_id,
            category_name=product.category.name if product.category else None,
            name=product.name,
            price_mxn=product.price_mxn,
            cost_mxn=product.cost_mxn,
            cost_usd_import=product.cost_usd_import,
            sku=product.sku,
            barcode=product.barcode,
            min_stock_alert=product.min_stock_alert,
            image_url=product.image_url,
            is_active=product.is_active,
            total_stock=total_stock,
            is_low_stock=is_low_stock,
            margin_percentage=margin_percentage,
            stocks=stocks_response,
            created_at=product.created_at,
            updated_at=product.updated_at,
        )

    # -------------------------------------------------------------------------
    # GESTIÓN DE PRODUCTOS (3 CAMPOS VITALES Y CRUD COMPLETO)
    # -------------------------------------------------------------------------

    async def create_product_vital(
        self, data: ProductCreateVital, current_user: User
    ) -> ProductResponse:
        """
        Registra un producto utilizando el Formulario Minimalista de 3 Campos Vitales (SR-08):
        1. name (Nombre)
        2. price_mxn (Precio en Pesos Mexicanos)
        3. initial_stock (Existencias iniciales)
        Autogenera el SKU ('NEX-XXXXX'), asigna la categoría 'General' y el almacén principal.
        """
        # Extraer ID del comercio para evitar lazy-loading
        tenant_id = current_user.tenant_id

        # Asegurar contexto RLS en PostgreSQL
        await set_tenant_context(self.db, tenant_id)

        # 1. Validar categoría o asignar categoría por defecto 'General'
        category_id = data.category_id
        if category_id is None:
            default_category = await self.category_repo.get_or_create_default(tenant_id)
            category_id = default_category.id
        else:
            category = await self.category_repo.get_by_id(category_id)
            if not category or category.tenant_id != tenant_id:
                raise NotFoundException(f"La categoría con ID '{category_id}' no existe.")

        # 2. Validar almacén o asignar almacén principal por defecto
        warehouse_id = data.warehouse_id
        if warehouse_id is None:
            default_warehouse = await self.warehouse_repo.get_or_create_default(tenant_id)
            warehouse_id = default_warehouse.id
        else:
            warehouse = await self.warehouse_repo.get_by_id(warehouse_id)
            if not warehouse or warehouse.tenant_id != tenant_id:
                raise NotFoundException(f"El almacén con ID '{warehouse_id}' no existe.")

        # 3. Generar o validar código SKU único
        if data.sku:
            clean_sku = data.sku.strip()
            existing_sku = await self.product_repo.get_by_sku(clean_sku, tenant_id)
            if existing_sku:
                raise ConflictException(f"El código SKU '{clean_sku}' ya está registrado en tu catálogo.")
            final_sku = clean_sku
        else:
            final_sku = await self.product_repo.generate_unique_sku(tenant_id)

        # 4. Validar código de barras si fue provisto
        final_barcode = data.barcode.strip() if data.barcode else None
        if final_barcode:
            existing_barcode = await self.product_repo.get_by_barcode(final_barcode, tenant_id)
            if existing_barcode:
                raise ConflictException(f"El código de barras '{final_barcode}' ya existe en el producto '{existing_barcode.name}'.")

        # 5. Inserción atómica del producto y de sus existencias iniciales (Campo Vital 3)
        created_product = await self.product_repo.create_with_stock(
            tenant_id=tenant_id,
            name=data.name.strip(),
            price_mxn=data.price_mxn,
            initial_stock=data.initial_stock,
            warehouse_id=warehouse_id,
            sku=final_sku,
            cost_mxn=data.cost_mxn or Decimal("0.00"),
            cost_usd_import=data.cost_usd_import,
            barcode=final_barcode,
            category_id=category_id,
            min_stock_alert=data.min_stock_alert or Decimal("5.00"),
            image_url=data.image_url,
            is_active=True,
        )

        # Persistir la transacción
        await self.db.commit()

        # Recargar producto con relaciones frescas
        await set_tenant_context(self.db, tenant_id)
        reloaded_product = await self.product_repo.get_by_id(created_product.id)
        if not reloaded_product:
            raise NotFoundException("Error al recargar el producto recién creado.")

        return self._build_product_response(reloaded_product)

    async def list_products(
        self,
        current_user: User,
        category_id: Optional[uuid.UUID] = None,
        is_active: Optional[bool] = None,
        query: Optional[str] = None,
        is_low_stock: Optional[bool] = None,
        skip: int = 0,
        limit: int = 100,
    ) -> List[ProductResponse]:
        """
        Retorna el listado de productos del comercio aplicando filtros por categoría,
        estado activo, búsqueda por texto/código de barras y filtro de stock crítico.
        """
        tenant_id = current_user.tenant_id
        await set_tenant_context(self.db, tenant_id)

        # Consultar productos desde el repositorio
        products = await self.product_repo.list_products(
            tenant_id=tenant_id,
            category_id=category_id,
            is_active=is_active,
            query=query,
            skip=skip,
            limit=limit,
        )

        # Mapear y calcular campos enriquecidos para cada producto
        responses = [self._build_product_response(p) for p in products]

        # Filtrar por stock bajo si fue solicitado
        if is_low_stock is True:
            responses = [r for r in responses if r.is_low_stock]

        return responses

    async def get_product_by_id(
        self, product_id: uuid.UUID, current_user: User
    ) -> ProductResponse:
        """
        Obtiene el detalle completo de un producto verificando pertenencia al tenant.
        """
        tenant_id = current_user.tenant_id
        await set_tenant_context(self.db, tenant_id)

        product = await self.product_repo.get_by_id(product_id)
        if not product or product.tenant_id != tenant_id:
            raise NotFoundException(f"Producto con ID '{product_id}' no encontrado.")

        return self._build_product_response(product)

    async def update_product(
        self, product_id: uuid.UUID, data: ProductUpdate, current_user: User
    ) -> ProductResponse:
        """
        Actualiza los datos de un producto (nombre, precio MXN, costo, SKU, categoría, etc.).
        """
        tenant_id = current_user.tenant_id
        await set_tenant_context(self.db, tenant_id)

        # Consultar producto
        product = await self.product_repo.get_by_id(product_id)
        if not product or product.tenant_id != tenant_id:
            raise NotFoundException(f"Producto con ID '{product_id}' no encontrado.")

        # Validar SKU si se modifica
        if data.sku is not None:
            clean_sku = data.sku.strip()
            if clean_sku != product.sku:
                existing_sku = await self.product_repo.get_by_sku(clean_sku, tenant_id)
                if existing_sku and existing_sku.id != product_id:
                    raise ConflictException(f"El código SKU '{clean_sku}' ya está en uso por otro producto.")

        # Validar código de barras si se modifica
        if data.barcode is not None:
            clean_barcode = data.barcode.strip()
            if clean_barcode != product.barcode:
                existing_barcode = await self.product_repo.get_by_barcode(clean_barcode, tenant_id)
                if existing_barcode and existing_barcode.id != product_id:
                    raise ConflictException(f"El código de barras '{clean_barcode}' ya está en uso.")

        # Validar categoría si se modifica
        if data.category_id is not None:
            category = await self.category_repo.get_by_id(data.category_id)
            if not category or category.tenant_id != tenant_id:
                raise NotFoundException(f"La categoría con ID '{data.category_id}' no existe.")

        # Actualizar campos
        await self.product_repo.update(
            product=product,
            name=data.name.strip() if data.name else None,
            price_mxn=data.price_mxn,
            cost_mxn=data.cost_mxn,
            cost_usd_import=data.cost_usd_import,
            sku=data.sku.strip() if data.sku else None,
            barcode=data.barcode.strip() if data.barcode else None,
            category_id=data.category_id,
            min_stock_alert=data.min_stock_alert,
            image_url=data.image_url,
            is_active=data.is_active,
        )

        # Persistir cambios
        await self.db.commit()

        # Recargar entidad
        await set_tenant_context(self.db, tenant_id)
        reloaded = await self.product_repo.get_by_id(product.id)
        if not reloaded:
            raise NotFoundException("Error al recargar el producto actualizado.")

        return self._build_product_response(reloaded)

    async def delete_product(self, product_id: uuid.UUID, current_user: User) -> None:
        """
        Elimina físicamente un producto del catálogo maestro.
        """
        tenant_id = current_user.tenant_id
        await set_tenant_context(self.db, tenant_id)

        product = await self.product_repo.get_by_id(product_id)
        if not product or product.tenant_id != tenant_id:
            raise NotFoundException(f"Producto con ID '{product_id}' no encontrado.")

        await self.product_repo.delete(product)
        await self.db.commit()

    # -------------------------------------------------------------------------
    # GESTIÓN DE CATEGORÍAS
    # -------------------------------------------------------------------------

    async def list_categories(self, current_user: User) -> List[CategoryResponse]:
        """
        Retorna la lista de todas las categorías del comercio.
        """
        tenant_id = current_user.tenant_id
        await set_tenant_context(self.db, tenant_id)
        categories = await self.category_repo.list_by_tenant(tenant_id)
        return [CategoryResponse.model_validate(c) for c in categories]

    async def create_category(
        self, data: CategoryCreate, current_user: User
    ) -> CategoryResponse:
        """
        Crea una nueva categoría de productos.
        """
        tenant_id = current_user.tenant_id
        await set_tenant_context(self.db, tenant_id)

        clean_name = data.name.strip()
        existing = await self.category_repo.get_by_name(clean_name, tenant_id)
        if existing:
            raise ConflictException(f"Ya existe una categoría con el nombre '{clean_name}'.")

        category = await self.category_repo.create(
            tenant_id=tenant_id,
            name=clean_name,
            description=data.description.strip() if data.description else None,
        )
        await self.db.commit()
        return CategoryResponse.model_validate(category)

    # -------------------------------------------------------------------------
    # GESTIÓN DE ALMACENES
    # -------------------------------------------------------------------------

    async def list_warehouses(self, current_user: User) -> List[WarehouseResponse]:
        """
        Retorna la lista de almacenes y sucursales del comercio.
        """
        tenant_id = current_user.tenant_id
        await set_tenant_context(self.db, tenant_id)
        warehouses = await self.warehouse_repo.list_by_tenant(tenant_id)
        return [WarehouseResponse.model_validate(w) for w in warehouses]

    async def create_warehouse(
        self, data: WarehouseCreate, current_user: User
    ) -> WarehouseResponse:
        """
        Crea un nuevo almacén físico.
        """
        tenant_id = current_user.tenant_id
        await set_tenant_context(self.db, tenant_id)

        clean_name = data.name.strip()
        warehouse = await self.warehouse_repo.create(
            tenant_id=tenant_id,
            name=clean_name,
            is_default=data.is_default,
        )
        await self.db.commit()
        return WarehouseResponse.model_validate(warehouse)
