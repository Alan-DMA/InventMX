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
from app.modules.sales_pos.domain.payment import PaymentMethod, SalePayment
from app.modules.sales_pos.domain.sale import Sale, SaleItem, SaleStatus
from app.modules.sales_pos.repositories.sale_repository import SaleRepository
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


class SalesService:
    """
    Servicio de Reglas de Negocio para el Núcleo Transaccional POS (RF-09, RF-12, RF-13, RF-14).
    Garantiza consistencia ACID, bloqueo por concurrencia (SELECT FOR UPDATE),
    congelamiento de costos históricos, pagos mixtos y calculadora de cambio Banxico.
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
        Ejecuta el Checkout transaccional atómico en el Punto de Venta (RF-09, RF-12, RF-13, RF-14).
        1. Valida el almacén físico.
        2. Procesa cada partida (producto existente, producto al vuelo o combo).
        3. Bloquea stocks con SELECT ... FOR UPDATE para prevenir sobreventas concurrentes.
        4. Congela precios de venta y costos unitarios históricos en Pesos Mexicanos ($ MXN).
        5. Asienta movimientos inmutables en el Kardex (SALE_EXIT, ADJUSTMENT_IN).
        6. Valida y distribuye los métodos de pago (Split Payments RF-14) y calcula cambio en efectivo.
        7. Genera folio consecutivo y persiste la venta y sus pagos atómicamente.
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
        Anula o cancela una venta registrada revirtiendo las existencias en Kardex (RF-12).
        """
        sale = await self.sale_repo.get_by_id(sale_id, current_user.tenant_id)
        if not sale:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"La venta con ID {sale_id} no fue encontrada.",
            )
        if sale.status == SaleStatus.CANCELLED:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="La venta ya se encuentra en estado CANCELLED.",
            )

        tenant_id = current_user.tenant_id
        warehouse_id = sale.warehouse_id

        # Reversión de existencias en Kardex por cada partida
        for item in sale.items:
            if item.product_id:
                stock_query = (
                    select(ProductStock)
                    .where(ProductStock.product_id == item.product_id)
                    .where(ProductStock.warehouse_id == warehouse_id)
                    .where(ProductStock.tenant_id == tenant_id)
                    .with_for_update()
                )
                res = await self.session.execute(stock_query)
                p_stock = res.scalar_one_or_none()
                if p_stock:
                    prev = p_stock.current_stock
                    new_stk = prev + item.quantity
                    p_stock.current_stock = new_stk

                    mov = InventoryMovement(
                        tenant_id=tenant_id,
                        product_id=item.product_id,
                        warehouse_id=warehouse_id,
                        user_id=current_user.id,
                        movement_type=MovementType.SALE_CANCEL,
                        quantity=item.quantity,
                        previous_stock=prev,
                        new_stock=new_stk,
                        unit_cost_mxn=item.unit_cost_mxn,
                        reference_id=sale.id,
                        notes=f"Reincorporación por cancelación de venta {sale.folio}: {reason}",
                    )
                    self.session.add(mov)

            elif item.combo_id:
                c_query = (
                    select(Combo)
                    .options(selectinload(Combo.items))
                    .where(Combo.id == item.combo_id)
                    .where(Combo.tenant_id == tenant_id)
                )
                c_res = await self.session.execute(c_query)
                combo = c_res.scalar_one_or_none()
                if combo:
                    for comp in combo.items:
                        qty_to_restore = comp.quantity * item.quantity
                        stock_query = (
                            select(ProductStock)
                            .where(ProductStock.product_id == comp.product_id)
                            .where(ProductStock.warehouse_id == warehouse_id)
                            .where(ProductStock.tenant_id == tenant_id)
                            .with_for_update()
                        )
                        stk_res = await self.session.execute(stock_query)
                        comp_stock = stk_res.scalar_one_or_none()
                        if comp_stock:
                            prev = comp_stock.current_stock
                            new_stk = prev + qty_to_restore
                            comp_stock.current_stock = new_stk

                            mov = InventoryMovement(
                                tenant_id=tenant_id,
                                product_id=comp.product_id,
                                warehouse_id=warehouse_id,
                                user_id=current_user.id,
                                movement_type=MovementType.SALE_CANCEL,
                                quantity=qty_to_restore,
                                previous_stock=prev,
                                new_stock=new_stk,
                                unit_cost_mxn=comp_stock.average_cost_mxn,
                                reference_id=sale.id,
                                notes=f"Reincorporación de componente de combo por cancelación de venta {sale.folio}: {reason}",
                            )
                            self.session.add(mov)

        # Actualizar estado a CANCELLED
        sale.status = SaleStatus.CANCELLED
        sale.notes = f"{sale.notes or ''} [CANCELADA: {reason}]".strip()
        await self.session.flush()
        return self._build_sale_response(sale)

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
