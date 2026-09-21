# Importación de fecha y hora
from datetime import datetime, timezone
# Importación de precisión decimal para Pesos Mexicanos
from decimal import Decimal
# Importación de tipado estático
from typing import Any, Dict, List, Optional
# Importación de identificadores UUID
import uuid

# Importación de FastAPI para errores HTTP
from fastapi import HTTPException, status
# Importación de la sesión asíncrona de base de datos
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database.session import set_tenant_context

from app.modules.auth_tenancy.domain.tenant import Tenant
from app.modules.auth_tenancy.domain.user import User
from app.modules.whatsapp_catalog.domain.catalog_order import CatalogOrder
from app.modules.whatsapp_catalog.repositories.catalog_repository import CatalogRepository
from app.modules.whatsapp_catalog.schemas.public_catalog import (
    CancelReason,
    CatalogOrderItemResponse,
    CatalogOrderStatus,
    DeliveryMethod,
    OrderRevisionResponse,
    PaymentMethodPreview,
    StoreOrderEditRequest,
    StoreOrderListResponse,
    StoreOrderResponse,
    StoreOrderStatusUpdate,
    WhatsAppOrderBuildRequest,
)
from app.modules.whatsapp_catalog.services.order_event_hub import order_event_hub
from app.modules.whatsapp_catalog.services.public_catalog_service import PublicCatalogService

# Transiciones permitidas del ciclo de vida (origen → destinos). Reabrir
# (DELIVERED/CANCELLED → NEW) existe porque "el cliente al final sí lo quiso"
# y "lo cerré por error" son casos reales; sin esto habría que recapturar.
_TRANSITIONS: Dict[str, set] = {
    "NEW": {"READY", "DELIVERED", "CANCELLED"},
    "READY": {"NEW", "DELIVERED", "CANCELLED"},
    "DELIVERED": {"NEW"},
    "CANCELLED": {"NEW"},
}


