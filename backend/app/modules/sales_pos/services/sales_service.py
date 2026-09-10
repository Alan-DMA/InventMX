# Importación de marcas temporales
from datetime import datetime, timezone
# Importación de módulos matemáticos y decimales
from decimal import Decimal
# Importación de tipado estático
from typing import Dict, List, Optional, Tuple
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
from app.modules.sales_pos.domain.commission import CommissionType, SaleCommission
from app.modules.sales_pos.domain.payment import PaymentMethod, SalePayment
from app.modules.sales_pos.domain.sale import Sale, SaleItem, SaleStatus
from app.modules.sales_pos.domain.ticket_settings import TicketSettings
from app.modules.sales_pos.repositories.commission_repository import CommissionRepository
from app.modules.sales_pos.repositories.sale_repository import SaleRepository
from app.modules.sales_pos.repositories.ticket_repository import TicketRepository
from app.modules.sales_pos.schemas.commission import (
    CommissionSummaryResponse,
    SaleCommissionResponse,
    UserCommissionSummary,
)
from app.modules.sales_pos.schemas.payment import (
    BanxicoDenominationBreakdown,
    PaymentRequest,
    PaymentResponse,
    QuickChangeRequest,
    QuickChangeResponse,
)
from app.modules.sales_pos.schemas.sale import (
    SaleCheckoutRequest,
    SaleItemRequest,
    SaleItemResponse,
    SaleResponse,
)
from app.modules.sales_pos.schemas.ticket import (
    TicketLineItemPayload,
    TicketPayloadResponse,
    TicketPaymentPayload,
    TicketSettingsResponse,
    TicketSettingsUpdateRequest,
)


