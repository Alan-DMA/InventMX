from fastapi import APIRouter, Depends, HTTPException, status, Query
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, text
from decimal import Decimal
from uuid import UUID
from typing import List
from datetime import datetime, timezone

from app.core.database import get_db
from app.api.deps import get_current_user
from app.models.models import (
    User, Sale, SaleItem, SalePayment, Product, Inventory, 
    Warehouse, InventoryMovement, Tenant
)
from app.schemas.sales import (
    SaleCreate, SaleResponse, SalePaymentCreate, SaleStatusTransition,
    SaleItemResponse, SalePaymentResponse
)

router = APIRouter()

# Helper to verify transitions
def _validate_transition(current_status: str, new_status: str):
    valid_transitions = {
        "DRAFT": ["PENDING_PAYMENT", "CANCELLED"],
        "PENDING_PAYMENT": ["PAID", "CANCELLED"],
        "PAID": ["COMPLETED", "REFUNDED"],
        "COMPLETED": ["REFUNDED"],
        "CANCELLED": [],
        "REFUNDED": []
    }
    
    if new_status not in valid_transitions.get(current_status, []):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Transición inválida de estado: {current_status} -> {new_status}"
        )


# --- Endpoints ---

@router.post("", response_model=SaleResponse, status_code=status.HTTP_201_CREATED)
async def create_sale(
    payload: SaleCreate,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """
    Crea una nueva venta en estado inicial DRAFT.
    Congela el costo de compra actual del producto en el ítem de venta.
    """
    # 1. Obtener la tasa de cambio del inquilino
    tenant_query = await db.execute(select(Tenant).where(Tenant.id == current_user.tenant_id))
    tenant = tenant_query.scalars().first()
    if not tenant:
        raise HTTPException(status_code=404, detail="Tenant no encontrado.")
    rate = tenant.current_exchange_rate

    # 2. Validar que los productos existan y calcular el total
    total_usd = Decimal("0.00")
    items_to_create = []

    for item in payload.items:
        prod_query = await db.execute(select(Product).where(Product.id == item.product_id))
        product = prod_query.scalars().first()
        if not product or not product.is_active:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"El producto con ID {item.product_id} no existe o no está activo."
            )
        
        # Calcular total
        total_usd += item.unit_price_usd * item.quantity

        # Crear registro del ítem con el costo congelado del producto
        sale_item = SaleItem(
            tenant_id=current_user.tenant_id,
            product_id=product.id,
            quantity=item.quantity,
            unit_cost_usd=product.cost_usd,  # Congelamos costo actual
            unit_price_usd=item.unit_price_usd
        )
        items_to_create.append(sale_item)

    # 3. Crear cabecera de la venta
    new_sale = Sale(
        tenant_id=current_user.tenant_id,
        user_id=current_user.id,
        seller_id=payload.seller_id or current_user.id,
        exchange_rate_applied=rate,
        status="DRAFT",
        total_usd=total_usd,
        commission_amount_usd=Decimal("0.00")
    )
    db.add(new_sale)
    await db.flush()

    # Vincular items
    for item in items_to_create:
        item.sale_id = new_sale.id
        db.add(item)

    await db.commit()

    # Retornar respuesta
    return SaleResponse(
        id=new_sale.id,
        tenant_id=new_sale.tenant_id,
        user_id=new_sale.user_id,
        seller_id=new_sale.seller_id,
        exchange_rate_applied=new_sale.exchange_rate_applied,
        status=new_sale.status,
        total_usd=new_sale.total_usd,
        commission_amount_usd=new_sale.commission_amount_usd,
        created_at=new_sale.created_at,
        updated_at=new_sale.updated_at,
        items=[SaleItemResponse(
            product_id=i.product_id,
            quantity=i.quantity,
            unit_cost_usd=i.unit_cost_usd,
            unit_price_usd=i.unit_price_usd
        ) for i in items_to_create]
    )


