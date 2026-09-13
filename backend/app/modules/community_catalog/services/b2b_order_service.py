# Importación de precisión decimal para Pesos Mexicanos
from datetime import datetime
from decimal import Decimal
# Importación de tipado estático
from typing import List, Optional
# Importación de identificadores UUID
import uuid

# Importación de excepciones HTTP de FastAPI
from fastapi import HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

# Importación de entidades de dominio
from app.modules.auth_tenancy.domain.user import User
from app.modules.community_catalog.domain.b2b_order import (
    B2BOrder,
    B2BOrderItem,
    B2BOrderStatus,
)
from app.modules.community_catalog.repositories.b2b_marketplace_repository import B2BMarketplaceRepository
from app.modules.community_catalog.repositories.b2b_order_repository import B2BOrderRepository
from app.modules.community_catalog.schemas.b2b_order import (
    B2BOrderCreateRequest,
    B2BOrderItemResponse,
    B2BOrderResponse,
    B2BOrderStatusUpdateRequest,
)


class B2BOrderService:
    """
    Servicio transaccional de pedidos mayoristas entre comercios (RF-27 / Const. Art. 7.5).
    """

    def __init__(self, session: AsyncSession) -> None:
        self.session = session
        self.order_repo = B2BOrderRepository(session)
        self.marketplace_repo = B2BMarketplaceRepository(session)

    async def create_b2b_order(
        self,
        request: B2BOrderCreateRequest,
        current_user: User,
    ) -> B2BOrderResponse:
        """
        Emite un nuevo pedido mayorista B2B hacia otro comercio.
        Valida que el comprador no se compre a sí mismo, lotes mínimos y existencias disponibles.
        """
        # 1. Validar que el comprador no sea el mismo vendedor
        if request.seller_tenant_id == current_user.tenant_id:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="No es posible emitir pedidos mayoristas a su propio comercio.",
            )

        # 2. Validar partidas del pedido
        order_items: List[B2BOrderItem] = []
        total_sum = Decimal("0.00")

        for item_req in request.items:
            listing = await self.marketplace_repo.get_listing_by_id(item_req.b2b_listing_id)
            if not listing:
                raise HTTPException(
                    status_code=status.HTTP_404_NOT_FOUND,
                    detail=f"La oferta mayorista con ID '{item_req.b2b_listing_id}' no existe.",
                )
            if listing.tenant_id != request.seller_tenant_id:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="La oferta seleccionada no pertenece al vendedor especificado.",
                )
            if not listing.is_active:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail=f"La oferta para '{listing.product_name}' no se encuentra activa.",
                )

            # Validar lote mínimo de compra
            if item_req.quantity < listing.min_wholesale_quantity:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail=f"La cantidad solicitada ({item_req.quantity:g}) es menor al lote mínimo requerido ({listing.min_wholesale_quantity:g} pzas) para '{listing.product_name}'.",
                )

            # Validar existencias disponibles para mayoreo
            if item_req.quantity > listing.available_b2b_stock:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail=f"Existencias insuficientes para mayoreo en '{listing.product_name}'. Disponibles: {listing.available_b2b_stock:g}.",
                )

            line_subtotal = (listing.wholesale_price_mxn * item_req.quantity).quantize(Decimal("0.01"))
            total_sum += line_subtotal

            order_item = B2BOrderItem(
                b2b_listing_id=listing.id,
                product_id=listing.product_id,
                product_name=listing.product_name,
                quantity=item_req.quantity,
                unit_price_mxn=listing.wholesale_price_mxn,
                subtotal_mxn=line_subtotal,
            )
            order_items.append(order_item)

        # 3. Generar folio y persistir pedido
        order_num = await self.order_repo.generate_next_order_number()
        b2b_order = B2BOrder(
            order_number=order_num,
            buyer_tenant_id=current_user.tenant_id,
            seller_tenant_id=request.seller_tenant_id,
            status=B2BOrderStatus.PENDING,
            total_mxn=total_sum.quantize(Decimal("0.01")),
            delivery_type=request.delivery_type,
            delivery_address=request.delivery_address,
            notes=request.notes,
            items=order_items,
        )

        created_order = await self.order_repo.create_order(b2b_order)
        return self._map_order_to_response(created_order)

    async def list_sent_orders(
        self,
        current_user: User,
        status: Optional[B2BOrderStatus] = None,
    ) -> List[B2BOrderResponse]:
        """Retorna pedidos emitidos como comprador."""
        orders = await self.order_repo.list_sent_orders(current_user.tenant_id, status)
        return [self._map_order_to_response(o) for o in orders]

    async def list_received_orders(
        self,
        current_user: User,
        status: Optional[B2BOrderStatus] = None,
    ) -> List[B2BOrderResponse]:
        """Retorna pedidos recibidos como vendedor."""
        orders = await self.order_repo.list_received_orders(current_user.tenant_id, status)
        return [self._map_order_to_response(o) for o in orders]

    async def update_order_status(
        self,
        order_id: uuid.UUID,
        request: B2BOrderStatusUpdateRequest,
        current_user: User,
    ) -> B2BOrderResponse:
        """
        Actualiza el estado de un pedido B2B.
        - Aceptar/Rechazar/Completar: Solo el vendedor.
        - Cancelar: Comprador o Vendedor antes de completado.
        Al aceptar el pedido, descuenta el stock mayorista disponible del vendedor.
        """
        order = await self.order_repo.get_order_by_id(order_id)
        if not order:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Pedido B2B no encontrado.",
            )

        new_status = request.status
        is_seller = order.seller_tenant_id == current_user.tenant_id
        is_buyer = order.buyer_tenant_id == current_user.tenant_id

        if not (is_seller or is_buyer):
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="No tiene permisos para interactuar con este pedido.",
            )

        if new_status in [B2BOrderStatus.ACCEPTED, B2BOrderStatus.REJECTED, B2BOrderStatus.COMPLETED]:
            if not is_seller:
                raise HTTPException(
                    status_code=status.HTTP_403_FORBIDDEN,
                    detail="Únicamente el comercio vendedor puede aceptar, rechazar o completar este pedido.",
                )

        if new_status == B2BOrderStatus.ACCEPTED and order.status == B2BOrderStatus.PENDING:
            # Descontar stock mayorista del listing
            for itm in order.items:
                listing = await self.marketplace_repo.get_listing_by_id(itm.b2b_listing_id)
                if listing:
                    listing.available_b2b_stock = max(Decimal("0.00"), listing.available_b2b_stock - itm.quantity)

        order.status = new_status
        if request.notes:
            timestamp = datetime.now().strftime('%Y-%m-%d %H:%M')
            order.notes = f"{order.notes or ''}\n[{timestamp}]: {request.notes}".strip()

        await self.session.flush()
        await self.session.refresh(order)
        return self._map_order_to_response(order)

    def _map_order_to_response(self, order: B2BOrder) -> B2BOrderResponse:
        """Transforma la entidad B2BOrder a DTO de respuesta."""
        buyer_name = order.buyer_tenant.name if order.buyer_tenant else "Comercio Comprador"
        seller_name = order.seller_tenant.name if order.seller_tenant else "Comercio Vendedor"

        items_dto = [
            B2BOrderItemResponse(
                id=itm.id,
                b2b_listing_id=itm.b2b_listing_id,
                product_id=itm.product_id,
                product_name=itm.product_name,
                quantity=itm.quantity,
                unit_price_mxn=itm.unit_price_mxn,
                subtotal_mxn=itm.subtotal_mxn,
            )
            for itm in order.items
        ]

        return B2BOrderResponse(
            id=order.id,
            order_number=order.order_number,
            buyer_tenant_id=order.buyer_tenant_id,
            buyer_store_name=buyer_name,
            seller_tenant_id=order.seller_tenant_id,
            seller_store_name=seller_name,
            status=order.status,
            total_mxn=order.total_mxn,
            delivery_type=order.delivery_type,
            delivery_address=order.delivery_address,
            notes=order.notes,
            items=items_dto,
            created_at=order.created_at,
            updated_at=order.updated_at,
        )