class SalesService:
    """
    Servicio de Reglas de Negocio para el Núcleo Transaccional POS (RF-08, RF-09, RF-10, RF-12, RF-13, RF-14).
    Garantiza consistencia ACID, bloqueo por concurrencia (SELECT FOR UPDATE),
    congelamiento de costos históricos, pagos divididos, calculadora de cambio Banxico,
    formateo monoespaciado de tickets térmicos (58mm/80mm) y cálculo dinámico de comisiones.
    """

    def __init__(self, session: AsyncSession):
        # Sesión asíncrona de base de datos
        self.session = session
        # Repositorio de ventas
        self.sale_repo = SaleRepository(session)
        # Repositorio de productos
        self.product_repo = ProductRepository(session)
        # Repositorio de configuración de tickets
        self.ticket_repo = TicketRepository(session)
        # Repositorio de comisiones
        self.commission_repo = CommissionRepository(session)

    async def _get_or_create_general_category(self, tenant_id: uuid.UUID) -> Category:
        """
        Garantiza la existencia de la categoría 'General' para productos creados al vuelo (Lazy Loading).
        """
        query = (
            select(Category)
            .where(Category.tenant_id == tenant_id)
            .where(Category.name == "General")
        )
        res = await self.session.execute(query)
        cat = res.scalar_one_or_none()
        if not cat:
            cat = Category(
                tenant_id=tenant_id,
                name="General",
                description="Categoría por defecto para productos creados al vuelo en POS",
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
        Ejecuta el checkout atómico en mostrador (RF-09, RF-12, RF-13, RF-14 / Const. Art. 7.1, 7.2):
        - Bloqueo SELECT FOR UPDATE de existencias en almacén.
        - Soporte para creación de productos al vuelo (Lazy Loading).
        - Descuento de stock en combos promocionales.
        - Asientos inmutables en Kardex (SALE_EXIT y ADJUSTMENT_IN).
        - Congelamiento de precios y costos históricos en Pesos Mexicanos ($ MXN).
        - Soporte de pagos divididos, pagos parciales diferidos (PENDING_PAYMENT) y cálculo de cambio.
        """
        tenant_id = current_user.tenant_id

        # 1. Validar Almacén
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
                detail=f"El almacén con ID {request.warehouse_id} no fue encontrado.",
            )

        sale_items_to_create: List[SaleItem] = []
        total_subtotal_mxn = Decimal("0.00")
        total_cost_mxn = Decimal("0.00")
        total_discount_mxn = request.discount_mxn or Decimal("0.00")

        # 2. Procesar cada partida del carrito
        for item_req in request.items:
            # -----------------------------------------------------------------
            # CASO A: Producto Creado al Vuelo (Lazy Loading RF-09 / Const. Art. 7.3)
            # -----------------------------------------------------------------
            if item_req.is_on_the_fly:
                if not item_req.on_the_fly_name:
                    raise HTTPException(
                        status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                        detail="El nombre del producto al vuelo (on_the_fly_name) es obligatorio.",
                    )
                if item_req.unit_price_mxn is None or item_req.unit_price_mxn < Decimal("0.00"):
                    raise HTTPException(
                        status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                        detail="El precio unitario (unit_price_mxn) es obligatorio para productos al vuelo.",
                    )

                unit_price = item_req.unit_price_mxn
                cost_mxn = item_req.on_the_fly_cost_mxn or Decimal("0.00")

                # Obtener categoría por defecto
                general_cat = await self._get_or_create_general_category(tenant_id)

                # Generar SKU interno único para el producto al vuelo (NEX-XXXXXXXX)
                sku = f"NEX-{uuid.uuid4().hex[:8].upper()}"

                # Crear nuevo producto de catálogo automáticamente
                new_product = Product(
                    tenant_id=tenant_id,
                    category_id=general_cat.id,
                    name=item_req.on_the_fly_name.strip(),
                    sku=sku,
                    barcode=item_req.on_the_fly_barcode.strip() if item_req.on_the_fly_barcode else None,
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
                    current_stock=Decimal("0.000"),
                    reserved_stock=Decimal("0.000"),
                )
                self.session.add(new_stock)
                await self.session.flush()

                # Asiento de entrada inicial de inventario en Kardex (ADJUSTMENT_IN)
                entry_mov = InventoryMovement(
                    tenant_id=tenant_id,
                    product_id=new_product.id,
                    warehouse_id=warehouse.id,
                    user_id=current_user.id,
                    movement_type=MovementType.ADJUSTMENT_IN,
                    quantity=initial_qty,
                    previous_stock=Decimal("0.000"),
                    new_stock=initial_qty,
                    unit_cost_mxn=cost_mxn,
                    notes=f"Alta Just-in-Time en POS para producto al vuelo '{new_product.name}'",
                )
                self.session.add(entry_mov)

                # Asiento de salida inmediata por venta en Kardex (SALE_EXIT)
                sale_mov = InventoryMovement(
                    tenant_id=tenant_id,
                    product_id=new_product.id,
                    warehouse_id=warehouse.id,
                    user_id=current_user.id,
                    movement_type=MovementType.SALE_EXIT,
                    quantity=-initial_qty,
                    previous_stock=initial_qty,
                    new_stock=Decimal("0.000"),
                    unit_cost_mxn=cost_mxn,
                    notes=f"Venta inmediata POS para producto al vuelo '{new_product.name}'",
                )
                self.session.add(sale_mov)

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
                combo_query = (
                    select(Combo)
                    .options(selectinload(Combo.items).selectinload(ComboItem.product))
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

                # Deducción atómica de existencias de cada componente con SELECT FOR UPDATE
                for c_item in combo.items:
                    required_comp_qty = c_item.quantity * item_req.quantity

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
                            f"Stock insuficiente para el producto '{product.name}'. "
                            f"Existencias disponibles: {available}, solicitadas: {item_req.quantity}."
                        ),
                    )

                # Descontar stock
                prev_stock = p_stock.current_stock
                new_stk = prev_stock - item_req.quantity
                p_stock.current_stock = new_stk

                # Congelar costo unitario de adquisición histórico en MXN
                unit_cost = product.cost_mxn if product.cost_mxn is not None else Decimal("0.00")
                unit_price = item_req.unit_price_mxn if item_req.unit_price_mxn is not None else product.price_mxn

                # Registrar asiento en Kardex (SALE_EXIT)
                mov = InventoryMovement(
                    tenant_id=tenant_id,
                    product_id=product.id,
                    warehouse_id=warehouse.id,
                    user_id=current_user.id,
                    movement_type=MovementType.SALE_EXIT,
                    quantity=-item_req.quantity,
                    previous_stock=prev_stock,
                    new_stock=new_stk,
                    unit_cost_mxn=unit_cost,
                    notes=f"Venta en POS de producto '{product.name}'",
                )
                self.session.add(mov)

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

        # 4. Procesar y Validar Pagos (RF-13, RF-14 / Const. Art. 3.2, 7.2)
        sale_payments_to_create: List[SalePayment] = []
        payment_method_type = "CASH_MXN"
        total_paid_mxn = Decimal("0.00")
        total_change_mxn = Decimal("0.00")

        if not request.payments:
            # Si no se especifican pagos, se asume pago exacto en efectivo CASH_MXN
            total_paid_mxn = final_total_mxn
            total_change_mxn = Decimal("0.00")
            payment_method_type = "CASH_MXN"
            exact_payment = SalePayment(
                tenant_id=tenant_id,
                payment_method=PaymentMethod.CASH_MXN,
                amount_paid_mxn=final_total_mxn,
                change_returned_mxn=Decimal("0.00"),
                reference_code=None,
                notes="Pago en efectivo registrado en checkout",
            )
            sale_payments_to_create.append(exact_payment)
            sale_status = SaleStatus.COMPLETED
        else:
            # Validación exhaustiva de lista de pagos
            for p_req in request.payments:
                if p_req.amount_paid_mxn <= Decimal("0.00"):
                    raise HTTPException(
                        status_code=status.HTTP_400_BAD_REQUEST,
                        detail="El monto de cada pago debe ser mayor a 0.00 MXN.",
                    )
                total_paid_mxn += p_req.amount_paid_mxn

            # Validación de suficiencia de pago
            if total_paid_mxn < final_total_mxn:
                if not request.allow_partial_payment:
                    raise HTTPException(
                        status_code=status.HTTP_400_BAD_REQUEST,
                        detail=(
                            f"El importe total pagado (${total_paid_mxn:.2f} MXN) es insuficiente para "
                            f"cubrir el total de la venta (${final_total_mxn:.2f} MXN)."
                        ),
                    )
                # Si se permiten pagos diferidos / parciales, la venta queda en estado pendiente
                sale_status = SaleStatus.PENDING_PAYMENT
                total_change_mxn = Decimal("0.00")
            else:
                sale_status = SaleStatus.COMPLETED
                # Cálculo de cambio/vuelto
                total_change_mxn = (total_paid_mxn - final_total_mxn).quantize(Decimal("0.01"))

            # Validar que los métodos electrónicos no generen vuelto si no hay efectivo suficiente
            cash_payments = [p for p in request.payments if p.payment_method == PaymentMethod.CASH_MXN]
            total_cash_received = sum(p.amount_paid_mxn for p in cash_payments)

            if total_change_mxn > Decimal("0.00") and total_change_mxn > total_cash_received:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail=(
                        f"El cambio a devolver (${total_change_mxn:.2f} MXN) excede el efectivo entregado "
                        f"(${total_cash_received:.2f} MXN). Los métodos digitales no pueden generar cambio en efectivo."
                    ),
                )

            # Determinar tipo de liquidación
            if len(request.payments) == 1:
                payment_method_type = request.payments[0].payment_method.value
            else:
                payment_method_type = "MULTIPLE"

            # Crear entidades de pago asignando el cambio al pago en efectivo
            remaining_change_to_assign = total_change_mxn
            for p_req in request.payments:
                change_for_this_payment = Decimal("0.00")
                if p_req.payment_method == PaymentMethod.CASH_MXN and remaining_change_to_assign > Decimal("0.00"):
                    change_for_this_payment = min(p_req.amount_paid_mxn, remaining_change_to_assign)
                    remaining_change_to_assign -= change_for_this_payment

                p_entity = SalePayment(
                    tenant_id=tenant_id,
                    payment_method=p_req.payment_method,
                    amount_paid_mxn=p_req.amount_paid_mxn,
                    change_returned_mxn=change_for_this_payment,
                    reference_code=p_req.reference_code,
                    notes=p_req.notes,
                )
                sale_payments_to_create.append(p_entity)

        # 5. Generar consecutivo de folio único
        folio = await self.sale_repo.generate_next_folio(tenant_id)

        # 6. Crear cabecera de la venta
        sale = Sale(
            tenant_id=tenant_id,
            cashier_id=current_user.id,
            warehouse_id=warehouse.id,
            client_id=request.client_id,
            folio=folio,
            status=sale_status if request.payments else SaleStatus.COMPLETED,
            subtotal_mxn=total_subtotal_mxn,
            discount_mxn=total_discount_mxn,
            tax_mxn=Decimal("0.00"),
            total_mxn=final_total_mxn,
            total_cost_mxn=total_cost_mxn,
            payment_method_type=payment_method_type,
            amount_paid_mxn=total_paid_mxn,
            change_returned_mxn=total_change_mxn,
            notes=request.notes,
            items=sale_items_to_create,
            payments=sale_payments_to_create,
        )

        await self.sale_repo.create_sale(sale)
        return self._build_sale_response(sale)

    def calculate_quick_change(
        self,
        total_mxn: Decimal,
        cash_received_mxn: Decimal,
    ) -> QuickChangeResponse:
        """
        Asistente de cálculo instantáneo de vuelto y desglose de denominaciones oficiales de Banxico (RF-14 / Const. Art. 7.2).
        Billetes: $1000, $500, $200, $100, $50, $20
        Monedas: $20, $10, $5, $2, $1, $0.50
        """
        if cash_received_mxn < total_mxn:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=(
                    f"El efectivo recibido (${cash_received_mxn:.2f} MXN) es insuficiente "
                    f"para cubrir el total a cobrar (${total_mxn:.2f} MXN)."
                ),
            )

        change_mxn = (cash_received_mxn - total_mxn).quantize(Decimal("0.01"))
        is_exact = (change_mxn == Decimal("0.00"))

        # Desglose greedy en centavos para máxima precisión sin flotantes
        remaining_cents = int(round(change_mxn * 100))

        # Denominaciones oficiales de billetes (en centavos)
        official_bills = [
            ("1000", 100000),
            ("500", 50000),
            ("200", 20000),
            ("100", 10000),
            ("50", 5000),
            ("20", 2000),
        ]

        # Denominaciones oficiales de monedas (en centavos)
        official_coins = [
            ("10", 1000),
            ("5", 500),
            ("2", 200),
            ("1", 100),
            ("0.50", 50),
        ]

        bills_dict: Dict[str, int] = {}
        for name, val_cents in official_bills:
            count = remaining_cents // val_cents
            if count > 0:
                bills_dict[name] = int(count)
                remaining_cents %= val_cents

        coins_dict: Dict[str, int] = {}
        for name, val_cents in official_coins:
            count = remaining_cents // val_cents
            if count > 0:
                coins_dict[name] = int(count)
                remaining_cents %= val_cents

        breakdown = BanxicoDenominationBreakdown(
            bills=bills_dict,
            coins=coins_dict,
        )

        return QuickChangeResponse(
            total_mxn=total_mxn,
            cash_received_mxn=cash_received_mxn,
            change_mxn=change_mxn,
            is_exact_payment=is_exact,
            banxico_breakdown=breakdown,
        )

    async def add_payment_to_sale(
        self,
        sale_id: uuid.UUID,
        payment_req: PaymentRequest,
        current_user: User,
    ) -> SaleResponse:
        """
        Registra un abono o pago complementario a una venta existente (RF-13, RF-14).
        Si el total acumulado cubre la venta, transiciona el estado de PENDING_PAYMENT a COMPLETED.
        """
        sale = await self.sale_repo.get_by_id(sale_id, current_user.tenant_id)
        if not sale:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"La venta con ID {sale_id} no fue encontrada o no pertenece al inquilino.",
            )

        if sale.status in [SaleStatus.CANCELLED, SaleStatus.REFUNDED]:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"No se pueden registrar pagos en una venta en estado {sale.status.value}.",
            )

        current_paid = sum(p.amount_paid_mxn for p in (sale.payments or []))
        new_total_paid = current_paid + payment_req.amount_paid_mxn
        new_change = max(Decimal("0.00"), new_total_paid - sale.total_mxn)

        # Validación si genera cambio pero no es efectivo
        if new_change > Decimal("0.00") and payment_req.payment_method != PaymentMethod.CASH_MXN:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Solo los pagos en efectivo pueden generar cambio/vuelto en mostrador.",
            )

        change_for_this_payment = new_change if payment_req.payment_method == PaymentMethod.CASH_MXN else Decimal("0.00")

        payment_entity = SalePayment(
            tenant_id=current_user.tenant_id,
            sale_id=sale.id,
            payment_method=payment_req.payment_method,
            amount_paid_mxn=payment_req.amount_paid_mxn,
            change_returned_mxn=change_for_this_payment,
            reference_code=payment_req.reference_code,
            notes=payment_req.notes,
        )
        self.session.add(payment_entity)
        if sale.payments is not None:
            sale.payments.append(payment_entity)
        else:
            sale.payments = [payment_entity]

        sale.amount_paid_mxn = new_total_paid
        sale.change_returned_mxn = new_change

        # Si se liquidó por completo y estaba en PENDING_PAYMENT, completar la venta
        if new_total_paid >= sale.total_mxn:
            if sale.status == SaleStatus.PENDING_PAYMENT:
                sale.status = SaleStatus.COMPLETED

        # Determinar si ahora es múltiple
        if len(sale.payments) > 1:
            sale.payment_method_type = "MULTIPLE"
        else:
            sale.payment_method_type = payment_req.payment_method.value

        await self.session.flush()
        return self._build_sale_response(sale)

    async def get_sale_by_id(self, sale_id: uuid.UUID, current_user: User) -> SaleResponse:
        """
        Obtiene el detalle completo de una venta por su ID asegurando aislamiento RLS.
        """
        sale = await self.sale_repo.get_by_id(sale_id, current_user.tenant_id)
        if not sale:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"La venta con ID {sale_id} no fue encontrada.",
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
    ) -> List[SaleResponse]:
        """
        Consulta el historial de ventas paginado con filtros avanzados.
        """
        sales = await self.sale_repo.list_sales(
            tenant_id=current_user.tenant_id,
            start_date=start_date,
            end_date=end_date,
            cashier_id=cashier_id,
            warehouse_id=warehouse_id,
            status_filter=status_filter,
            skip=skip,
            limit=limit,
        )
        return [self._build_sale_response(s) for s in sales]

    async def cancel_sale(
        self,
        sale_id: uuid.UUID,
        reason: str,
        current_user: User,
    ) -> SaleResponse:
        """
        Cancela una venta y revierte el inventario con asiento inmutable en Kardex (RETURN_IN) (RF-12).
        """
        tenant_id = current_user.tenant_id

        # 1. Recuperar la venta
        sale = await self.sale_repo.get_by_id(sale_id, tenant_id)
        if not sale:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"La venta con ID {sale_id} no fue encontrada.",
            )

        if sale.status == SaleStatus.CANCELLED:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Esta venta ya se encuentra cancelada.",
            )

        # 2. Revertir existencias de cada partida
        for item in sale.items:
            # Reversión de combo
            if item.combo_id is not None:
                combo_query = (
                    select(Combo)
                    .options(selectinload(Combo.items).selectinload(ComboItem.product))
                    .where(Combo.id == item.combo_id)
                )
                c_res = await self.session.execute(combo_query)
                combo = c_res.scalar_one_or_none()
                if combo:
                    for c_item in combo.items:
                        qty_to_revert = c_item.quantity * item.quantity
                        stock_query = (
                            select(ProductStock)
                            .where(ProductStock.product_id == c_item.product_id)
                            .where(ProductStock.warehouse_id == sale.warehouse_id)
                            .where(ProductStock.tenant_id == tenant_id)
                            .with_for_update()
                        )
                        s_res = await self.session.execute(stock_query)
                        p_stock = s_res.scalar_one_or_none()
                        if p_stock:
                            prev_stk = p_stock.current_stock
                            new_stk = prev_stk + qty_to_revert
                            p_stock.current_stock = new_stk

                            comp_cost = c_item.product.cost_mxn if c_item.product else Decimal("0.00")
                            rev_mov = InventoryMovement(
                                tenant_id=tenant_id,
                                product_id=c_item.product_id,
                                warehouse_id=sale.warehouse_id,
                                user_id=current_user.id,
                                movement_type=MovementType.SALE_CANCEL,
                                quantity=qty_to_revert,
                                previous_stock=prev_stk,
                                new_stock=new_stk,
                                unit_cost_mxn=comp_cost or Decimal("0.00"),
                                notes=f"Reversión por cancelación de venta {sale.folio}: combo '{combo.name}'",
                            )
                            self.session.add(rev_mov)

            # Reversión de producto individual
            elif item.product_id is not None:
                stock_query = (
                    select(ProductStock)
                    .where(ProductStock.product_id == item.product_id)
                    .where(ProductStock.warehouse_id == sale.warehouse_id)
                    .where(ProductStock.tenant_id == tenant_id)
                    .with_for_update()
                )
                s_res = await self.session.execute(stock_query)
                p_stock = s_res.scalar_one_or_none()
                if p_stock:
                    prev_stk = p_stock.current_stock
                    new_stk = prev_stk + item.quantity
                    p_stock.current_stock = new_stk

                    rev_mov = InventoryMovement(
                        tenant_id=tenant_id,
                        product_id=item.product_id,
                        warehouse_id=sale.warehouse_id,
                        user_id=current_user.id,
                        movement_type=MovementType.SALE_CANCEL,
                        quantity=item.quantity,
                        previous_stock=prev_stk,
                        new_stock=new_stk,
                        unit_cost_mxn=item.unit_cost_mxn,
                        notes=f"Reversión por cancelación de venta {sale.folio}: '{item.product_name}'",
                    )
                    self.session.add(rev_mov)

        # Actualizar estado a CANCELLED
        sale.status = SaleStatus.CANCELLED
        sale.notes = f"{sale.notes or ''} [CANCELADA: {reason}]".strip()
        await self.session.flush()
        return self._build_sale_response(sale)

    # =========================================================================
    # DÍA 8: FORMATEO DE TICKETS TÉRMICOS & GESTIÓN DE CONFIGURACIÓN (RF-08)
    # =========================================================================

    async def get_ticket_settings(self, current_user: User) -> TicketSettingsResponse:
        """
        Recupera la configuración de tickets térmicos del comercio.
        """
        settings = await self.ticket_repo.get_or_create_default(
            tenant_id=current_user.tenant_id,
            default_business_name="Nexus POS",
        )
        return TicketSettingsResponse(
            tenant_id=settings.tenant_id,
            business_name=settings.business_name,
            legal_name=settings.legal_name,
            rfc=settings.rfc,
            address=settings.address,
            phone=settings.phone,
            email=settings.email,
            footer_message=settings.footer_message,
            paper_width_mm=settings.paper_width_mm,
            show_savings=settings.show_savings,
            show_cashier_name=settings.show_cashier_name,
            show_taxes=settings.show_taxes,
            updated_at=settings.updated_at,
        )

    async def update_ticket_settings(
        self,
        update_req: TicketSettingsUpdateRequest,
        current_user: User,
    ) -> TicketSettingsResponse:
        """
        Actualiza los parámetros de personalización del ticket térmico (RF-08).
        """
        settings = await self.ticket_repo.get_or_create_default(
            tenant_id=current_user.tenant_id,
            default_business_name="Nexus POS",
        )
        updated = await self.ticket_repo.update_settings(settings, update_req)
        return TicketSettingsResponse(
            tenant_id=updated.tenant_id,
            business_name=updated.business_name,
            legal_name=updated.legal_name,
            rfc=updated.rfc,
            address=updated.address,
            phone=updated.phone,
            email=updated.email,
            footer_message=updated.footer_message,
            paper_width_mm=updated.paper_width_mm,
            show_savings=updated.show_savings,
            show_cashier_name=updated.show_cashier_name,
            show_taxes=updated.show_taxes,
            updated_at=updated.updated_at,
        )

    async def generate_sale_ticket(
        self,
        sale_id: uuid.UUID,
        width_mm: Optional[int],
        current_user: User,
    ) -> TicketPayloadResponse:
        """
        Genera el comprobante simplificado / nota de venta POS (RF-08 / Const. Art. 1.2.8).
        Calcula alineación de caracteres monoespaciados para 58mm (32 columnas) u 80mm (48 columnas).
        """
        # 1. Recuperar la venta
        sale = await self.sale_repo.get_by_id(sale_id, current_user.tenant_id)
        if not sale:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"La venta con ID {sale_id} no fue encontrada.",
            )

        # 2. Recuperar configuración de la tienda
        settings = await self.ticket_repo.get_or_create_default(
            tenant_id=current_user.tenant_id,
            default_business_name="Nexus POS",
        )

        effective_width = width_mm if width_mm in [58, 80] else settings.paper_width_mm
        cols = 32 if effective_width == 58 else 48

        # Funciones auxiliares de formateo monoespaciado
        def center(txt: str) -> str:
            if len(txt) >= cols:
                return txt[:cols]
            return txt.center(cols)

        def left_right(left: str, right: str) -> str:
            available_spaces = cols - len(left) - len(right)
            if available_spaces < 1:
                # Truncar izquierda si no cabe
                left_truncated = left[:cols - len(right) - 1]
                return f"{left_truncated} {right}"
            return f"{left}{' ' * available_spaces}{right}"

        def divider(ch: str = "-") -> str:
            return ch * cols

        # 3. Construir líneas de texto monoespaciado
        lines: List[str] = []

        # Cabecera
        business_title = settings.business_name or "NEXUS POS"
        lines.append(center(business_title))
        if settings.legal_name:
            lines.append(center(settings.legal_name))
        if settings.rfc:
            lines.append(center(f"RFC: {settings.rfc}"))
        if settings.address:
            # Dividir dirección en líneas de tamaño adecuado
            addr_words = settings.address.split()
            current_addr_line = ""
            for w in addr_words:
                if len(current_addr_line) + len(w) + 1 <= cols:
                    current_addr_line += (w + " ")
                else:
                    lines.append(center(current_addr_line.strip()))
                    current_addr_line = w + " "
            if current_addr_line:
                lines.append(center(current_addr_line.strip()))
        if settings.phone:
            lines.append(center(f"TEL: {settings.phone}"))
        if settings.email:
            lines.append(center(f"EMAIL: {settings.email}"))

        lines.append(divider("="))
        lines.append(left_right(f"FOLIO: {sale.folio}", sale.created_at.strftime("%d/%m/%Y %H:%M")))
        
        cashier_name = sale.cashier.full_name if sale.cashier else current_user.full_name
        if settings.show_cashier_name and cashier_name:
            lines.append(left_right("CAJERO:", cashier_name))

        lines.append(divider("-"))
        # Encabezado de columnas
        if cols == 32:
            lines.append(f"{'CANT':<4}  {'DESCRIPCION':<16} {'TOTAL':>8}")
        else:
            lines.append(f"{'CANT':<5}  {'DESCRIPCION':<28} {'TOTAL':>11}")
        lines.append(divider("-"))

        # Partidas del ticket
        items_payload: List[TicketLineItemPayload] = []
        total_savings = sale.discount_mxn or Decimal("0.00")

        for it in sale.items:
            items_payload.append(
                TicketLineItemPayload(
                    quantity=it.quantity,
                    product_name=it.product_name,
                    unit_price_mxn=it.unit_price_mxn,
                    discount_mxn=it.discount_mxn,
                    total_mxn=it.total_mxn,
                )
            )
            total_savings += it.discount_mxn

            qty_str = f"{it.quantity:.2f}" if (it.quantity % 1 != 0) else f"{int(it.quantity)}"
            price_str = f"${it.total_mxn:.2f}"

            if cols == 32:
                name_trimmed = it.product_name[:16]
                lines.append(f"{qty_str:>4}  {name_trimmed:<16} {price_str:>8}")
            else:
                name_trimmed = it.product_name[:28]
                lines.append(f"{qty_str:>5}  {name_trimmed:<28} {price_str:>11}")

            if it.discount_mxn > Decimal("0.00"):
                lines.append(left_right("  (Desc. partida)", f"-${it.discount_mxn:.2f}"))

        lines.append(divider("-"))
        lines.append(left_right("SUBTOTAL:", f"${sale.subtotal_mxn:.2f} MXN"))

        if sale.discount_mxn > Decimal("0.00"):
            lines.append(left_right("DESCUENTO GLOBAL:", f"-${sale.discount_mxn:.2f} MXN"))

        if settings.show_taxes and sale.tax_mxn > Decimal("0.00"):
            lines.append(left_right("IVA TRASLADADO:", f"${sale.tax_mxn:.2f} MXN"))

        lines.append(divider("="))
        lines.append(left_right("TOTAL A PAGAR:", f"${sale.total_mxn:.2f} MXN"))
        lines.append(divider("="))

        # Desglose de pagos
        payments_payload: List[TicketPaymentPayload] = []
        lines.append(center("FORMA DE PAGO"))

        for p in (sale.payments or []):
            payments_payload.append(
                TicketPaymentPayload(
                    payment_method=p.payment_method.value,
                    amount_paid_mxn=p.amount_paid_mxn,
                    reference_code=p.reference_code,
                )
            )
            ref_info = f" ({p.reference_code})" if p.reference_code else ""
            lines.append(left_right(f"{p.payment_method.value}{ref_info}:", f"${p.amount_paid_mxn:.2f} MXN"))

        lines.append(left_right("TOTAL PAGADO:", f"${sale.amount_paid_mxn:.2f} MXN"))
        lines.append(left_right("CAMBIO ENTREGADO:", f"${sale.change_returned_mxn:.2f} MXN"))

        # Bloque de ahorro
        if settings.show_savings and total_savings > Decimal("0.00"):
            lines.append(divider("*"))
            lines.append(center(f"*** USTED AHORRÓ: ${total_savings:.2f} MXN ***"))
            lines.append(divider("*"))

        # Pie de ticket
        lines.append(divider("-"))
        lines.append(center(settings.footer_message or "¡Gracias por su compra!"))
        lines.append(divider("-"))

        formatted_string = "\n".join(lines)

        return TicketPayloadResponse(
            folio=sale.folio,
            created_at=sale.created_at,
            cashier_name=cashier_name,
            business_name=business_title,
            legal_name=settings.legal_name,
            rfc=settings.rfc,
            address=settings.address,
            phone=settings.phone,
            email=settings.email,
            paper_width_mm=effective_width,
            items=items_payload,
            subtotal_mxn=sale.subtotal_mxn,
            discount_mxn=sale.discount_mxn,
            tax_mxn=sale.tax_mxn,
            total_mxn=sale.total_mxn,
            amount_paid_mxn=sale.amount_paid_mxn,
            change_returned_mxn=sale.change_returned_mxn,
            savings_mxn=total_savings.quantize(Decimal("0.01")),
            payments=payments_payload,
            footer_message=settings.footer_message,
            formatted_text=formatted_string,
        )

    # =========================================================================
    # DÍA 8: CÁLCULO Y GESTIÓN DE COMISIONES DINÁMICAS (RF-10 / Const. Art. 8.2)
    # =========================================================================

    async def record_sale_commission(
        self,
        sale_id: uuid.UUID,
        user_id: uuid.UUID,
        commission_type: CommissionType,
        commission_rate: Decimal,
        current_user: User,
    ) -> SaleCommissionResponse:
        """
        Calcula y congela el asiento inmutable de comisión para un empleado por una venta (RF-10).
        """
        tenant_id = current_user.tenant_id

        # 1. Recuperar la venta
        sale = await self.sale_repo.get_by_id(sale_id, tenant_id)
        if not sale:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"La venta con ID {sale_id} no fue encontrada.",
            )

        # 2. Calcular base y monto de comisión según el esquema
        if commission_type == CommissionType.PERCENTAGE_SALE:
            base_amount = sale.total_mxn
            commission_amount = (base_amount * (commission_rate / Decimal("100.00"))).quantize(Decimal("0.01"))
        elif commission_type == CommissionType.PERCENTAGE_PROFIT:
            profit = sale.total_mxn - sale.total_cost_mxn
            base_amount = max(Decimal("0.00"), profit)
            commission_amount = (base_amount * (commission_rate / Decimal("100.00"))).quantize(Decimal("0.01"))
        elif commission_type == CommissionType.FIXED_PER_SALE:
            base_amount = sale.total_mxn
            commission_amount = commission_rate.quantize(Decimal("0.01"))
        else:
            base_amount = sale.total_mxn
            commission_amount = Decimal("0.00")

        # 3. Crear entidad de comisión inmutable
        commission = SaleCommission(
            tenant_id=tenant_id,
            sale_id=sale.id,
            user_id=user_id,
            commission_type=commission_type,
            commission_rate=commission_rate,
            base_amount_mxn=base_amount,
            commission_amount_mxn=commission_amount,
            is_settled=False,
            settled_at=None,
        )

        created = await self.commission_repo.create_commission(commission)

        # Cargar nombre del beneficiario
        u_query = select(User).where(User.id == user_id).where(User.tenant_id == tenant_id)
        u_res = await self.session.execute(u_query)
        u_obj = u_res.scalar_one_or_none()
        user_name = u_obj.full_name if u_obj else None

        return SaleCommissionResponse(
            id=created.id,
            tenant_id=created.tenant_id,
            sale_id=created.sale_id,
            user_id=created.user_id,
            user_name=user_name,
            commission_type=created.commission_type,
            commission_rate=created.commission_rate,
            base_amount_mxn=created.base_amount_mxn,
            commission_amount_mxn=created.commission_amount_mxn,
            is_settled=created.is_settled,
            settled_at=created.settled_at,
            created_at=created.created_at,
        )

    async def get_commissions_summary(
        self,
        current_user: User,
        user_id: Optional[uuid.UUID] = None,
        start_date: Optional[datetime] = None,
        end_date: Optional[datetime] = None,
    ) -> CommissionSummaryResponse:
        """
        Genera el informe consolidado de comisiones por empleado y totales del negocio (RF-10).
        """
        tenant_id = current_user.tenant_id

        summaries = await self.commission_repo.get_summary_by_users(
            tenant_id=tenant_id,
            user_id=user_id,
            start_date=start_date,
            end_date=end_date,
        )

        total_commissions = sum((s.total_commission_amount_mxn for s in summaries), Decimal("0.00"))
        total_sales_count = sum(s.total_sales_count for s in summaries)

        return CommissionSummaryResponse(
            start_date=start_date,
            end_date=end_date,
            total_commissions_mxn=total_commissions.quantize(Decimal("0.01")),
            total_sales_count=total_sales_count,
            summaries_by_user=summaries,
        )

    def _build_sale_response(self, sale: Sale) -> SaleResponse:
        """
        Construye el DTO enriquecido de respuesta con utilidades brutas, partidas y pagos registrados.
        """
        item_responses: List[SaleItemResponse] = []
        for it in (sale.items or []):
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

        payment_responses: List[PaymentResponse] = []
        for p in (sale.payments or []):
            payment_responses.append(
                PaymentResponse(
                    id=p.id,
                    sale_id=p.sale_id,
                    payment_method=p.payment_method,
                    amount_paid_mxn=p.amount_paid_mxn,
                    change_returned_mxn=p.change_returned_mxn,
                    reference_code=p.reference_code,
                    notes=p.notes,
                    created_at=p.created_at,
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
            payment_method_type=sale.payment_method_type or "CASH_MXN",
            amount_paid_mxn=sale.amount_paid_mxn,
            change_returned_mxn=sale.change_returned_mxn,
            notes=sale.notes,
            items=item_responses,
            payments=payment_responses,
            created_at=sale.created_at,
            updated_at=sale.updated_at,
        )
