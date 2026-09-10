# Importación de precisión decimal para Pesos Mexicanos
from datetime import date, timedelta
from decimal import Decimal
# Importación de tipado estático
from typing import List, Optional, Tuple
# Importación de identificadores UUID
import uuid
# Importación de excepciones HTTP de FastAPI
from fastapi import HTTPException, status
# Importación de SQLAlchemy
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

# Importación de entidades de dominio y repositorios
from app.modules.auth_tenancy.domain.user import User
from app.modules.inventory.domain.inventory_movement import MovementType
from app.modules.inventory.domain.product import Product
from app.modules.inventory.domain.product_stock import ProductStock
from app.modules.inventory.domain.warehouse import Warehouse
from app.modules.inventory.repositories.movement_repository import MovementRepository
from app.modules.purchasing_suppliers.domain.account_payable import (
    AccountPayable,
    AccountPayableStatus,
)
from app.modules.purchasing_suppliers.domain.purchase_order import (
    PurchaseOrder,
    PurchaseOrderItem,
    PurchaseOrderStatus,
)
from app.modules.purchasing_suppliers.domain.supplier import Supplier, SupplierStatus
from app.modules.purchasing_suppliers.repositories.account_payable_repository import (
    AccountPayableRepository,
)
from app.modules.purchasing_suppliers.repositories.purchase_order_repository import (
    PurchaseOrderRepository,
)
from app.modules.purchasing_suppliers.repositories.supplier_repository import (
    SupplierRepository,
)
from app.modules.purchasing_suppliers.schemas.account_payable import AccountPayableResponse
from app.modules.purchasing_suppliers.schemas.purchase_order import (
    PurchaseOrderCreateRequest,
    PurchaseOrderItemResponse,
    PurchaseOrderReceiveRequest,
    PurchaseOrderReceiveResponse,
    PurchaseOrderResponse,
)
from app.modules.purchasing_suppliers.schemas.supplier import (
    SupplierCreateRequest,
    SupplierResponse,
    SupplierUpdateRequest,
)