class StoreOrdersService:
    """
    Pedidos web del lado del tendero (Fases 1-3 del plan del 20 sep 2026):
    lista con badge del servidor, visto automático, cambios de estado con motivo,
    edición con historial de versiones, venta ligada y concurrencia optimista.
    """

    def __init__(self, session: AsyncSession) -> None:
        self.session = session
        self.repo = CatalogRepository(session)

    # -------------------------------------------------------------------------
    # Lectura
    # -------------------------------------------------------------------------

    async def list_orders(
        self,
        current_user: User,
        scope: str,
        since: Optional[datetime],
        limit: int,
    ) -> StoreOrderListResponse:
        tenant = await self._require_tenant(current_user)
        orders = await self.repo.list_orders(tenant.id, scope=scope, since=since, limit=limit)
        items = [await self.to_store_response(o, tenant) for o in orders]
        return StoreOrderListResponse(
            items=items,
            total=await self.repo.count_orders(tenant.id, scope),
            new_count=await self.repo.count_new_unseen(tenant.id),
            active_count=await self.repo.count_orders(tenant.id, "active"),
        )

    async def get_order(self, current_user: User, folio: str, mark_seen: bool = True) -> StoreOrderResponse:
        """Abrir el pedido en la app lo marca como visto — sin toque extra."""
        tenant = await self._require_tenant(current_user)
        order = await self._require_order(tenant.id, folio)
        if mark_seen and order.seen_at is None:
            order.seen_at = datetime.now(timezone.utc)
            order.seen_by = current_user.id
            await self.repo.save_order(order)
            await self._commit(tenant.id)
            self._publish(tenant.id, "order.updated", await self.to_store_response(order, tenant))
        return await self.to_store_response(order, tenant)

    # -------------------------------------------------------------------------
    # Estado
    # -------------------------------------------------------------------------

    async def update_status(
        self,
        current_user: User,
        folio: str,
        request: StoreOrderStatusUpdate,
    ) -> StoreOrderResponse:
        tenant = await self._require_tenant(current_user)
        order = await self._require_order(tenant.id, folio)
        self._check_version(order, request.expected_updated_at)

        target = request.status.value
        if target != order.status:
            if target not in _TRANSITIONS.get(order.status, set()):
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail=f"No se puede pasar un pedido de {order.status} a {target}.",
                )
            if order.status == "DELIVERED" and order.sale_id is not None:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="Este pedido ya se cobró en caja. Si hay que devolverlo, hazlo desde la venta.",
                )
            if target == "CANCELLED" and request.cancel_reason is None:
                raise HTTPException(
                    status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                    detail="Indica el motivo de la cancelación.",
                )
            # Entregar es vender (decisión de Eduardo, QA 20 sep): sin venta
            # ligada el inventario y la caja quedarían mintiendo. Se entrega
            # desde "Cobrar en caja"; el POS liga la venta al terminar.
            if target == "DELIVERED" and request.sale_id is None and order.sale_id is None:
                raise HTTPException(
                    status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                    detail="Para entregar un pedido hay que cobrarlo en caja: la venta descuenta el inventario.",
                )
            order.status = target
            order.status_changed_at = datetime.now(timezone.utc)
            order.cancel_reason = request.cancel_reason.value if target == "CANCELLED" else None

        if request.sale_id is not None:
            order.sale_id = request.sale_id
        order.attended_by = current_user.id
        if order.seen_at is None:
            order.seen_at = datetime.now(timezone.utc)
            order.seen_by = current_user.id

        await self.repo.save_order(order)
        await self._commit(tenant.id)
        response = await self.to_store_response(order, tenant)
        self._publish(tenant.id, "order.updated", response)
        return response

    # -------------------------------------------------------------------------
    # Edición (cambios acordados por chat)
    # -------------------------------------------------------------------------

    async def edit_order(
        self,
        current_user: User,
        folio: str,
        request: StoreOrderEditRequest,
    ) -> StoreOrderResponse:
        tenant = await self._require_tenant(current_user)
        order = await self._require_order(tenant.id, folio)
        self._check_version(order, request.expected_updated_at)
        if order.status not in ("NEW", "READY"):
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Sólo se puede editar un pedido que sigue activo. Reábrelo primero.",
            )

        # 1. Guardar la versión que se va a reemplazar (para "yo pedí 3")
        revisions = list(order.revisions or [])
        revisions.append(self._snapshot(order, by=current_user))
        order.revisions = revisions

        # 2. Recalcular con la misma lógica de la vitrina, pero sin el pedido mínimo:
        #    si la tienda decide dejarlo por debajo, es su decisión.
        public = PublicCatalogService(self.session)
        settings = await self.repo.get_or_create_settings(tenant.id)
        build_request = WhatsAppOrderBuildRequest(
            customer_name=request.customer_name or order.customer_name,
            customer_phone=request.customer_phone if request.customer_phone is not None else order.customer_phone,
            delivery_method=request.delivery_method,
            delivery_address=request.delivery_address,
            payment_method=PaymentMethodPreview(order.payment_method),
            # El "pago con $X" del cliente no se valida contra el nuevo total (la
            # vitrina lo rechazaría con 422); el cambio se recalcula abajo.
            cash_tendered_mxn=None,
            items=request.items,
            order_notes=request.order_notes,
        )
        computed = await public._compute_order(tenant, settings, build_request, enforce_store_rules=False)
        change_mxn: Optional[Decimal] = None
        if order.payment_method == PaymentMethodPreview.CASH.value and order.cash_tendered_mxn is not None:
            if order.cash_tendered_mxn >= computed.total_mxn:
                change_mxn = (order.cash_tendered_mxn - computed.total_mxn).quantize(Decimal("0.01"))

        order.customer_name = build_request.customer_name.strip()
        order.customer_phone = (build_request.customer_phone or "").strip() or None
        order.delivery_method = request.delivery_method.value
        order.delivery_address = (request.delivery_address or "").strip() or None
        order.order_notes = (request.order_notes or "").strip() or None
        order.items = [public._item_to_json(item) for item in computed.items]
        order.subtotal_mxn = computed.subtotal_mxn
        order.delivery_fee_mxn = computed.delivery_fee_mxn
        order.total_mxn = computed.total_mxn
        order.change_mxn = change_mxn
        order.item_count = len(computed.items)
        order.formatted_text = computed.formatted_text
        order.wa_link = computed.wa_link
        order.edited_at = datetime.now(timezone.utc)
        order.edited_by = current_user.id
        order.attended_by = current_user.id
        if order.seen_at is None:
            order.seen_at = order.edited_at
            order.seen_by = current_user.id

        await self.repo.save_order(order)
        await self._commit(tenant.id)
        response = await self.to_store_response(order, tenant)
        self._publish(tenant.id, "order.updated", response)
        return response

    # -------------------------------------------------------------------------
    # Serialización compartida (también la usa submit_order para el evento)
    # -------------------------------------------------------------------------

    async def to_store_response(self, order: CatalogOrder, tenant: Tenant) -> StoreOrderResponse:
        names = await self.repo.get_user_names([order.seen_by, order.attended_by, order.edited_by])
        revisions = []
        for raw in order.revisions or []:
            try:
                revisions.append(OrderRevisionResponse(**raw))
            except Exception:  # una revisión mal formada no debe tirar el pedido entero
                continue
        base = PublicCatalogService._order_to_response(order, tenant, include_key=True)
        return StoreOrderResponse(
            **base.model_dump(),
            seen_at=order.seen_at,
            seen_by_name=names.get(order.seen_by),
            attended_by_name=names.get(order.attended_by),
            edited_by_name=names.get(order.edited_by),
            sale_id=order.sale_id,
            revisions=revisions,
            possible_duplicate_of=await self.repo.find_possible_duplicate(order),
        )

    # -------------------------------------------------------------------------
    # Helpers
    # -------------------------------------------------------------------------

    async def _commit(self, tenant_id: uuid.UUID) -> None:
        """
        Commit + re-fijar el contexto RLS: tras el commit la sesión puede tomar otra
        conexión del pool sin `app.current_tenant`, y las consultas siguientes
        (nombres de usuario, duplicados) verían cero filas.
        """
        await self.session.commit()
        await set_tenant_context(self.session, tenant_id)

    async def _require_tenant(self, current_user: User) -> Tenant:
        tenant = await self.repo.get_tenant_by_id(current_user.tenant_id)
        if not tenant:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="El comercio de la sesión no existe.")
        return tenant

    async def _require_order(self, tenant_id: uuid.UUID, folio: str) -> CatalogOrder:
        order = await self.repo.get_order_by_folio(tenant_id, folio)
        if not order:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"El pedido '{folio}' no existe en este comercio.",
            )
        return order

    @staticmethod
    def _check_version(order: CatalogOrder, expected: Optional[datetime]) -> None:
        """
        Concurrencia optimista: si el cliente vio una versión distinta a la actual,
        alguien más cambió el pedido — se avisa y la app recarga, nunca se pisa.
        """
        if expected is None or order.updated_at is None:
            return
        current = order.updated_at
        if expected.tzinfo is None:
            expected = expected.replace(tzinfo=timezone.utc)
        if abs((current - expected).total_seconds()) > 0.001:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="Alguien más cambió este pedido. Se recarga con la versión actual.",
            )

    @staticmethod
    def _snapshot(order: CatalogOrder, by: User) -> Dict[str, Any]:
        """Instantánea JSON de la versión actual antes de editarla."""
        return {
            "at": datetime.now(timezone.utc).isoformat(),
            "by_name": by.full_name,
            "delivery_method": order.delivery_method,
            "delivery_address": order.delivery_address,
            "order_notes": order.order_notes,
            "items": list(order.items or []),
            "subtotal_mxn": str(order.subtotal_mxn),
            "delivery_fee_mxn": str(order.delivery_fee_mxn),
            "total_mxn": str(order.total_mxn),
        }

    @staticmethod
    def _publish(tenant_id: uuid.UUID, event_type: str, order: StoreOrderResponse) -> None:
        """Evento al WebSocket de la app del tendero (`order.new` / `order.updated`)."""
        order_event_hub.publish(
            tenant_id,
            {"type": event_type, "order": order.model_dump(mode="json")},
        )