@router.post("/{id}/payments", response_model=SaleResponse)
async def add_sale_payments(
    id: UUID,
    payments: List[SalePaymentCreate],
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """
    Registra uno o más pagos mixtos (USD/VES) para una venta en curso.
    """
    # 1. Obtener la venta
    sale_query = await db.execute(select(Sale).where(Sale.id == id))
    sale = sale_query.scalars().first()
    if not sale:
        raise HTTPException(status_code=404, detail="Venta no encontrada.")

    # 2. Agregar los pagos
    payments_created = []
    for p in payments:
        new_payment = SalePayment(
            tenant_id=current_user.tenant_id,
            sale_id=sale.id,
            payment_method=p.payment_method,
            amount_usd=p.amount_usd,
            amount_ves=p.amount_ves,
            reference_number=p.reference_number
        )
        db.add(new_payment)
        payments_created.append(new_payment)

    # Consultar relaciones para la respuesta antes del commit
    items_query = await db.execute(select(SaleItem).where(SaleItem.sale_id == sale.id))
    items_list = items_query.scalars().all()

    payments_query = await db.execute(select(SalePayment).where(SalePayment.sale_id == sale.id))
    all_payments = payments_query.scalars().all()

    await db.commit()

    return SaleResponse(
        id=sale.id,
        tenant_id=sale.tenant_id,
        user_id=sale.user_id,
        seller_id=sale.seller_id,
        exchange_rate_applied=sale.exchange_rate_applied,
        status=sale.status,
        total_usd=sale.total_usd,
        commission_amount_usd=sale.commission_amount_usd,
        created_at=sale.created_at,
        updated_at=sale.updated_at,
        items=[SaleItemResponse(
            product_id=i.product_id,
            quantity=i.quantity,
            unit_cost_usd=i.unit_cost_usd,
            unit_price_usd=i.unit_price_usd
        ) for i in items_list],
        payments=[SalePaymentResponse(
            payment_method=p.payment_method,
            amount_usd=p.amount_usd,
            amount_ves=p.amount_ves,
            reference_number=p.reference_number
        ) for p in all_payments]
    )


@router.post("/{id}/transition", response_model=SaleResponse)
async def transition_sale(
    id: UUID,
    payload: SaleStatusTransition,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """
    Transiciona el estado de una venta y ejecuta las reglas asociadas de comisiones e inventario.
    """
    # 1. Obtener la venta
    sale_query = await db.execute(select(Sale).where(Sale.id == id))
    sale = sale_query.scalars().first()
    if not sale:
        raise HTTPException(status_code=404, detail="Venta no encontrada.")

    # 2. Validar transición de estado
    current_status = sale.status
    new_status = payload.new_status
    _validate_transition(current_status, new_status)

    # Obtener el almacén principal
    wh_query = await db.execute(
        select(Warehouse).where(Warehouse.name == "Almacén Principal")
    )
    warehouse = wh_query.scalars().first()
    if not warehouse:
        raise HTTPException(status_code=500, detail="Almacén Principal no configurado.")

    # Cargar los ítems de venta
    items_query = await db.execute(select(SaleItem).where(SaleItem.sale_id == sale.id))
    items = items_query.scalars().all()

    # --- Lógica por transición ---

    # A: DRAFT -> PENDING_PAYMENT (Reservar Stock)
    if current_status == "DRAFT" and new_status == "PENDING_PAYMENT":
        for item in items:
            inv_query = await db.execute(
                select(Inventory).where(
                    (Inventory.product_id == item.product_id) & 
                    (Inventory.warehouse_id == warehouse.id)
                )
            )
            inv = inv_query.scalars().first()
            if not inv or inv.stock_available < item.quantity:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail={
                        "code": "INSUFFICIENT_STOCK",
                        "message": f"Existencias insuficientes para reservar el ítem ID: {item.product_id}"
                    }
                )
            # Reservar cantidades
            inv.stock_available -= item.quantity
            inv.stock_reserved += item.quantity
            
            # Movimiento Kardex
            db.add(InventoryMovement(
                tenant_id=current_user.tenant_id,
                product_id=item.product_id,
                warehouse_id=warehouse.id,
                quantity=item.quantity,
                type="RESERVA",
                reference_document=str(sale.id),
                notes=f"Reserva de stock para venta ID {sale.id}"
            ))

    # B: PENDING_PAYMENT -> PAID (Cálculo de comisiones y verificación de pago)
    elif current_status == "PENDING_PAYMENT" and new_status == "PAID":
        # 1. Validar que esté pagada en su totalidad
        payments_query = await db.execute(select(SalePayment).where(SalePayment.sale_id == sale.id))
        payments = payments_query.scalars().all()
        total_paid_usd = sum(p.amount_usd for p in payments)
        
        # Damos un margen de error decimal ínfimo
        if total_paid_usd < (sale.total_usd - Decimal("0.01")):
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail={
                    "code": "PAYMENTS_INCOMPLETE",
                    "message": f"Monto pagado ({total_paid_usd}) es menor al total de la venta ({sale.total_usd})."
                }
            )

        # 2. Calcular comisiones para el vendedor
        if sale.seller_id:
            seller_query = await db.execute(select(User).where(User.id == sale.seller_id))
            seller = seller_query.scalars().first()
            
            if seller and seller.commission_rate > 0:
                # Margen neto real = sum((precio - costo) * cantidad)
                margin_usd = sum((i.unit_price_usd - i.unit_cost_usd) * i.quantity for i in items)
                
                if margin_usd > 0:
                    commission_amount = margin_usd * (seller.commission_rate / Decimal("100.00"))
                    sale.commission_amount_usd = max(Decimal("0.00"), commission_amount)
                else:
                    sale.commission_amount_usd = Decimal("0.00")

    # C: PAID -> COMPLETED (Despacho físico: Consumir stock reservado)
    elif current_status == "PAID" and new_status == "COMPLETED":
        for item in items:
            inv_query = await db.execute(
                select(Inventory).where(
                    (Inventory.product_id == item.product_id) & 
                    (Inventory.warehouse_id == warehouse.id)
                )
            )
            inv = inv_query.scalars().first()
            if inv:
                # Restar del reservado
                qty_to_consume = min(item.quantity, inv.stock_reserved)
                inv.stock_reserved -= qty_to_consume
                
                # Registrar movimiento SALIDA
                db.add(InventoryMovement(
                    tenant_id=current_user.tenant_id,
                    product_id=item.product_id,
                    warehouse_id=warehouse.id,
                    quantity=qty_to_consume,
                    type="SALIDA",
                    reference_document=str(sale.id),
                    notes=f"Despacho físico por venta completada ID {sale.id}"
                ))

    # D: DRAFT / PENDING_PAYMENT -> CANCELLED (Liberar stock reservado)
    elif new_status == "CANCELLED":
        if current_status == "PENDING_PAYMENT":
            for item in items:
                inv_query = await db.execute(
                    select(Inventory).where(
                        (Inventory.product_id == item.product_id) & 
                        (Inventory.warehouse_id == warehouse.id)
                    )
                )
                inv = inv_query.scalars().first()
                if inv:
                    # Devolver reservado a disponible
                    qty_to_release = min(item.quantity, inv.stock_reserved)
                    inv.stock_reserved -= qty_to_release
                    inv.stock_available += qty_to_release
                    
                    # Kardex
                    db.add(InventoryMovement(
                        tenant_id=current_user.tenant_id,
                        product_id=item.product_id,
                        warehouse_id=warehouse.id,
                        quantity=qty_to_release,
                        type="LIBERACION",
                        reference_document=str(sale.id),
                        notes=f"Liberación por cancelación de venta ID {sale.id}"
                    ))

    # E: PAID / COMPLETED -> REFUNDED (Devolución total a inventario y cancelación de comisión)
    elif new_status == "REFUNDED":
        # Las comisiones se anulan en devoluciones
        sale.commission_amount_usd = Decimal("0.00")
        
        for item in items:
            inv_query = await db.execute(
                select(Inventory).where(
                    (Inventory.product_id == item.product_id) & 
                    (Inventory.warehouse_id == warehouse.id)
                )
            )
            inv = inv_query.scalars().first()
            if inv:
                if current_status == "COMPLETED":
                    # El stock ya había salido, por ende se devuelve directo a disponible
                    inv.stock_available += item.quantity
                    db.add(InventoryMovement(
                        tenant_id=current_user.tenant_id,
                        product_id=item.product_id,
                        warehouse_id=warehouse.id,
                        quantity=item.quantity,
                        type="DEVOLUCION",
                        reference_document=str(sale.id),
                        notes=f"Devolución de mercancía por reembolso de venta completada ID {sale.id}"
                    ))
                elif current_status == "PAID":
                    # El stock aún estaba en estado reservado
                    qty_to_release = min(item.quantity, inv.stock_reserved)
                    inv.stock_reserved -= qty_to_release
                    inv.stock_available += qty_to_release
                    
                    db.add(InventoryMovement(
                        tenant_id=current_user.tenant_id,
                        product_id=item.product_id,
                        warehouse_id=warehouse.id,
                        quantity=qty_to_release,
                        type="DEVOLUCION",
                        reference_document=str(sale.id),
                        notes=f"Devolución de stock reservado por reembolso de venta pagada ID {sale.id}"
                    ))

    # Actualizar estado de la venta con timestamp UTC correcto (naive para PostgreSQL TIMESTAMP WITHOUT TIME ZONE)
    sale.status = new_status
    sale.updated_at = datetime.now(timezone.utc).replace(tzinfo=None)
    # Recargar relaciones para respuesta antes del commit
    payments_query = await db.execute(select(SalePayment).where(SalePayment.sale_id == sale.id))
    all_payments = payments_query.scalars().all()

    await db.commit()

    return SaleResponse(
        id=sale.id,
        tenant_id=sale.tenant_id,
        user_id=sale.user_id,
        seller_id=sale.seller_id,
        exchange_rate_applied=sale.exchange_rate_applied,
        status=sale.status,
        total_usd=sale.total_usd,
        commission_amount_usd=sale.commission_amount_usd,
        created_at=sale.created_at,
        updated_at=sale.updated_at,
        items=[SaleItemResponse(
            product_id=i.product_id,
            quantity=i.quantity,
            unit_cost_usd=i.unit_cost_usd,
            unit_price_usd=i.unit_price_usd
        ) for i in items],
        payments=[SalePaymentResponse(
            payment_method=p.payment_method,
            amount_usd=p.amount_usd,
            amount_ves=p.amount_ves,
            reference_number=p.reference_number
        ) for p in all_payments]
    )