class PurchasingService:
    """
    Servicio de lógica de negocio para Proveedores, Órdenes de Compra y Recepción a Inventario (RF-15, RF-17).
    """

    def __init__(self, session: AsyncSession) -> None:
        self.session = session
        self.supplier_repo = SupplierRepository(session)
        self.po_repo = PurchaseOrderRepository(session)
        self.ap_repo = AccountPayableRepository(session)
        self.movement_repo = MovementRepository(session)

    # -------------------------------------------------------------------------
    # Gestión de Proveedores (Suppliers)
    # -------------------------------------------------------------------------

    async def create_supplier(
        self,
        request: SupplierCreateRequest,
        current_user: User,
    ) -> SupplierResponse:
        """Crea un nuevo proveedor asociado al inquilino."""
        supplier = Supplier(
            tenant_id=current_user.tenant_id,
            name=request.name.strip(),
            rfc=request.rfc.strip().upper() if request.rfc else None,
            phone=request.phone.strip() if request.phone else None,
            email=request.email.strip().lower() if request.email else None,
            address=request.address.strip() if request.address else None,
            credit_days=request.credit_days,
            credit_limit_mxn=request.credit_limit_mxn,
            status=SupplierStatus.ACTIVE,
            notes=request.notes,
        )
        saved = await self.supplier_repo.create(supplier)
        return SupplierResponse.model_validate(saved)

    async def update_supplier(
        self,
        supplier_id: uuid.UUID,
        request: SupplierUpdateRequest,
        current_user: User,
    ) -> SupplierResponse:
        """Actualiza la información comercial o crédito de un proveedor."""
        supplier = await self.supplier_repo.get_by_id(supplier_id, current_user.tenant_id)
        if not supplier:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Proveedor no encontrado o no pertenece a este comercio.",
            )

        if request.name is not None:
            supplier.name = request.name.strip()
        if request.rfc is not None:
            supplier.rfc = request.rfc.strip().upper() if request.rfc else None
        if request.phone is not None:
            supplier.phone = request.phone.strip() if request.phone else None
        if request.email is not None:
            supplier.email = request.email.strip().lower() if request.email else None
        if request.address is not None:
            supplier.address = request.address.strip() if request.address else None
        if request.credit_days is not None:
            supplier.credit_days = request.credit_days
        if request.credit_limit_mxn is not None:
            supplier.credit_limit_mxn = request.credit_limit_mxn
        if request.status is not None:
            supplier.status = request.status
        if request.notes is not None:
            supplier.notes = request.notes

        updated = await self.supplier_repo.update(supplier)
        return SupplierResponse.model_validate(updated)

    async def get_supplier(
        self,
        supplier_id: uuid.UUID,
        current_user: User,
    ) -> SupplierResponse:
        """Obtiene el detalle de un proveedor."""
        supplier = await self.supplier_repo.get_by_id(supplier_id, current_user.tenant_id)
        if not supplier:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Proveedor no encontrado.",
            )
        return SupplierResponse.model_validate(supplier)

    async def list_suppliers(
        self,
        current_user: User,
        search: Optional[str] = None,
        status_filter: Optional[SupplierStatus] = None,
        limit: int = 50,
        offset: int = 0,
    ) -> Tuple[List[SupplierResponse], int]:
        """Lista proveedores aplicando filtros de búsqueda y estado."""
        items, total = await self.supplier_repo.list_suppliers(
            tenant_id=current_user.tenant_id,
            search=search,
            status=status_filter,
            limit=limit,
            offset=offset,
        )
        return [SupplierResponse.model_validate(s) for s in items], total

    async def deactivate_supplier(
        self,
        supplier_id: uuid.UUID,
        current_user: User,
    ) -> SupplierResponse:
        """Desactiva un proveedor para evitar nuevas órdenes de compra."""
        supplier = await self.supplier_repo.get_by_id(supplier_id, current_user.tenant_id)
        if not supplier:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Proveedor no encontrado.",
            )
        supplier.status = SupplierStatus.INACTIVE
        updated = await self.supplier_repo.update(supplier)
        return SupplierResponse.model_validate(updated)

    # -------------------------------------------------------------------------
    # Órdenes de Compra (Purchase Orders)
    # -------------------------------------------------------------------------

    async def create_purchase_order(
        self,
        request: PurchaseOrderCreateRequest,
        current_user: User,
    ) -> PurchaseOrderResponse:
        """
        Crea una nueva orden de compra con sus renglones calculados en Pesos Mexicanos.
        """
        # 1. Validar proveedor
        supplier = await self.supplier_repo.get_by_id(request.supplier_id, current_user.tenant_id)
        if not supplier:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Proveedor especificado no existe.",
            )
        if supplier.status == SupplierStatus.INACTIVE:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="No se pueden emitir órdenes a un proveedor inactivo.",
            )

        # 2. Validar o resolver almacén
        warehouse_id = request.warehouse_id
        if not warehouse_id:
            # Buscar almacén principal por defecto
            stmt_wh = select(Warehouse).where(
                Warehouse.tenant_id == current_user.tenant_id,
                Warehouse.is_default == True,
            )
            res_wh = await self.session.execute(stmt_wh)
            wh = res_wh.scalar_one_or_none()
            if not wh:
                # Tomar cualquier almacén del inquilino
                stmt_wh_any = select(Warehouse).where(Warehouse.tenant_id == current_user.tenant_id)
                res_wh_any = await self.session.execute(stmt_wh_any)
                wh = res_wh_any.scalar_one_or_none()
            if not wh:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="No existe ningún almacén configurado para el comercio.",
                )
            warehouse_id = wh.id

        # 3. Generar folio correlativo
        folio = await self.po_repo.generate_next_folio(current_user.tenant_id)

        # 4. Validar productos y calcular totales
        po_items: List[PurchaseOrderItem] = []
        subtotal_sum = Decimal("0.00")

        for item_req in request.items:
            # Validar existencia de producto
            p_stmt = select(Product).where(
                Product.id == item_req.product_id,
                Product.tenant_id == current_user.tenant_id,
            )
            p_res = await self.session.execute(p_stmt)
            product = p_res.scalar_one_or_none()
            if not product:
                raise HTTPException(
                    status_code=status.HTTP_404_NOT_FOUND,
                    detail=f"Producto {item_req.product_id} no encontrado.",
                )

            # Costo unitario acordado (si viene 0, tomar el costo actual del producto)
            unit_cost = item_req.unit_cost_mxn if item_req.unit_cost_mxn > Decimal("0.0000") else getattr(product, "cost_mxn", Decimal("0.0000"))
            line_subtotal = (unit_cost * item_req.quantity_ordered).quantize(Decimal("0.01"))
            subtotal_sum += line_subtotal

            po_item = PurchaseOrderItem(
                tenant_id=current_user.tenant_id,
                product_id=product.id,
                quantity_ordered=item_req.quantity_ordered,
                quantity_received=Decimal("0.0000"),
                unit_cost_mxn=unit_cost,
                subtotal_mxn=line_subtotal,
                lot_number=item_req.lot_number,
                expiry_date=item_req.expiry_date,
            )
            po_items.append(po_item)

        tax_total = Decimal("0.00")
        total_order = subtotal_sum + tax_total

        # 5. Crear la orden de compra
        order = PurchaseOrder(
            tenant_id=current_user.tenant_id,
            supplier_id=supplier.id,
            warehouse_id=warehouse_id,
            folio=folio,
            status=PurchaseOrderStatus.CONFIRMED,
            subtotal_mxn=subtotal_sum,
            tax_mxn=tax_total,
            total_mxn=total_order,
            expected_delivery_date=request.expected_delivery_date,
            notes=request.notes,
            created_by_user_id=current_user.id,
            items=po_items,
        )

        saved_order = await self.po_repo.create(order)
        # Recargar con relaciones
        full_order = await self.po_repo.get_by_id(saved_order.id, current_user.tenant_id)
        return self._build_order_response(full_order)

    async def get_purchase_order(
        self,
        order_id: uuid.UUID,
        current_user: User,
    ) -> PurchaseOrderResponse:
        """Obtiene una orden de compra por su ID."""
        order = await self.po_repo.get_by_id(order_id, current_user.tenant_id)
        if not order:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Orden de compra no encontrada.",
            )
        return self._build_order_response(order)

    async def list_purchase_orders(
        self,
        current_user: User,
        supplier_id: Optional[uuid.UUID] = None,
        status_filter: Optional[PurchaseOrderStatus] = None,
        date_from: Optional[date] = None,
        date_to: Optional[date] = None,
        limit: int = 50,
        offset: int = 0,
    ) -> Tuple[List[PurchaseOrderResponse], int]:
        """Lista órdenes de compra con filtros y paginación."""
        orders, total = await self.po_repo.list_purchase_orders(
            tenant_id=current_user.tenant_id,
            supplier_id=supplier_id,
            status=status_filter,
            date_from=date_from,
            date_to=date_to,
            limit=limit,
            offset=offset,
        )
        return [self._build_order_response(o) for o in orders], total

    # -------------------------------------------------------------------------
    # Recepción Física de Mercancía a Inventario / Kardex (RF-15, RF-17)
    # -------------------------------------------------------------------------

    async def receive_purchase_order(
        self,
        order_id: uuid.UUID,
        request: PurchaseOrderReceiveRequest,
        current_user: User,
    ) -> PurchaseOrderReceiveResponse:
        """
        Recepciona físicamente productos de una orden de compra, actualiza stock en almacén,
        asienta movimientos de tipo PURCHASE_ENTRY en Kardex y genera la Cuenta por Pagar (CxP).
        """
        # 1. Obtener orden de compra con items
        order = await self.po_repo.get_by_id(order_id, current_user.tenant_id)
        if not order:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Orden de compra no encontrada.",
            )

        if order.status in (PurchaseOrderStatus.RECEIVED, PurchaseOrderStatus.CANCELLED):
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail=f"La orden ya se encuentra en estado {order.status.value} y no admite nuevas recepciones.",
            )

        # Mapa de renglones existentes por ID
        item_map = {item.id: item for item in order.items}

        movements_created = 0
        total_received_cost = Decimal("0.00")

        # 2. Procesar cada renglón recepcionado
        for rec_req in request.items_received:
            po_item = item_map.get(rec_req.purchase_order_item_id)
            if not po_item:
                raise HTTPException(
                    status_code=status.HTTP_404_NOT_FOUND,
                    detail=f"Renglón de orden de compra {rec_req.purchase_order_item_id} no pertenece a esta orden.",
                )

            # Validar que no se exceda la cantidad ordenada
            pending_qty = po_item.quantity_ordered - po_item.quantity_received
            if rec_req.quantity_received > pending_qty:
                raise HTTPException(
                    status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                    detail=(
                        f"Cantidad a recibir ({rec_req.quantity_received}) supera la cantidad pendiente "
                        f"({pending_qty}) para el producto {po_item.product_id}."
                    ),
                )

            # Actualizar cantidad y costo si viene especificado
            po_item.quantity_received += rec_req.quantity_received
            if rec_req.unit_cost_mxn is not None:
                po_item.unit_cost_mxn = rec_req.unit_cost_mxn
            if rec_req.lot_number:
                po_item.lot_number = rec_req.lot_number
            if rec_req.expiry_date:
                po_item.expiry_date = rec_req.expiry_date

            line_cost = (po_item.unit_cost_mxn * rec_req.quantity_received).quantize(Decimal("0.01"))
            total_received_cost += line_cost

            # 3. Buscar o inicializar stock en el almacén de destino (con lock)
            stock_stmt = (
                select(ProductStock)
                .where(
                    ProductStock.product_id == po_item.product_id,
                    ProductStock.warehouse_id == order.warehouse_id,
                    ProductStock.tenant_id == current_user.tenant_id,
                )
                .with_for_update()
            )
            stock_res = await self.session.execute(stock_stmt)
            stock = stock_res.scalar_one_or_none()

            if not stock:
                # Crear registro de existencias si no existía en el almacén
                stock = ProductStock(
                    tenant_id=current_user.tenant_id,
                    product_id=po_item.product_id,
                    warehouse_id=order.warehouse_id,
                    current_stock=Decimal("0.00"),
                    reserved_stock=Decimal("0.00"),
                )
                self.session.add(stock)
                await self.session.flush()

            previous_stock = stock.current_stock
            stock.current_stock += rec_req.quantity_received
            new_stock = stock.current_stock

            # 4. Registrar movimiento append-only en el Libro Mayor de Kardex (inventory_movements)
            invoice_ref_note = f" - Factura: {request.invoice_reference}" if request.invoice_reference else ""
            await self.movement_repo.record_movement(
                tenant_id=current_user.tenant_id,
                product_id=po_item.product_id,
                warehouse_id=order.warehouse_id,
                movement_type=MovementType.PURCHASE_ENTRY,
                quantity=rec_req.quantity_received,
                previous_stock=previous_stock,
                new_stock=new_stock,
                unit_cost_mxn=po_item.unit_cost_mxn,
                user_id=current_user.id,
                reference_id=order.id,
                notes=f"Recepción OC {order.folio}{invoice_ref_note}",
            )
            movements_created += 1

        # 5. Evaluar si la orden quedó completamente recibida o parcial
        all_completed = all(item.quantity_received >= item.quantity_ordered for item in order.items)
        order.status = PurchaseOrderStatus.RECEIVED if all_completed else PurchaseOrderStatus.PARTIALLY_RECEIVED
        order.received_date = request.received_date or date.today()
        if request.invoice_reference:
            order.invoice_reference = request.invoice_reference
        if request.notes:
            order.notes = f"{order.notes or ''} | {request.notes}".strip(" |")

        await self.po_repo.update(order)

        # 6. Generación de Cuenta por Pagar (CxP) si aún no existe para esta orden
        ap_response: Optional[AccountPayableResponse] = None
        existing_ap = await self.ap_repo.get_by_purchase_order_id(order.id, current_user.tenant_id)

        if not existing_ap:
            # Obtener días de crédito del proveedor
            supplier = await self.supplier_repo.get_by_id(order.supplier_id, current_user.tenant_id)
            credit_days = supplier.credit_days if supplier else 0
            due_date = order.received_date + timedelta(days=credit_days)

            ap_folio = await self.ap_repo.generate_next_folio(current_user.tenant_id)
            new_ap = AccountPayable(
                tenant_id=current_user.tenant_id,
                supplier_id=order.supplier_id,
                purchase_order_id=order.id,
                folio=ap_folio,
                total_mxn=order.total_mxn,
                amount_paid_mxn=Decimal("0.00"),
                status=AccountPayableStatus.PENDING,
                due_date=due_date,
                invoice_reference=order.invoice_reference,
                notes=f"Generada por recepción de orden de compra {order.folio}",
            )
            saved_ap = await self.ap_repo.create(new_ap)
            ap_with_supplier = await self.ap_repo.get_by_id(saved_ap.id, current_user.tenant_id)
            ap_response = self._build_ap_response(ap_with_supplier)
        else:
            ap_response = self._build_ap_response(existing_ap)

        # 7. Retornar respuesta consolidada
        full_order = await self.po_repo.get_by_id(order.id, current_user.tenant_id)
        return PurchaseOrderReceiveResponse(
            purchase_order=self._build_order_response(full_order),
            stock_movements_count=movements_created,
            account_payable=ap_response,
        )

    # -------------------------------------------------------------------------
    # Métodos Auxiliares de Construcción de Respuestas
    # -------------------------------------------------------------------------

    def _build_order_response(self, order: PurchaseOrder) -> PurchaseOrderResponse:
        """Mapea una entidad PurchaseOrder a su esquema fuertemente tipado."""
        items_dto: List[PurchaseOrderItemResponse] = []
        for it in order.items:
            items_dto.append(
                PurchaseOrderItemResponse(
                    id=it.id,
                    tenant_id=it.tenant_id,
                    purchase_order_id=it.purchase_order_id,
                    product_id=it.product_id,
                    product_name=it.product.name if it.product else None,
                    product_sku=it.product.sku if it.product else None,
                    quantity_ordered=it.quantity_ordered,
                    quantity_received=it.quantity_received,
                    unit_cost_mxn=it.unit_cost_mxn,
                    subtotal_mxn=it.subtotal_mxn,
                    lot_number=it.lot_number,
                    expiry_date=it.expiry_date,
                    created_at=it.created_at,
                )
            )

        return PurchaseOrderResponse(
            id=order.id,
            tenant_id=order.tenant_id,
            supplier_id=order.supplier_id,
            supplier_name=order.supplier.name if order.supplier else None,
            supplier_rfc=order.supplier.rfc if order.supplier else None,
            warehouse_id=order.warehouse_id,
            warehouse_name=None,
            folio=order.folio,
            status=order.status,
            subtotal_mxn=order.subtotal_mxn,
            tax_mxn=order.tax_mxn,
            total_mxn=order.total_mxn,
            expected_delivery_date=order.expected_delivery_date,
            received_date=order.received_date,
            invoice_reference=order.invoice_reference,
            notes=order.notes,
            created_by_user_id=order.created_by_user_id,
            created_at=order.created_at,
            updated_at=order.updated_at,
            items=items_dto,
        )

    def _build_ap_response(self, ap: AccountPayable) -> AccountPayableResponse:
        """Mapea una Cuenta por Pagar a su DTO de respuesta."""
        return AccountPayableResponse(
            id=ap.id,
            tenant_id=ap.tenant_id,
            supplier_id=ap.supplier_id,
            supplier_name=ap.supplier.name if ap.supplier else None,
            purchase_order_id=ap.purchase_order_id,
            folio=ap.folio,
            total_mxn=ap.total_mxn,
            amount_paid_mxn=ap.amount_paid_mxn,
            status=ap.status,
            due_date=ap.due_date,
            invoice_reference=ap.invoice_reference,
            notes=ap.notes,
            created_at=ap.created_at,
            updated_at=ap.updated_at,
        )
