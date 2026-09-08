# Importación del módulo datetime y timedelta para cálculo de expiraciones
from datetime import datetime, timedelta, timezone
# Importación del módulo decimal para cálculos monetarios y porcentajes
from decimal import Decimal
# Importación de módulos de parseo CSV, Excel y flujos en memoria
import csv
import io
import openpyxl
import re
# Importación de tipado estático
from typing import Any, Dict, List, Optional, Tuple
# Importación de UUID para identificación de entidades
import uuid
# Importación de la sesión asíncrona de SQLAlchemy
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

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
from app.modules.inventory.domain.combo import Combo, ComboItem
from app.modules.inventory.domain.inventory_movement import (
    InventoryMovement,
    MovementType,
)
from app.modules.inventory.domain.product import Product
from app.modules.inventory.domain.product_stock import ProductStock
from app.modules.inventory.domain.seed_product import SeedProduct
from app.modules.inventory.domain.stock_reservation import (
    ReservationStatus,
    StockReservation,
)
from app.modules.inventory.domain.warehouse import Warehouse

# Importación de repositorios de datos
from app.modules.inventory.repositories.category_repository import CategoryRepository
from app.modules.inventory.repositories.combo_repository import ComboRepository
from app.modules.inventory.repositories.movement_repository import MovementRepository
from app.modules.inventory.repositories.product_repository import ProductRepository
from app.modules.inventory.repositories.reservation_repository import (
    ReservationRepository,
)
from app.modules.inventory.repositories.seed_product_repository import (
    SeedProductRepository,
)
from app.modules.inventory.repositories.warehouse_repository import WarehouseRepository

# Importación de esquemas Pydantic
from app.modules.inventory.schemas.category import CategoryCreate, CategoryResponse
from app.modules.inventory.schemas.combo import (
    ComboCreate,
    ComboItemResponse,
    ComboResponse,
    ComboUpdate,
)
from app.modules.inventory.schemas.import_export import (
    ColumnMapping,
    ImportExecutionResponse,
    ImportPreviewResponse,
    ImportRowError,
)
from app.modules.inventory.schemas.movement import (
    InventoryMovementResponse,
    StockAdjustmentCreate,
    StockTransferCreate,
)
from app.modules.inventory.schemas.product import (
    ProductCreateVital,
    ProductListItem,
    ProductResponse,
    ProductStockResponse,
    ProductUpdate,
)
from app.modules.inventory.schemas.reservation import (
    StockReservationCreate,
    StockReservationResponse,
)
from app.modules.inventory.schemas.seed_product import (
    EanLookupResponse,
    SeedProductResponse,
)
from app.modules.inventory.schemas.warehouse import WarehouseCreate, WarehouseResponse