# ─────────────────────────────────────────────────────────
# A-06: Endpoints de LECTURA que faltaban en la API
# ─────────────────────────────────────────────────────────

def _build_sale_response(sale: Sale, items: list, payments: list) -> SaleResponse:
    """Helper reutilizable para construir SaleResponse desde objetos ORM."""
    return SaleResponse(
        id=sale.id,
        tenant_id=sale.tenant_id,
        user_id=sale.user_id,
        seller_id=sale.seller_id,
        exchange_rate_applied=sale.exchange_rate_applied,
        status=sale.status,
        total_usd=sale.total_usd,
        commission_amount_usd=sale.commission_amount_usd,
        created_at=sale.created_at,
        updated_at=sale.updated_at,
        items=[SaleItemResponse(
            product_id=i.product_id,
            quantity=i.quantity,
            unit_cost_usd=i.unit_cost_usd,
            unit_price_usd=i.unit_price_usd,
        ) for i in items],
        payments=[SalePaymentResponse(
            payment_method=p.payment_method,
            amount_usd=p.amount_usd,
            amount_ves=p.amount_ves,
            reference_number=p.reference_number,
        ) for p in payments],
    )


@router.get("", response_model=List[SaleResponse])
async def list_sales(
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
    status_filter: str = Query(default=None, alias="status", description="Filtrar por estado: DRAFT, PENDING_PAYMENT, PAID, COMPLETED, CANCELLED, REFUNDED"),
    skip: int = Query(default=0, ge=0, description="Offset de paginación"),
    limit: int = Query(default=50, ge=1, le=200, description="Límite de resultados (máx 200)"),
):
    """
    Lista el historial de ventas del Tenant actual con paginación y filtro por estado.
    Los items y pagos se devuelven embebidos en cada venta.
    """
    # Consultar ventas con filtros opcionales
    query = select(Sale)
    if status_filter:
        query = query.where(Sale.status == status_filter)
    query = query.order_by(Sale.created_at.desc()).offset(skip).limit(limit)

    result = await db.execute(query)
    sales = result.scalars().all()

    # Cargar items y pagos para cada venta
    response_list = []
    for sale in sales:
        items_res = await db.execute(select(SaleItem).where(SaleItem.sale_id == sale.id))
        items = items_res.scalars().all()
        pay_res = await db.execute(select(SalePayment).where(SalePayment.sale_id == sale.id))
        payments = pay_res.scalars().all()
        response_list.append(_build_sale_response(sale, items, payments))

    return response_list


@router.get("/{sale_id}", response_model=SaleResponse)
async def get_sale(
    sale_id: UUID,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    Retorna el detalle completo de una venta específica (cabecera + ítems + pagos).
    Protegido por RLS: solo puede ver ventas del propio Tenant.
    """
    sale_res = await db.execute(select(Sale).where(Sale.id == sale_id))
    sale = sale_res.scalars().first()
    if not sale:
        raise HTTPException(status_code=404, detail="Venta no encontrada.")

    items_res = await db.execute(select(SaleItem).where(SaleItem.sale_id == sale.id))
    items = items_res.scalars().all()

    pay_res = await db.execute(select(SalePayment).where(SalePayment.sale_id == sale.id))
    payments = pay_res.scalars().all()

    return _build_sale_response(sale, items, payments)
