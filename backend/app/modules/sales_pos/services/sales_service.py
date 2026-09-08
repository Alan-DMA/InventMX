# Importación de módulos matemáticos y decimales
from decimal import Decimal
# Importación de tipado estático
from typing import List, Optional, Tuple
# Importación de UUID
import uuid
# Importación de FastAPI HTTPException
from fastapi import HTTPException, status
# Importación de SQLAlchemy
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

# Importación de modelos de dominio
from app.modules.auth_tenancy.domain.user import User
from app.modules.inventory.domain import (
    Category,
    Combo,
    ComboItem,
    InventoryMovement,
    MovementType,
    Product,
    ProductStock,
    Warehouse,
)
from app.modules.inventory.repositories.product_repository import ProductRepository
from app.modules.sales_pos.domain.sale import Sale, SaleItem, SaleStatus
from app.modules.sales_pos.repositories.sale_repository import SaleRepository
from app.modules.sales_pos.schemas.sale import (
    SaleCheckoutRequest,
    SaleItemRequest,
    SaleItemResponse,
    SaleResponse,
)


class SalesService:
    """
    Servicio de Reglas de Negocio para el Núcleo Transaccional POS (RF-09, RF-12).
    Garantiza consistencia ACID, bloqueo por concurrencia (SELECT FOR UPDATE),
    congelamiento de costos históricos y creación orgánica de productos al vuelo.
    """

    def __init__(self, session: AsyncSession):
        # Sesión asíncrona de base de datos
        self.session = session
        # Repositorio de ventas
        self.sale_repo = SaleRepository(session)
        # Repositorio de productos
        self.product_repo = ProductRepository(session)

    async def _get_or_create_general_category(self, tenant_id: uuid.UUID) -> Category:
        """
        Obtiene la categoría por defecto 'General' o la crea si no existe para el inquilino.
        """
        query = (
            select(Category)
            .where(Category.tenant_id == tenant_id)
            .where(Category.name.ilike("General"))
        )
        res = await self.session.execute(query)
        cat = res.scalar_one_or_none()
        if not cat:
            cat = Category(
                tenant_id=tenant_id,
                name="General",
                description="Categoría por defecto para productos sin clasificación",
            )
            self.session.add(cat)
            await self.session.flush()
        return cat

    async def process_pos_checkout(
        self,
        request: SaleCheckoutRequest,
        current_user: User,
    ) -> SaleResponse:
        """
        Ejecuta el Checkout transaccional atómico en el Punto de Venta (RF-09, RF-12).
        1. Valida el almacén físico.
        2. Procesa cada partida (producto existente, producto al vuelo o combo).
        3. Bloquea stocks con SELECT ... FOR UPDATE para prevenir sobreventas concurrentes.
        4. Congela precios de venta y costos unitarios históricos en Pesos Mexicanos ($ MXN).
        5. Asienta movimientos inmutables en el Kardex (SALE_EXIT, ADJUSTMENT_IN).
        6. Genera folio consecutivo y persiste la venta.
        """
        tenant_id = current_user.tenant_id

        # 1. Validar existencia del almacén
        w_query = (
            select(Warehouse)
            .where(Warehouse.id == request.warehouse_id)
            .where(Warehouse.tenant_id == tenant_id)
        )
        w_res = await self.session.execute(w_query)
        warehouse = w_res.scalar_one_or_none()
        if not warehouse:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="El almacén especificado para la venta no existe o no pertenece al inquilino.",
            )

        sale_items_to_create: List[SaleItem] = []
        total_subtotal_mxn = Decimal("0.00")
        total_discount_mxn = request.discount_mxn or Decimal("0.00")
        total_cost_mxn = Decimal("0.00")

        # 2. Iterar cada partida del carrito
        for item_req in request.items:
            # -----------------------------------------------------------------
            # CASO A: Producto Creado Sobre la Marcha (Lazy Loading RF-09 / Const. Art. 7.3)
            # -----------------------------------------------------------------
            if item_req.is_on_the_fly or (item_req.product_id is None and item_req.combo_id is None):
                if not item_req.on_the_fly_name:
                    raise HTTPException(
                        status_code=status.HTTP_400_BAD_REQUEST,
                        detail="Para registrar un producto al vuelo se requiere el nombre del producto.",
                    )
                if item_req.unit_price_mxn is None or item_req.unit_price_mxn < 0:
                    raise HTTPException(
                        status_code=status.HTTP_400_BAD_REQUEST,
                        detail="Para registrar un producto al vuelo se requiere un precio de venta válido en MXN.",
                    )

                # Generar SKU sagrado único NEX-XXXXX
                new_sku = await self.product_repo.generate_unique_sku(tenant_id)
                # Resolver categoría General
                general_cat = await self._get_or_create_general_category(tenant_id)

                cost_mxn = item_req.on_the_fly_cost_mxn or Decimal("0.00")
                unit_price = item_req.unit_price_mxn

                # Crear nuevo producto en catálogo
                new_product = Product(
                    tenant_id=tenant_id,
                    sku=new_sku,
                    name=item_req.on_the_fly_name.strip(),
                    barcode=item_req.on_the_fly_barcode,
                    category_id=general_cat.id,
                    price_mxn=unit_price,
                    cost_mxn=cost_mxn,
                    is_active=True,
                )
                self.session.add(new_product)
                await self.session.flush()

                # Crear stock inicial suficiente para cubrir la venta actual
                initial_qty = item_req.quantity
                new_stock = ProductStock(
                    tenant_id=tenant_id,
                    product_id=new_product.id,
                    warehouse_id=warehouse.id,
                    current_stock=Decimal("0.000"), # Queda en 0 tras venderlo
                    reserved_stock=Decimal("0.000"),
                )
                self.session.add(new_stock)
                await self.session.flush()

                # Asiento 1: Entrada inicial de inventario orgánico al Kardex
                movement_in = InventoryMovement(
                    tenant_id=tenant_id,
                    product_id=new_product.id,
                    warehouse_id=warehouse.id,
                    user_id=current_user.id,
                    movement_type=MovementType.ADJUSTMENT_IN,
                    quantity=initial_qty,
                    previous_stock=Decimal("0.000"),
                    new_stock=initial_qty,
                    unit_cost_mxn=cost_mxn,
                    notes=f"Alta orgánica de producto al vuelo en venta POS ({new_product.name})",
                )
                self.session.add(movement_in)

                # Asiento 2: Salida por venta al Kardex
                movement_out = InventoryMovement(
                    tenant_id=tenant_id,
                    product_id=new_product.id,
                    warehouse_id=warehouse.id,
                    user_id=current_user.id,
                    movement_type=MovementType.SALE_EXIT,
                    quantity=-initial_qty,
                    previous_stock=initial_qty,
                    new_stock=Decimal("0.000"),
                    unit_cost_mxn=cost_mxn,
                    notes=f"Salida por cobro en mostrador de producto al vuelo ({new_product.name})",
                )
                self.session.add(movement_out)

                # Calcular montos de la partida
                item_subtotal = (unit_price * item_req.quantity).quantize(Decimal("0.01"))
                item_discount = item_req.discount_mxn or Decimal("0.00")
                item_total = max(Decimal("0.00"), item_subtotal - item_discount)
                item_total_cost = (cost_mxn * item_req.quantity).quantize(Decimal("0.01"))

                total_subtotal_mxn += item_subtotal
                total_cost_mxn += item_total_cost

                sale_item = SaleItem(
                    tenant_id=tenant_id,
                    product_id=new_product.id,
                    combo_id=None,
                    product_name=new_product.name,
                    product_sku=new_product.sku,
                    quantity=item_req.quantity,
                    unit_price_mxn=unit_price,
                    unit_cost_mxn=cost_mxn,
                    subtotal_mxn=item_subtotal,
                    discount_mxn=item_discount,
                    total_mxn=item_total,
                    is_on_the_fly=True,
                )
                sale_items_to_create.append(sale_item)

            # -----------------------------------------------------------------
            # CASO B: Venta de Combo Promocional
            # -----------------------------------------------------------------
            elif item_req.combo_id is not None:
                # Consultar combo con items y productos
                combo_query = (
                    select(Combo)
                    .options(
                        selectinload(Combo.items).selectinload(ComboItem.product)
                    )
                    .where(Combo.id == item_req.combo_id)
                    .where(Combo.tenant_id == tenant_id)
                )
                combo_res = await self.session.execute(combo_query)
                combo = combo_res.scalar_one_or_none()
                if not combo:
                    raise HTTPException(
                        status_code=status.HTTP_404_NOT_FOUND,
                        detail=f"El combo con ID {item_req.combo_id} no fue encontrado.",
                    )
                if not combo.is_active:
                    raise HTTPException(
                        status_code=status.HTTP_400_BAD_REQUEST,
                        detail=f"El combo '{combo.name}' está inactivo y no puede ser vendido.",
                    )

                unit_price = item_req.unit_price_mxn if item_req.unit_price_mxn is not None else combo.price_mxn
                combo_cost = Decimal("0.00")

                # Bloquear y descontar existencias de cada componente del combo
                for c_item in combo.items:
                    required_comp_qty = c_item.quantity * item_req.quantity

                    # Bloqueo a nivel de fila SELECT FOR UPDATE
                    stock_query = (
                        select(ProductStock)
                        .where(ProductStock.product_id == c_item.product_id)
                        .where(ProductStock.warehouse_id == warehouse.id)
                        .where(ProductStock.tenant_id == tenant_id)
                        .with_for_update()
                    )
                    stock_res = await self.session.execute(stock_query)
                    p_stock = stock_res.scalar_one_or_none()

                    available = (p_stock.current_stock - p_stock.reserved_stock) if p_stock else Decimal("0.000")
                    if available < required_comp_qty:
                        p_name = c_item.product.name if c_item.product else "Componente"
                        raise HTTPException(
                            status_code=status.HTTP_400_BAD_REQUEST,
                            detail=(
                                f"Stock insuficiente para armar el combo '{combo.name}'. "
                                f"El componente '{p_name}' requiere {required_comp_qty} pero solo hay {available} disponibles."
                            ),
                        )

                    # Descontar stock del componente
                    prev_stock = p_stock.current_stock
                    new_stk = prev_stock - required_comp_qty
                    p_stock.current_stock = new_stk

                    comp_cost = (c_item.product.cost_mxn or Decimal("0.00")) if c_item.product else Decimal("0.00")
                    combo_cost += (comp_cost * c_item.quantity)

                    # Asiento en Kardex por componente del combo
                    movement = InventoryMovement(
                        tenant_id=tenant_id,
                        product_id=c_item.product_id,
                        warehouse_id=warehouse.id,
                        user_id=current_user.id,
                        movement_type=MovementType.SALE_EXIT,
                        quantity=-required_comp_qty,
                        previous_stock=prev_stock,
                        new_stock=new_stk,
                        unit_cost_mxn=comp_cost,
                        notes=f"Salida por venta de combo '{combo.name}' ({c_item.quantity}x por combo)",
                    )
                    self.session.add(movement)

                item_subtotal = (unit_price * item_req.quantity).quantize(Decimal("0.01"))
                item_discount = item_req.discount_mxn or Decimal("0.00")
                item_total = max(Decimal("0.00"), item_subtotal - item_discount)
                item_total_cost = (combo_cost * item_req.quantity).quantize(Decimal("0.01"))

                total_subtotal_mxn += item_subtotal
                total_cost_mxn += item_total_cost

                sale_item = SaleItem(
                    tenant_id=tenant_id,
                    product_id=None,
                    combo_id=combo.id,
                    product_name=combo.name,
                    product_sku=combo.sku,
                    quantity=item_req.quantity,
                    unit_price_mxn=unit_price,
                    unit_cost_mxn=combo_cost,
                    subtotal_mxn=item_subtotal,
                    discount_mxn=item_discount,
                    total_mxn=item_total,
                    is_on_the_fly=False,
                )
                sale_items_to_create.append(sale_item)

            # -----------------------------------------------------------------
            # CASO C: Venta de Producto Estándar del Catálogo
            # -----------------------------------------------------------------
            else:
                p_query = (
                    select(Product)
                    .where(Product.id == item_req.product_id)
                    .where(Product.tenant_id == tenant_id)
                )
                p_res = await self.session.execute(p_query)
                product = p_res.scalar_one_or_none()
                if not product:
                    raise HTTPException(
                        status_code=status.HTTP_404_NOT_FOUND,
                        detail=f"El producto con ID {item_req.product_id} no fue encontrado.",
                    )
                if not product.is_active:
                    raise HTTPException(
                        status_code=status.HTTP_400_BAD_REQUEST,
                        detail=f"El producto '{product.name}' está inactivo y no puede ser vendido.",
                    )

                # Bloqueo a nivel de fila SELECT FOR UPDATE en el stock
                stock_query = (
                    select(ProductStock)
                    .where(ProductStock.product_id == product.id)
                    .where(ProductStock.warehouse_id == warehouse.id)
                    .where(ProductStock.tenant_id == tenant_id)
                    .with_for_update()
                )
                stock_res = await self.session.execute(stock_query)
                p_stock = stock_res.scalar_one_or_none()

                available = (p_stock.current_stock - p_stock.reserved_stock) if p_stock else Decimal("0.000")
                if available < item_req.quantity:
                    raise HTTPException(
                        status_code=status.HTTP_400_BAD_REQUEST,
                        detail=(
                            f"Stock insuficiente para '{product.name}'. "
                            f"Se solicitaron {item_req.quantity} pero solo hay {available} disponibles en {warehouse.name}."
                        ),
                    )

                prev_stock = p_stock.current_stock
                new_stk = prev_stock - item_req.quantity
                p_stock.current_stock = new_stk

                unit_price = item_req.unit_price_mxn if item_req.unit_price_mxn is not None else product.price_mxn
                unit_cost = product.cost_mxn or Decimal("0.00")

                # Asiento en Kardex
                movement = InventoryMovement(
                    tenant_id=tenant_id,
                    product_id=product.id,
                    warehouse_id=warehouse.id,
                    user_id=current_user.id,
                    movement_type=MovementType.SALE_EXIT,
                    quantity=-item_req.quantity,
                    previous_stock=prev_stock,
                    new_stock=new_stk,
                    unit_cost_mxn=unit_cost,
                    notes=f"Salida por venta en mostrador POS ({product.name})",
                )
                self.session.add(movement)

                item_subtotal = (unit_price * item_req.quantity).quantize(Decimal("0.01"))
                item_discount = item_req.discount_mxn or Decimal("0.00")
                item_total = max(Decimal("0.00"), item_subtotal - item_discount)
                item_total_cost = (unit_cost * item_req.quantity).quantize(Decimal("0.01"))

                total_subtotal_mxn += item_subtotal
                total_cost_mxn += item_total_cost

                sale_item = SaleItem(
                    tenant_id=tenant_id,
                    product_id=product.id,
                    combo_id=None,
                    product_name=product.name,
                    product_sku=product.sku,
                    quantity=item_req.quantity,
                    unit_price_mxn=unit_price,
                    unit_cost_mxn=unit_cost,
                    subtotal_mxn=item_subtotal,
                    discount_mxn=item_discount,
                    total_mxn=item_total,
                    is_on_the_fly=False,
                )
                sale_items_to_create.append(sale_item)

        # 3. Calcular totales finales de la venta
        final_total_mxn = max(Decimal("0.00"), total_subtotal_mxn - total_discount_mxn)

        # 4. Generar consecutivo de folio único
        folio = await self.sale_repo.generate_next_folio(tenant_id)

        # 5. Crear cabecera de la venta
        sale = Sale(
            tenant_id=tenant_id,
            cashier_id=current_user.id,
            warehouse_id=warehouse.id,
            client_id=request.client_id,
            folio=folio,
            status=SaleStatus.COMPLETED,
            subtotal_mxn=total_subtotal_mxn,
            discount_mxn=total_discount_mxn,
            tax_mxn=Decimal("0.00"),
            total_mxn=final_total_mxn,
            total_cost_mxn=total_cost_mxn,
            notes=request.notes,
            items=sale_items_to_create,
        )

        await self.sale_repo.create_sale(sale)
        return self._build_sale_response(sale)

    async def get_sale_by_id(self, sale_id: uuid.UUID, current_user: User) -> SaleResponse:
        """
        Obtiene el detalle completo de una venta por su ID asegurando aislamiento RLS.
        """
        sale = await self.sale_repo.get_by_id(sale_id, current_user.tenant_id)
        if not sale:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"La venta con ID {sale_id} no fue encontrada o no pertenece al inquilino.",
            )
        return self._build_sale_response(sale)

    async def list_sales(
        self,
        current_user: User,
        start_date: Optional[datetime] = None,
        end_date: Optional[datetime] = None,
        cashier_id: Optional[uuid.UUID] = None,
        warehouse_id: Optional[uuid.UUID] = None,
        status_filter: Optional[SaleStatus] = None,
        skip: int = 0,
        limit: int = 50,
    ) -> Tuple[List[SaleResponse], int]:
        """
        Lista las ventas emitidas con paginación y filtros.
        """
        sales, total_count = await self.sale_repo.list_sales(
            tenant_id=current_user.tenant_id,
            start_date=start_date,
            end_date=end_date,
            cashier_id=cashier_id,
            warehouse_id=warehouse_id,
            status=status_filter,
            skip=skip,
            limit=limit,
        )
        return [self._build_sale_response(s) for s in sales], total_count

    async def cancel_sale(
        self,
        sale_id: uuid.UUID,
        reason: str,
        current_user: User,
    ) -> SaleResponse:
        """
        Anula o cancela una venta registrada, revirtiendo el stock al almacén
        y asentando movimientos compensatorios inmutables en el Kardex (SALE_CANCEL).
        """
        tenant_id = current_user.tenant_id
        sale = await self.sale_repo.get_by_id(sale_id, tenant_id)
        if not sale:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"La venta con ID {sale_id} no existe o no pertenece al inquilino.",
            )

        if sale.status in [SaleStatus.CANCELLED, SaleStatus.REFUNDED]:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"La venta {sale.folio} ya se encuentra en estado {sale.status.value}.",
            )

        # Revertir existencias de cada partida
        for item in sale.items:
            # Reversión de combo
            if item.combo_id is not None and item.combo:
                for c_item in item.combo.items:
                    revert_qty = c_item.quantity * item.quantity
                    stk_query = (
                        select(ProductStock)
                        .where(ProductStock.product_id == c_item.product_id)
                        .where(ProductStock.warehouse_id == sale.warehouse_id)
                        .where(ProductStock.tenant_id == tenant_id)
                        .with_for_update()
                    )
                    stk_res = await self.session.execute(stk_query)
                    p_stock = stk_res.scalar_one_or_none()
                    if p_stock:
                        prev = p_stock.current_stock
                        p_stock.current_stock = prev + revert_qty
                        mov = InventoryMovement(
                            tenant_id=tenant_id,
                            product_id=c_item.product_id,
                            warehouse_id=sale.warehouse_id,
                            user_id=current_user.id,
                            movement_type=MovementType.SALE_CANCEL,
                            quantity=revert_qty,
                            previous_stock=prev,
                            new_stock=prev + revert_qty,
                            unit_cost_mxn=(c_item.product.cost_mxn or Decimal("0.00")) if c_item.product else Decimal("0.00"),
                            reference_id=sale.id,
                            notes=f"Reincorporación por cancelación de venta {sale.folio}: {reason}",
                        )
                        self.session.add(mov)

            # Reversión de producto individual o creado al vuelo
            elif item.product_id is not None:
                stk_query = (
                    select(ProductStock)
                    .where(ProductStock.product_id == item.product_id)
                    .where(ProductStock.warehouse_id == sale.warehouse_id)
                    .where(ProductStock.tenant_id == tenant_id)
                    .with_for_update()
                )
                stk_res = await self.session.execute(stk_query)
                p_stock = stk_res.scalar_one_or_none()
                if p_stock:
                    prev = p_stock.current_stock
                    p_stock.current_stock = prev + item.quantity
                    mov = InventoryMovement(
                        tenant_id=tenant_id,
                        product_id=item.product_id,
                        warehouse_id=sale.warehouse_id,
                        user_id=current_user.id,
                        movement_type=MovementType.SALE_CANCEL,
                        quantity=item.quantity,
                        previous_stock=prev,
                        new_stock=prev + item.quantity,
                        unit_cost_mxn=item.unit_cost_mxn,
                        reference_id=sale.id,
                        notes=f"Reincorporación por cancelación de venta {sale.folio}: {reason}",
                    )
                    self.session.add(mov)

        # Actualizar estado a CANCELLED
        sale.status = SaleStatus.CANCELLED
        sale.notes = f"{sale.notes or ''} [CANCELADA: {reason}]".strip()
        await self.session.flush()
        return self._build_sale_response(sale)

    def _build_sale_response(self, sale: Sale) -> SaleResponse:
        """
        Construye el DTO enriquecido de respuesta con utilidades brutas y márgenes calculados.
        """
        item_responses: List[SaleItemResponse] = []
        for it in sale.items:
            profit = (it.unit_price_mxn - it.unit_cost_mxn) * it.quantity - it.discount_mxn
            item_responses.append(
                SaleItemResponse(
                    id=it.id,
                    sale_id=it.sale_id,
                    product_id=it.product_id,
                    combo_id=it.combo_id,
                    product_name=it.product_name,
                    product_sku=it.product_sku,
                    quantity=it.quantity,
                    unit_price_mxn=it.unit_price_mxn,
                    unit_cost_mxn=it.unit_cost_mxn,
                    subtotal_mxn=it.subtotal_mxn,
                    discount_mxn=it.discount_mxn,
                    total_mxn=it.total_mxn,
                    is_on_the_fly=it.is_on_the_fly,
                    profit_mxn=profit.quantize(Decimal("0.01")),
                    created_at=it.created_at,
                )
            )

        gross_profit = sale.total_mxn - sale.total_cost_mxn

        return SaleResponse(
            id=sale.id,
            tenant_id=sale.tenant_id,
            cashier_id=sale.cashier_id,
            warehouse_id=sale.warehouse_id,
            client_id=sale.client_id,
            folio=sale.folio,
            status=sale.status,
            subtotal_mxn=sale.subtotal_mxn,
            discount_mxn=sale.discount_mxn,
            tax_mxn=sale.tax_mxn,
            total_mxn=sale.total_mxn,
            total_cost_mxn=sale.total_cost_mxn,
            gross_profit_mxn=gross_profit.quantize(Decimal("0.01")),
            notes=sale.notes,
            items=item_responses,
            created_at=sale.created_at,
            updated_at=sale.updated_at,
        )