class InventoryService:
    """
    Servicio integral de lógica de negocio para el Módulo de Inventario, Catálogo, Combos, Kardex,
    Catálogo Semilla EAN-13 e Importación Flexible de Archivos Excel/CSV.
    Implementa la regla de los 3 Campos Vitales (SR-08), consistencia ACID en Kardex inmutable (Const. Art. 7.1),
    promociones y combos (RF-03), traslados multi-almacén (RF-07), stock reservado con TTL de 15 min (RF-06),
    reconocimiento EAN-13 instantáneo en < 5ms (RF-29) e ingesta masiva con mapeo dinámico (RF-01).
    """

    def __init__(self, db: AsyncSession):
        # Inyección de la sesión asíncrona de base de datos
        self.db = db
        # Instanciación de repositorios del módulo
        self.product_repo = ProductRepository(db)
        self.category_repo = CategoryRepository(db)
        self.warehouse_repo = WarehouseRepository(db)
        self.combo_repo = ComboRepository(db)
        self.movement_repo = MovementRepository(db)
        self.reservation_repo = ReservationRepository(db)
        self.seed_product_repo = SeedProductRepository(db)

    def _build_product_response(self, product: Product) -> ProductResponse:
        """
        Método auxiliar para construir la respuesta completa de un Producto
        calculando existencias acumuladas, alertas de stock bajo y margen comercial en MXN.
        """
        total_stock = sum((s.current_stock for s in product.stocks), Decimal("0.00"))
        is_low_stock = total_stock <= product.min_stock_alert

        margin_percentage: Optional[Decimal] = None
        if product.price_mxn > Decimal("0.00"):
            profit = product.price_mxn - product.cost_mxn
            margin_percentage = Decimal(round((profit / product.price_mxn) * Decimal("100.00"), 2))

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

    def _build_combo_response(self, combo: Combo) -> ComboResponse:
        """
        Construye la respuesta completa de un Combo calculando el número máximo de paquetes
        que pueden armarse en base a las existencias físicas actuales de cada componente (RF-03).
        """
        items_response: List[ComboItemResponse] = []
        possible_combos_list: List[Decimal] = []

        for item in combo.items:
            prod = item.product
            # Calcular existencias totales del producto
            prod_stock = sum((s.current_stock for s in prod.stocks), Decimal("0.00")) if prod.stocks else Decimal("0.00")
            
            # Cantidad de combos que se pueden armar con las existencias de este producto
            if item.quantity > Decimal("0.00"):
                max_combos_for_item = prod_stock // item.quantity
                possible_combos_list.append(max_combos_for_item)

            items_response.append(
                ComboItemResponse(
                    id=item.id,
                    product_id=item.product_id,
                    product_name=prod.name if prod else "Desconocido",
                    quantity=item.quantity,
                    product_price_mxn=prod.price_mxn if prod else Decimal("0.00"),
                )
            )

        # El stock vendible del combo es el cuello de botella (mínimo de todos sus componentes)
        available_combos = min(possible_combos_list) if possible_combos_list else Decimal("0.00")

        return ComboResponse(
            id=combo.id,
            tenant_id=combo.tenant_id,
            name=combo.name,
            description=combo.description,
            price_mxn=combo.price_mxn,
            sku=combo.sku,
            barcode=combo.barcode,
            image_url=combo.image_url,
            is_active=combo.is_active,
            available_combos=available_combos,
            items=items_response,
            created_at=combo.created_at,
            updated_at=combo.updated_at,
        )

    # -------------------------------------------------------------------------
    # GESTIÓN DE PRODUCTOS (3 CAMPOS VITALES Y CRUD)
    # -------------------------------------------------------------------------

    async def create_product_vital(
        self, data: ProductCreateVital, current_user: User
    ) -> ProductResponse:
        """
        Registra un producto utilizando el Formulario Minimalista de 3 Campos Vitales (SR-08):
        1. name (Nombre)
        2. price_mxn (Precio en Pesos Mexicanos)
        3. initial_stock (Existencias iniciales)
        """
        tenant_id = current_user.tenant_id
        await set_tenant_context(self.db, tenant_id)

        # 1. Validar o asignar categoría 'General'
        category_id = data.category_id
        if category_id is None:
            default_category = await self.category_repo.get_or_create_default(tenant_id)
            category_id = default_category.id
        else:
            category = await self.category_repo.get_by_id(category_id)
            if not category or category.tenant_id != tenant_id:
                raise NotFoundException(f"La categoría con ID '{category_id}' no existe.")

        # 2. Validar o asignar almacén principal
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

        # 5. Inserción atómica del producto y de sus existencias iniciales
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

        # 6. Registrar asiento inicial en Kardex si initial_stock > 0
        if data.initial_stock > Decimal("0.00"):
            await self.movement_repo.record_movement(
                tenant_id=tenant_id,
                product_id=created_product.id,
                warehouse_id=warehouse_id,
                movement_type=MovementType.ADJUSTMENT_IN,
                quantity=data.initial_stock,
                previous_stock=Decimal("0.00"),
                new_stock=data.initial_stock,
                unit_cost_mxn=data.cost_mxn or Decimal("0.00"),
                user_id=current_user.id,
                notes="Inventario inicial registrado en alta de producto",
            )

        await self.db.commit()

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
        tenant_id = current_user.tenant_id
        await set_tenant_context(self.db, tenant_id)

        products = await self.product_repo.list_products(
            tenant_id=tenant_id,
            category_id=category_id,
            is_active=is_active,
            query=query,
            skip=skip,
            limit=limit,
        )

        responses = [self._build_product_response(p) for p in products]

        if is_low_stock is True:
            responses = [r for r in responses if r.is_low_stock]

        return responses

    async def get_product_by_id(
        self, product_id: uuid.UUID, current_user: User
    ) -> ProductResponse:
        tenant_id = current_user.tenant_id
        await set_tenant_context(self.db, tenant_id)

        product = await self.product_repo.get_by_id(product_id)
        if not product or product.tenant_id != tenant_id:
            raise NotFoundException(f"Producto con ID '{product_id}' no encontrado.")

        return self._build_product_response(product)

    async def update_product(
        self, product_id: uuid.UUID, data: ProductUpdate, current_user: User
    ) -> ProductResponse:
        tenant_id = current_user.tenant_id
        await set_tenant_context(self.db, tenant_id)

        product = await self.product_repo.get_by_id(product_id)
        if not product or product.tenant_id != tenant_id:
            raise NotFoundException(f"Producto con ID '{product_id}' no encontrado.")

        if data.sku is not None:
            clean_sku = data.sku.strip()
            if clean_sku != product.sku:
                existing_sku = await self.product_repo.get_by_sku(clean_sku, tenant_id)
                if existing_sku and existing_sku.id != product_id:
                    raise ConflictException(f"El código SKU '{clean_sku}' ya está en uso por otro producto.")

        if data.barcode is not None:
            clean_barcode = data.barcode.strip()
            if clean_barcode != product.barcode:
                existing_barcode = await self.product_repo.get_by_barcode(clean_barcode, tenant_id)
                if existing_barcode and existing_barcode.id != product_id:
                    raise ConflictException(f"El código de barras '{clean_barcode}' ya está en uso.")

        if data.category_id is not None:
            category = await self.category_repo.get_by_id(data.category_id)
            if not category or category.tenant_id != tenant_id:
                raise NotFoundException(f"La categoría con ID '{data.category_id}' no existe.")

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

        await self.db.commit()

        await set_tenant_context(self.db, tenant_id)
        reloaded = await self.product_repo.get_by_id(product.id)
        if not reloaded:
            raise NotFoundException("Error al recargar el producto actualizado.")

        return self._build_product_response(reloaded)

    async def delete_product(self, product_id: uuid.UUID, current_user: User) -> None:
        tenant_id = current_user.tenant_id
        await set_tenant_context(self.db, tenant_id)

        product = await self.product_repo.get_by_id(product_id)
        if not product or product.tenant_id != tenant_id:
            raise NotFoundException(f"Producto con ID '{product_id}' no encontrado.")

        await self.product_repo.delete(product)
        await self.db.commit()

    # -------------------------------------------------------------------------
    # GESTIÓN DE COMBOS / PROMOCIONES (RF-03)
    # -------------------------------------------------------------------------

    async def create_combo(self, data: ComboCreate, current_user: User) -> ComboResponse:
        """
        Crea una nueva promoción o combo en Pesos Mexicanos (RF-03).
        Valida que todos los productos componentes existan y pertenezcan al tenant.
        """
        tenant_id = current_user.tenant_id
        await set_tenant_context(self.db, tenant_id)

        # 1. Validar que cada producto componente pertenezca al comercio
        for item in data.items:
            prod = await self.product_repo.get_by_id(item.product_id)
            if not prod or prod.tenant_id != tenant_id:
                raise NotFoundException(f"El producto componente con ID '{item.product_id}' no existe en tu catálogo.")

        # 2. Generar o validar SKU del combo
        if data.sku:
            clean_sku = data.sku.strip()
            existing_sku = await self.combo_repo.get_by_sku(clean_sku, tenant_id)
            if existing_sku:
                raise ConflictException(f"El código SKU '{clean_sku}' ya está registrado para otro combo.")
            final_sku = clean_sku
        else:
            final_sku = await self.product_repo.generate_unique_sku(tenant_id)

        # 3. Validar código de barras si fue provisto
        final_barcode = data.barcode.strip() if data.barcode else None
        if final_barcode:
            existing_barcode = await self.combo_repo.get_by_barcode(final_barcode, tenant_id)
            if existing_barcode:
                raise ConflictException(f"El código de barras '{final_barcode}' ya existe en la promoción '{existing_barcode.name}'.")

        # 4. Crear el combo y sus ítems
        combo = await self.combo_repo.create(
            tenant_id=tenant_id,
            name=data.name.strip(),
            price_mxn=data.price_mxn,
            sku=final_sku,
            items_data=data.items,
            description=data.description.strip() if data.description else None,
            barcode=final_barcode,
            image_url=data.image_url,
            is_active=True,
        )

        await self.db.commit()

        # Recargar con relaciones
        await set_tenant_context(self.db, tenant_id)
        reloaded = await self.combo_repo.get_by_id(combo.id)
        if not reloaded:
            raise NotFoundException("Error al recargar el combo recién creado.")

        return self._build_combo_response(reloaded)

    async def list_combos(
        self, current_user: User, is_active: Optional[bool] = None, skip: int = 0, limit: int = 100
    ) -> List[ComboResponse]:
        """
        Retorna la lista de combos del comercio con cálculo de paquetes disponibles.
        """
        tenant_id = current_user.tenant_id
        await set_tenant_context(self.db, tenant_id)

        combos = await self.combo_repo.list_by_tenant(
            tenant_id=tenant_id, is_active=is_active, skip=skip, limit=limit
        )
        return [self._build_combo_response(c) for c in combos]

    async def get_combo_by_id(self, combo_id: uuid.UUID, current_user: User) -> ComboResponse:
        """
        Obtiene el detalle de un combo por su UUID.
        """
        tenant_id = current_user.tenant_id
        await set_tenant_context(self.db, tenant_id)

        combo = await self.combo_repo.get_by_id(combo_id)
        if not combo or combo.tenant_id != tenant_id:
            raise NotFoundException(f"Combo con ID '{combo_id}' no encontrado.")

        return self._build_combo_response(combo)

    async def update_combo(
        self, combo_id: uuid.UUID, data: ComboUpdate, current_user: User
    ) -> ComboResponse:
        """
        Actualiza los datos o la composición de productos de un combo.
        """
        tenant_id = current_user.tenant_id
        await set_tenant_context(self.db, tenant_id)

        combo = await self.combo_repo.get_by_id(combo_id)
        if not combo or combo.tenant_id != tenant_id:
            raise NotFoundException(f"Combo con ID '{combo_id}' no encontrado.")

        # Validar componentes si se actualizan
        if data.items is not None:
            for item in data.items:
                prod = await self.product_repo.get_by_id(item.product_id)
                if not prod or prod.tenant_id != tenant_id:
                    raise NotFoundException(f"El producto componente '{item.product_id}' no existe.")

        await self.combo_repo.update(
            combo=combo,
            name=data.name.strip() if data.name else None,
            description=data.description.strip() if data.description else None,
            price_mxn=data.price_mxn,
            sku=data.sku.strip() if data.sku else None,
            barcode=data.barcode.strip() if data.barcode else None,
            image_url=data.image_url,
            is_active=data.is_active,
            items_data=data.items,
        )

        await self.db.commit()

        await set_tenant_context(self.db, tenant_id)
        reloaded = await self.combo_repo.get_by_id(combo.id)
        return self._build_combo_response(reloaded)

    async def delete_combo(self, combo_id: uuid.UUID, current_user: User) -> None:
        """
        Elimina físicamente un combo del catálogo.
        """
        tenant_id = current_user.tenant_id
        await set_tenant_context(self.db, tenant_id)

        combo = await self.combo_repo.get_by_id(combo_id)
        if not combo or combo.tenant_id != tenant_id:
            raise NotFoundException(f"Combo con ID '{combo_id}' no encontrado.")

        await self.combo_repo.delete(combo)
        await self.db.commit()

    # -------------------------------------------------------------------------
    # OPERACIONES DE ALMACÉN, AJUSTES Y TRASLADOS (RF-05, RF-07)
    # -------------------------------------------------------------------------

    async def adjust_stock(
        self, data: StockAdjustmentCreate, current_user: User
    ) -> InventoryMovementResponse:
        """
        Ajuste físico manual de existencias (+ Entrada / - Salida o Merma).
        Garantiza consistencia ACID y genera un asiento inmutable en el Kardex (Const. Art. 7.1).
        """
        tenant_id = current_user.tenant_id
        await set_tenant_context(self.db, tenant_id)

        # 1. Validar producto
        product = await self.product_repo.get_by_id(data.product_id)
        if not product or product.tenant_id != tenant_id:
            raise NotFoundException(f"Producto con ID '{data.product_id}' no encontrado.")

        # 2. Validar almacén
        warehouse = await self.warehouse_repo.get_by_id(data.warehouse_id)
        if not warehouse or warehouse.tenant_id != tenant_id:
            raise NotFoundException(f"Almacén con ID '{data.warehouse_id}' no encontrado.")

        # 3. Buscar o inicializar registro de existencias en el almacén
        stmt = select(ProductStock).where(
            ProductStock.tenant_id == tenant_id,
            ProductStock.product_id == data.product_id,
            ProductStock.warehouse_id == data.warehouse_id,
        )
        res = await self.db.execute(stmt)
        stock = res.scalar_one_or_none()

        if not stock:
            stock = ProductStock(
                id=uuid.uuid4(),
                tenant_id=tenant_id,
                product_id=data.product_id,
                warehouse_id=data.warehouse_id,
                current_stock=Decimal("0.00"),
                reserved_stock=Decimal("0.00"),
            )
            self.db.add(stock)
            await self.db.flush()

        previous_stock = stock.current_stock
        new_stock = previous_stock + data.quantity

        # Impedir existencias negativas
        if new_stock < Decimal("0.00"):
            raise BadRequestException(
                f"El ajuste solicitado provocaría existencias negativas ({new_stock} piezas). "
                f"Existencias actuales en almacén: {previous_stock} piezas."
            )

        # Actualizar existencias
        stock.current_stock = new_stock

        # Determinar tipo de movimiento
        if data.movement_type:
            m_type = data.movement_type
        else:
            m_type = MovementType.ADJUSTMENT_IN if data.quantity > Decimal("0.00") else MovementType.ADJUSTMENT_OUT

        unit_cost = data.unit_cost_mxn if data.unit_cost_mxn is not None else product.cost_mxn

        # 4. Asiento inmutable en Kardex
        movement = await self.movement_repo.record_movement(
            tenant_id=tenant_id,
            product_id=data.product_id,
            warehouse_id=data.warehouse_id,
            movement_type=m_type,
            quantity=data.quantity,
            previous_stock=previous_stock,
            new_stock=new_stock,
            unit_cost_mxn=unit_cost,
            user_id=current_user.id,
            notes=data.notes,
        )

        await self.db.commit()

        return InventoryMovementResponse(
            id=movement.id,
            tenant_id=movement.tenant_id,
            product_id=movement.product_id,
            product_name=product.name,
            warehouse_id=movement.warehouse_id,
            warehouse_name=warehouse.name,
            from_warehouse_id=None,
            to_warehouse_id=None,
            user_id=movement.user_id,
            movement_type=movement.movement_type,
            quantity=movement.quantity,
            previous_stock=movement.previous_stock,
            new_stock=movement.new_stock,
            unit_cost_mxn=movement.unit_cost_mxn,
            reference_id=movement.reference_id,
            notes=movement.notes,
            created_at=movement.created_at,
        )

    async def transfer_stock(
        self, data: StockTransferCreate, current_user: User
    ) -> List[InventoryMovementResponse]:
        """
        Traslado atómico de existencias entre dos almacenes del mismo comercio (RF-07).
        Genera un doble asiento en Kardex: TRANSFER_OUT en origen y TRANSFER_IN en destino.
        """
        tenant_id = current_user.tenant_id
        await set_tenant_context(self.db, tenant_id)

        # 1. Validar producto
        product = await self.product_repo.get_by_id(data.product_id)
        if not product or product.tenant_id != tenant_id:
            raise NotFoundException(f"Producto con ID '{data.product_id}' no encontrado.")

        # 2. Validar almacenes origen y destino
        from_wh = await self.warehouse_repo.get_by_id(data.from_warehouse_id)
        if not from_wh or from_wh.tenant_id != tenant_id:
            raise NotFoundException(f"Almacén origen con ID '{data.from_warehouse_id}' no encontrado.")

        to_wh = await self.warehouse_repo.get_by_id(data.to_warehouse_id)
        if not to_wh or to_wh.tenant_id != tenant_id:
            raise NotFoundException(f"Almacén destino con ID '{data.to_warehouse_id}' no encontrado.")

        # 3. Validar existencias disponibles en almacén origen
        stmt_from = select(ProductStock).where(
            ProductStock.tenant_id == tenant_id,
            ProductStock.product_id == data.product_id,
            ProductStock.warehouse_id == data.from_warehouse_id,
        )
        res_from = await self.db.execute(stmt_from)
        stock_from = res_from.scalar_one_or_none()

        available_in_origin = (stock_from.current_stock - stock_from.reserved_stock) if stock_from else Decimal("0.00")
        if available_in_origin < data.quantity:
            raise BadRequestException(
                f"Existencias insuficientes en almacén '{from_wh.name}'. "
                f"Disponible para transferir: {available_in_origin}, Solicitado: {data.quantity}"
            )

        # 4. Obtener o crear existencias en almacén destino
        stmt_to = select(ProductStock).where(
            ProductStock.tenant_id == tenant_id,
            ProductStock.product_id == data.product_id,
            ProductStock.warehouse_id == data.to_warehouse_id,
        )
        res_to = await self.db.execute(stmt_to)
        stock_to = res_to.scalar_one_or_none()

        if not stock_to:
            stock_to = ProductStock(
                id=uuid.uuid4(),
                tenant_id=tenant_id,
                product_id=data.product_id,
                warehouse_id=data.to_warehouse_id,
                current_stock=Decimal("0.00"),
                reserved_stock=Decimal("0.00"),
            )
            self.db.add(stock_to)
            await self.db.flush()

        # 5. Mutación de saldos
        from_prev = stock_from.current_stock
        from_new = from_prev - data.quantity
        stock_from.current_stock = from_new

        to_prev = stock_to.current_stock
        to_new = to_prev + data.quantity
        stock_to.current_stock = to_new

        transfer_ref_id = uuid.uuid4()

        # 6. Asiento contable de Salida (TRANSFER_OUT)
        mov_out = await self.movement_repo.record_movement(
            tenant_id=tenant_id,
            product_id=data.product_id,
            warehouse_id=data.from_warehouse_id,
            from_warehouse_id=data.from_warehouse_id,
            to_warehouse_id=data.to_warehouse_id,
            movement_type=MovementType.TRANSFER_OUT,
            quantity=-data.quantity,
            previous_stock=from_prev,
            new_stock=from_new,
            unit_cost_mxn=product.cost_mxn,
            user_id=current_user.id,
            reference_id=transfer_ref_id,
            notes=data.notes or f"Traslado hacia {to_wh.name}",
        )

        # 7. Asiento contable de Entrada (TRANSFER_IN)
        mov_in = await self.movement_repo.record_movement(
            tenant_id=tenant_id,
            product_id=data.product_id,
            warehouse_id=data.to_warehouse_id,
            from_warehouse_id=data.from_warehouse_id,
            to_warehouse_id=data.to_warehouse_id,
            movement_type=MovementType.TRANSFER_IN,
            quantity=data.quantity,
            previous_stock=to_prev,
            new_stock=to_new,
            unit_cost_mxn=product.cost_mxn,
            user_id=current_user.id,
            reference_id=transfer_ref_id,
            notes=data.notes or f"Recepción desde {from_wh.name}",
        )

        await self.db.commit()

        return [
            InventoryMovementResponse(
                id=mov_out.id,
                tenant_id=tenant_id,
                product_id=product.id,
                product_name=product.name,
                warehouse_id=from_wh.id,
                warehouse_name=from_wh.name,
                from_warehouse_id=from_wh.id,
                to_warehouse_id=to_wh.id,
                user_id=current_user.id,
                movement_type=mov_out.movement_type,
                quantity=mov_out.quantity,
                previous_stock=mov_out.previous_stock,
                new_stock=mov_out.new_stock,
                unit_cost_mxn=mov_out.unit_cost_mxn,
                reference_id=transfer_ref_id,
                notes=mov_out.notes,
                created_at=mov_out.created_at,
            ),
            InventoryMovementResponse(
                id=mov_in.id,
                tenant_id=tenant_id,
                product_id=product.id,
                product_name=product.name,
                warehouse_id=to_wh.id,
                warehouse_name=to_wh.name,
                from_warehouse_id=from_wh.id,
                to_warehouse_id=to_wh.id,
                user_id=current_user.id,
                movement_type=mov_in.movement_type,
                quantity=mov_in.quantity,
                previous_stock=mov_in.previous_stock,
                new_stock=mov_in.new_stock,
                unit_cost_mxn=mov_in.unit_cost_mxn,
                reference_id=transfer_ref_id,
                notes=mov_in.notes,
                created_at=mov_in.created_at,
            ),
        ]

    # -------------------------------------------------------------------------
    # CONSULTA DE KARDEX INMUTABLE (RF-05)
    # -------------------------------------------------------------------------

    async def list_movements(
        self,
        current_user: User,
        product_id: Optional[uuid.UUID] = None,
        warehouse_id: Optional[uuid.UUID] = None,
        movement_type: Optional[MovementType] = None,
        skip: int = 0,
        limit: int = 100,
    ) -> List[InventoryMovementResponse]:
        """
        Consulta el historial de movimientos de inventario con filtros de auditoría.
        """
        tenant_id = current_user.tenant_id
        await set_tenant_context(self.db, tenant_id)

        movements = await self.movement_repo.list_movements(
            tenant_id=tenant_id,
            product_id=product_id,
            warehouse_id=warehouse_id,
            movement_type=movement_type,
            skip=skip,
            limit=limit,
        )

        return [
            InventoryMovementResponse(
                id=m.id,
                tenant_id=m.tenant_id,
                product_id=m.product_id,
                product_name=m.product.name if m.product else "Desconocido",
                warehouse_id=m.warehouse_id,
                warehouse_name=m.warehouse.name if m.warehouse else "Desconocido",
                from_warehouse_id=m.from_warehouse_id,
                to_warehouse_id=m.to_warehouse_id,
                user_id=m.user_id,
                movement_type=m.movement_type,
                quantity=m.quantity,
                previous_stock=m.previous_stock,
                new_stock=m.new_stock,
                unit_cost_mxn=m.unit_cost_mxn,
                reference_id=m.reference_id,
                notes=m.notes,
                created_at=m.created_at,
            )
            for m in movements
        ]

    # -------------------------------------------------------------------------
    # GESTIÓN DE APARTADOS / STOCK RESERVADO TTL 15 MIN (RF-06)
    # -------------------------------------------------------------------------

    async def create_reservation(
        self, data: StockReservationCreate, current_user: User
    ) -> StockReservationResponse:
        """
        Crea un apartado temporal de existencias (TTL de 15 min).
        Evita colisiones de venta entre cajeros en mostrador (RF-06).
        """
        tenant_id = current_user.tenant_id
        await set_tenant_context(self.db, tenant_id)

        # 1. Validar producto
        product = await self.product_repo.get_by_id(data.product_id)
        if not product or product.tenant_id != tenant_id:
            raise NotFoundException(f"Producto con ID '{data.product_id}' no encontrado.")

        # 2. Validar existencias disponibles en el almacén
        stmt = select(ProductStock).where(
            ProductStock.tenant_id == tenant_id,
            ProductStock.product_id == data.product_id,
            ProductStock.warehouse_id == data.warehouse_id,
        )
        res = await self.db.execute(stmt)
        stock = res.scalar_one_or_none()

        available_stock = (stock.current_stock - stock.reserved_stock) if stock else Decimal("0.00")
        if available_stock < data.quantity:
            raise BadRequestException(
                f"Existencias insuficientes para apartar. Disponible: {available_stock}, Solicitado: {data.quantity}"
            )

        # 3. Incrementar existencias reservadas
        stock.reserved_stock += data.quantity

        # 4. Calcular estampa de tiempo de expiración TTL
        expires_at = datetime.now(timezone.utc) + timedelta(minutes=data.ttl_minutes)

        # 5. Registrar reserva
        reservation = await self.reservation_repo.create(
            tenant_id=tenant_id,
            product_id=data.product_id,
            warehouse_id=data.warehouse_id,
            quantity=data.quantity,
            expires_at=expires_at,
            reference_id=data.reference_id,
        )

        # 6. Registrar asiento de retención en Kardex
        await self.movement_repo.record_movement(
            tenant_id=tenant_id,
            product_id=data.product_id,
            warehouse_id=data.warehouse_id,
            movement_type=MovementType.RESERVATION_HOLD,
            quantity=data.quantity,
            previous_stock=stock.current_stock,
            new_stock=stock.current_stock,
            unit_cost_mxn=product.cost_mxn,
            user_id=current_user.id,
            reference_id=reservation.id,
            notes=f"Apartado temporal (TTL {data.ttl_minutes} min)",
        )

        await self.db.commit()

        return StockReservationResponse(
            id=reservation.id,
            tenant_id=reservation.tenant_id,
            product_id=reservation.product_id,
            product_name=product.name,
            warehouse_id=reservation.warehouse_id,
            quantity=reservation.quantity,
            status=reservation.status,
            reference_id=reservation.reference_id,
            expires_at=reservation.expires_at,
            created_at=reservation.created_at,
        )

    async def release_reservation(
        self, reservation_id: uuid.UUID, current_user: User
    ) -> StockReservationResponse:
        """
        Libera explícitamente un apartado activo (ej. cancelación de venta en carrito).
        """
        tenant_id = current_user.tenant_id
        await set_tenant_context(self.db, tenant_id)

        reservation = await self.reservation_repo.get_by_id(reservation_id)
        if not reservation or reservation.tenant_id != tenant_id:
            raise NotFoundException(f"Reserva con ID '{reservation_id}' no encontrada.")

        if reservation.status != ReservationStatus.PENDING:
            raise BadRequestException(f"La reserva ya se encuentra en estado '{reservation.status.value}'.")

        # Revertir existencias reservadas
        stmt = select(ProductStock).where(
            ProductStock.tenant_id == tenant_id,
            ProductStock.product_id == reservation.product_id,
            ProductStock.warehouse_id == reservation.warehouse_id,
        )
        res = await self.db.execute(stmt)
        stock = res.scalar_one_or_none()
        if stock:
            stock.reserved_stock = max(Decimal("0.00"), stock.reserved_stock - reservation.quantity)

        # Actualizar estado a RELEASED
        await self.reservation_repo.update_status(reservation, ReservationStatus.RELEASED)

        # Registrar asiento en Kardex
        await self.movement_repo.record_movement(
            tenant_id=tenant_id,
            product_id=reservation.product_id,
            warehouse_id=reservation.warehouse_id,
            movement_type=MovementType.RESERVATION_RELEASE,
            quantity=-reservation.quantity,
            previous_stock=stock.current_stock if stock else Decimal("0.00"),
            new_stock=stock.current_stock if stock else Decimal("0.00"),
            unit_cost_mxn=Decimal("0.00"),
            user_id=current_user.id,
            reference_id=reservation.id,
            notes="Liberación manual de apartado de stock",
        )

        await self.db.commit()

        return StockReservationResponse(
            id=reservation.id,
            tenant_id=reservation.tenant_id,
            product_id=reservation.product_id,
            product_name=reservation.product.name if reservation.product else "Desconocido",
            warehouse_id=reservation.warehouse_id,
            quantity=reservation.quantity,
            status=reservation.status,
            reference_id=reservation.reference_id,
            expires_at=reservation.expires_at,
            created_at=reservation.created_at,
        )

    async def cleanup_expired_reservations(self) -> int:
        """
        Worker / Cron job para liberar automáticamente apartados cuyo TTL de 15 min ha expirado (RF-06).
        """
        now = datetime.now(timezone.utc)
        expired_list = await self.reservation_repo.get_expired_pending(now)
        count = 0

        for r in expired_list:
            await set_tenant_context(self.db, r.tenant_id)

            # Revertir stock reservado
            stmt = select(ProductStock).where(
                ProductStock.tenant_id == r.tenant_id,
                ProductStock.product_id == r.product_id,
                ProductStock.warehouse_id == r.warehouse_id,
            )
            res = await self.db.execute(stmt)
            stock = res.scalar_one_or_none()
            if stock:
                stock.reserved_stock = max(Decimal("0.00"), stock.reserved_stock - r.quantity)

            # Marcar como EXPIRED
            await self.reservation_repo.update_status(r, ReservationStatus.EXPIRED)

            # Registrar en Kardex
            await self.movement_repo.record_movement(
                tenant_id=r.tenant_id,
                product_id=r.product_id,
                warehouse_id=r.warehouse_id,
                movement_type=MovementType.RESERVATION_RELEASE,
                quantity=-r.quantity,
                previous_stock=stock.current_stock if stock else Decimal("0.00"),
                new_stock=stock.current_stock if stock else Decimal("0.00"),
                unit_cost_mxn=Decimal("0.00"),
                user_id=None,
                reference_id=r.id,
                notes="Liberación automática por expiración de TTL (15 min)",
            )
            count += 1

        if count > 0:
            await self.db.commit()

        return count

    # -------------------------------------------------------------------------
    # GESTIÓN DE CATEGORÍAS Y ALMACENES
    # -------------------------------------------------------------------------

    async def list_categories(self, current_user: User) -> List[CategoryResponse]:
        tenant_id = current_user.tenant_id
        await set_tenant_context(self.db, tenant_id)
        categories = await self.category_repo.list_by_tenant(tenant_id)
        return [CategoryResponse.model_validate(c) for c in categories]

    async def create_category(
        self, data: CategoryCreate, current_user: User
    ) -> CategoryResponse:
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

    async def list_warehouses(self, current_user: User) -> List[WarehouseResponse]:
        tenant_id = current_user.tenant_id
        await set_tenant_context(self.db, tenant_id)
        warehouses = await self.warehouse_repo.list_by_tenant(tenant_id)
        return [WarehouseResponse.model_validate(w) for w in warehouses]

    async def create_warehouse(
        self, data: WarehouseCreate, current_user: User
    ) -> WarehouseResponse:
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

    # -------------------------------------------------------------------------
    # CONSULTA ULTRA-RÁPIDA DE CATÁLOGO SEMILLA EAN-13 (RF-29 / Const. Art. 7.5)
    # -------------------------------------------------------------------------

    async def lookup_ean(self, barcode: str) -> EanLookupResponse:
        """
        Consulta instantánea (< 5ms) en el Catálogo Semilla Maestro EAN-13 México (Tier 1).
        Permite autocompletar la ficha técnica (nombre, marca, categoría, precio sugerido)
        al escanear un código de barras en el punto de venta o en modo góndola.
        """
        # Limpieza del código de barras
        clean_barcode = barcode.strip()
        # Búsqueda indexada en base de datos
        seed_item = await self.seed_product_repo.get_by_barcode(clean_barcode)

        # Si no existe en el catálogo semilla oficial
        if not seed_item:
            return EanLookupResponse(found=False, product=None)

        # Si fue encontrado, retornar ficha serializada
        return EanLookupResponse(
            found=True,
            product=SeedProductResponse.model_validate(seed_item),
        )

    # -------------------------------------------------------------------------
    # IMPORTADOR FLEXIBLE DE INVENTARIO EXCEL / CSV (RF-01 / Const. Art. 1.2.8)
    # -------------------------------------------------------------------------

    def _parse_tabular_data(
        self, file_bytes: bytes, filename: str
    ) -> Tuple[List[str], List[Dict[str, Any]], int]:
        """
        Lector utilitario agnóstico de formatos (.xlsx y .csv) con detección
        automática de encabezados y lectura de filas en memoria.
        """
        headers: List[str] = []
        all_rows: List[Dict[str, Any]] = []

        # 1. Procesamiento de archivos Excel (.xlsx)
        if filename.lower().endswith((".xlsx", ".xlsm", ".xltx")):
            wb = openpyxl.load_workbook(io.BytesIO(file_bytes), read_only=True, data_only=True)
            sheet = wb.active
            iter_rows = sheet.iter_rows(values_only=True)

            # Buscar primera fila no vacía como encabezados
            raw_headers = None
            for row in iter_rows:
                if row and any(cell is not None and str(cell).strip() != "" for cell in row):
                    raw_headers = [str(c).strip() if c is not None else f"Columna_{i+1}" for i, c in enumerate(row)]
                    break

            if not raw_headers:
                raise BadRequestException("El archivo Excel está vacío o no contiene encabezados válidos.")

            headers = raw_headers

            # Leer filas restantes
            for row in iter_rows:
                if not row or not any(cell is not None and str(cell).strip() != "" for cell in row):
                    continue
                row_dict = {}
                for idx, col_name in enumerate(headers):
                    val = row[idx] if idx < len(row) else None
                    row_dict[col_name] = val
                all_rows.append(row_dict)

            wb.close()

        # 2. Procesamiento de archivos CSV (.csv)
        elif filename.lower().endswith(".csv"):
            try:
                content_str = file_bytes.decode("utf-8-sig")
            except UnicodeDecodeError:
                content_str = file_bytes.decode("latin-1")

            # Detectar delimitador (, o ;)
            sample_line = content_str[:2048]
            delimiter = ";" if sample_line.count(";") > sample_line.count(",") else ","

            reader = csv.reader(io.StringIO(content_str), delimiter=delimiter)
            raw_headers = None
            for row in reader:
                if row and any(cell.strip() != "" for cell in row):
                    raw_headers = [c.strip() if c.strip() != "" else f"Columna_{i+1}" for i, c in enumerate(row)]
                    break

            if not raw_headers:
                raise BadRequestException("El archivo CSV está vacío o no contiene encabezados válidos.")

            headers = raw_headers

            for row in reader:
                if not row or not any(cell.strip() != "" for cell in row):
                    continue
                row_dict = {}
                for idx, col_name in enumerate(headers):
                    val = row[idx] if idx < len(row) else ""
                    row_dict[col_name] = val
                all_rows.append(row_dict)

        else:
            raise BadRequestException("Formato no soportado. Solo se admiten archivos Excel (.xlsx) o CSV (.csv).")

        return headers, all_rows, len(all_rows)

    def _clean_numeric(self, val: Any) -> Optional[Decimal]:
        """
        Limpia y sanitiza cadenas numéricas convirtiendo formatos como '$ 1,234.50' a Decimal.
        """
        if val is None:
            return None
        if isinstance(val, (int, float, Decimal)):
            return Decimal(str(val))

        s = str(val).strip()
        if not s:
            return None

        # Eliminar signos de moneda, comas y espacios
        cleaned = re.sub(r"[^0-9.-]", "", s)
        try:
            return Decimal(cleaned)
        except Exception:
            return None

    def _generate_heuristic_mapping(self, headers: List[str]) -> Dict[str, str]:
        """
        Genera sugerencias automáticas de mapeo de columnas analizando nombres habituales.
        """
        mapping: Dict[str, str] = {}
        for h in headers:
            h_norm = h.lower()
            if any(k in h_norm for k in ["nombre", "descripcion", "producto", "articulo", "item"]) and "name_column" not in mapping:
                mapping["name_column"] = h
            elif any(k in h_norm for k in ["precio", "venta", "p.vta", "publico", "pvp"]) and "price_column" not in mapping:
                mapping["price_column"] = h
            elif any(k in h_norm for k in ["stock", "existencia", "cantidad", "cant", "unidades", "inv"]) and "stock_column" not in mapping:
                mapping["stock_column"] = h
            elif any(k in h_norm for k in ["costo", "compra", "pc", "cost"]) and "cost_column" not in mapping:
                mapping["cost_column"] = h
            elif any(k in h_norm for k in ["codigo", "barra", "barcode", "ean", "upc"]) and "barcode_column" not in mapping:
                mapping["barcode_column"] = h
            elif any(k in h_norm for k in ["categoria", "familia", "depto", "departamento", "linea", "rubro"]) and "category_column" not in mapping:
                mapping["category_column"] = h
            elif any(k in h_norm for k in ["sku", "clave", "cod_int", "ref"]) and "sku_column" not in mapping:
                mapping["sku_column"] = h
        return mapping

    async def preview_import(self, file_bytes: bytes, filename: str) -> ImportPreviewResponse:
        """
        Previsualiza las primeras filas de un archivo Excel/CSV y sugiere mapeo visual (RF-01).
        """
        headers, all_rows, total_rows = self._parse_tabular_data(file_bytes, filename)
        sample_rows = all_rows[:5]
        suggested = self._generate_heuristic_mapping(headers)

        return ImportPreviewResponse(
            filename=filename,
            headers=headers,
            sample_rows=sample_rows,
            total_detected_rows=total_rows,
            suggested_mapping=suggested,
        )

    async def execute_import(
        self,
        file_bytes: bytes,
        filename: str,
        mapping: ColumnMapping,
        current_user: User,
    ) -> ImportExecutionResponse:
        """
        Ejecuta la ingesta masiva atómica por lotes en PostgreSQL RLS.
        Valida los 3 Campos Vitales (Nombre, Precio MXN, Stock) y autogenera SKUs y Kardex inicial (RF-01).
        """
        tenant_id = current_user.tenant_id
        await set_tenant_context(self.db, tenant_id)

        # 1. Parsear archivo tabular
        headers, all_rows, total_rows = self._parse_tabular_data(file_bytes, filename)

        # 2. Validar que las columnas mapeadas obligatorias existan en el archivo
        if mapping.name_column not in headers:
            raise BadRequestException(f"La columna de Nombre '{mapping.name_column}' no existe en el archivo.")
        if mapping.price_column not in headers:
            raise BadRequestException(f"La columna de Precio '{mapping.price_column}' no existe en el archivo.")
        if mapping.stock_column not in headers:
            raise BadRequestException(f"La columna de Existencias '{mapping.stock_column}' no existe en el archivo.")

        # 3. Obtener almacén principal predeterminado
        default_warehouse = await self.warehouse_repo.get_or_create_default(tenant_id)
        default_wh_id = default_warehouse.id

        # 4. Caché de categorías para evitar consultas redundantes
        category_cache: Dict[str, uuid.UUID] = {}
        default_cat = await self.category_repo.get_or_create_default(tenant_id)
        category_cache["general"] = default_cat.id

        imported_count = 0
        skipped_count = 0
        errors: List[ImportRowError] = []

        # 5. Iterar filas y procesar
        for idx, row in enumerate(all_rows, start=2):  # start=2 considerando fila 1 como encabezados
            # 5.1 Validar Nombre (Campo Vital 1)
            raw_name = row.get(mapping.name_column)
            if raw_name is None or str(raw_name).strip() == "":
                skipped_count += 1
                errors.append(ImportRowError(row_number=idx, reason="Nombre del producto vacío o ausente"))
                continue
            name = str(raw_name).strip()

            # 5.2 Validar Precio MXN (Campo Vital 2)
            raw_price = row.get(mapping.price_column)
            price_mxn = self._clean_numeric(raw_price)
            if price_mxn is None or price_mxn < Decimal("0.00"):
                skipped_count += 1
                errors.append(ImportRowError(row_number=idx, reason=f"Precio inválido o negativo: '{raw_price}'"))
                continue

            # 5.3 Validar Existencias Iniciales (Campo Vital 3)
            raw_stock = row.get(mapping.stock_column)
            stock_qty = self._clean_numeric(raw_stock)
            if stock_qty is None or stock_qty < Decimal("0.00"):
                stock_qty = Decimal("0.00")

            # 5.4 Costo en MXN opcional
            cost_mxn = Decimal("0.00")
            if mapping.cost_column and mapping.cost_column in row:
                parsed_cost = self._clean_numeric(row.get(mapping.cost_column))
                if parsed_cost and parsed_cost >= Decimal("0.00"):
                    cost_mxn = parsed_cost

            # 5.5 Código de barras opcional
            barcode = None
            if mapping.barcode_column and mapping.barcode_column in row:
                b_val = row.get(mapping.barcode_column)
                if b_val is not None and str(b_val).strip() != "":
                    clean_b = str(b_val).strip()
                    # Verificar si el código ya existe en el tenant
                    existing_b = await self.product_repo.get_by_barcode(clean_b, tenant_id)
                    if existing_b:
                        skipped_count += 1
                        errors.append(ImportRowError(row_number=idx, reason=f"Código de barras '{clean_b}' duplicado"))
                        continue
                    barcode = clean_b

            # 5.6 Categoría opcional
            cat_id = default_cat.id
            if mapping.category_column and mapping.category_column in row:
                c_val = row.get(mapping.category_column)
                if c_val is not None and str(c_val).strip() != "":
                    cat_name = str(c_val).strip()
                    cat_key = cat_name.lower()
                    if cat_key in category_cache:
                        cat_id = category_cache[cat_key]
                    else:
                        existing_cat = await self.category_repo.get_by_name(cat_name, tenant_id)
                        if existing_cat:
                            cat_id = existing_cat.id
                        else:
                            new_cat = await self.category_repo.create(tenant_id, cat_name)
                            cat_id = new_cat.id
                        category_cache[cat_key] = cat_id

            # 5.7 SKU opcional o autogenerado
            if mapping.sku_column and mapping.sku_column in row:
                s_val = row.get(mapping.sku_column)
                if s_val is not None and str(s_val).strip() != "":
                    clean_sku = str(s_val).strip()
                    existing_sku = await self.product_repo.get_by_sku(clean_sku, tenant_id)
                    if existing_sku:
                        final_sku = await self.product_repo.generate_unique_sku(tenant_id)
                    else:
                        final_sku = clean_sku
                else:
                    final_sku = await self.product_repo.generate_unique_sku(tenant_id)
            else:
                final_sku = await self.product_repo.generate_unique_sku(tenant_id)

            # 5.8 Inserción atómica del producto
            try:
                prod = await self.product_repo.create_with_stock(
                    tenant_id=tenant_id,
                    name=name,
                    price_mxn=price_mxn,
                    initial_stock=stock_qty,
                    warehouse_id=default_wh_id,
                    sku=final_sku,
                    cost_mxn=cost_mxn,
                    barcode=barcode,
                    category_id=cat_id,
                    min_stock_alert=Decimal("5.00"),
                    is_active=True,
                )

                # 5.9 Asiento inicial en Kardex si existencias > 0
                if stock_qty > Decimal("0.00"):
                    await self.movement_repo.record_movement(
                        tenant_id=tenant_id,
                        product_id=prod.id,
                        warehouse_id=default_wh_id,
                        movement_type=MovementType.ADJUSTMENT_IN,
                        quantity=stock_qty,
                        previous_stock=Decimal("0.00"),
                        new_stock=stock_qty,
                        unit_cost_mxn=cost_mxn,
                        user_id=current_user.id,
                        notes=f"Carga masiva desde archivo: {filename}",
                    )

                imported_count += 1
            except Exception as e:
                skipped_count += 1
                errors.append(ImportRowError(row_number=idx, reason=f"Error en persistencia: {str(e)}"))

        # 6. Commit de la transacción completa
        if imported_count > 0:
            await self.db.commit()

        status_text = "completed" if skipped_count == 0 else "partial"
        return ImportExecutionResponse(
            total_rows=total_rows,
            imported_count=imported_count,
            skipped_count=skipped_count,
            errors=errors,
            status=status_text,
        )
