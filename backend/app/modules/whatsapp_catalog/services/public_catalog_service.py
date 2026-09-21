# Importación de precisión decimal para Pesos Mexicanos
from dataclasses import dataclass
from datetime import datetime, timezone
from decimal import Decimal
import secrets
# Importación de codificación URL para enlaces wa.me
import urllib.parse
# Importación de tipado estático
from typing import Any, Dict, List, Optional, Tuple
# Importación de identificadores UUID
import uuid

# Importación de excepciones HTTP de FastAPI
from fastapi import HTTPException, status
# Importación de la sesión asíncrona de base de datos y set_tenant_context
from sqlalchemy.ext.asyncio import AsyncSession
from app.core.database.session import set_tenant_context

# Importación de repositorios de dominio
from app.modules.auth_tenancy.domain.tenant import Tenant
from app.modules.whatsapp_catalog.domain.catalog_order import CatalogOrder
from app.modules.whatsapp_catalog.domain.catalog_settings import CatalogSettings
from app.modules.whatsapp_catalog.repositories.catalog_repository import CatalogRepository
# Importación de esquemas Pydantic
from app.modules.whatsapp_catalog.schemas.public_catalog import (
    CancelReason,
    CatalogOrderItemResponse,
    CatalogOrderResponse,
    CatalogOrderStatus,
    DeliveryMethod,
    OpenGraphMetaResponse,
    PaymentMethodPreview,
    PublicCatalogResponse,
    PublicCategoryResponse,
    PublicProductDetailResponse,
    PublicProductItemResponse,
    PublicStoreInfoResponse,
    WhatsAppOrderBuildRequest,
    WhatsAppOrderBuildResponse,
)


@dataclass
class _OrderItem:
    """Renglón validado del pedido con la instantánea del producto."""
    product_id: uuid.UUID
    name: str
    sku: str
    category_id: Optional[uuid.UUID]
    category_name: Optional[str]
    price_mxn: Decimal
    image_url: Optional[str]
    quantity: Decimal
    notes: Optional[str]
    total_mxn: Decimal


@dataclass
class _ComputedOrder:
    """Totales, mensaje y enlace de un pedido ya validado contra la tienda."""
    items: List[_OrderItem]
    subtotal_mxn: Decimal
    delivery_fee_mxn: Decimal
    total_mxn: Decimal
    change_mxn: Optional[Decimal]
    formatted_text: str
    wa_link: str


class PublicCatalogService:
    """
    Servicio de Catálogo Web Público y Constructor de Pedidos de WhatsApp (RF-23, RF-24 / Const. Art. 7.4).
    Permite consulta abierta por slug, cálculo de carritos en $ MXN y generación de enlaces universales wa.me.
    """

    def __init__(self, session: AsyncSession) -> None:
        # Inyección del repositorio de catálogo
        self.session = session
        self.repo = CatalogRepository(session)

    async def get_public_catalog(
        self,
        slug: str,
        category_id: Optional[uuid.UUID] = None,
        search: Optional[str] = None,
    ) -> PublicCatalogResponse:
        """
        Obtiene el catálogo público de la tienda por su slug.
        No requiere autenticación (acceso libre para clientes).
        """
        # 1. Resolver el comercio por su slug
        tenant = await self.repo.get_tenant_by_slug(slug)
        if not tenant:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"La tienda con identificador '{slug}' no existe o se encuentra inactiva.",
            )

        # 2. Inyectar contexto de tenant para consistencia RLS
        await set_tenant_context(self.session, tenant.id)

        # 3. Obtener configuraciones del catálogo
        settings = await self.repo.get_or_create_settings(tenant.id)
        if not settings.is_catalog_enabled:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="El catálogo digital de este comercio se encuentra temporalmente suspendido.",
            )

        # 4. Obtener categorías con productos activos
        raw_cats = await self.repo.get_public_categories(tenant.id)
        categories_dto = [
            PublicCategoryResponse(
                id=c.id,
                name=c.name,
                product_count=count,
            )
            for c, count in raw_cats
        ]

        # 5. Obtener productos activos visibles
        raw_prods = await self.repo.get_public_products(
            tenant_id=tenant.id,
            category_id=category_id,
            search=search,
        )
        products_dto = [
            PublicProductItemResponse(
                id=p.id,
                name=p.name,
                sku=p.sku,
                category_id=p.category_id,
                category_name=cat_name,
                price_mxn=p.price_mxn,
                image_url=p.image_url,
                in_stock=stock_qty > 0,
                available_stock=stock_qty,
            )
            for p, stock_qty, cat_name in raw_prods
        ]

        # 6. Construir información pública del comercio
        store_info = PublicStoreInfoResponse(
            name=tenant.name,
            slug=tenant.slug,
            whatsapp_number=settings.whatsapp_number,
            welcome_message=settings.welcome_message,
            business_hours=settings.business_hours,
            min_order_amount_mxn=settings.min_order_amount_mxn,
            delivery_fee_mxn=settings.delivery_fee_mxn,
            delivery_enabled=settings.delivery_enabled,
            pickup_enabled=settings.pickup_enabled,
            is_catalog_enabled=settings.is_catalog_enabled,
        )

        return PublicCatalogResponse(
            store=store_info,
            categories=categories_dto,
            products=products_dto,
            total_products=len(products_dto),
        )

    async def get_public_product_detail(
        self,
        slug: str,
        product_id: uuid.UUID,
    ) -> PublicProductDetailResponse:
        """
        Obtiene la ficha pública individual de un producto con existencias y metadatos.
        """
        tenant = await self.repo.get_tenant_by_slug(slug)
        if not tenant:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"Comercio '{slug}' no encontrado.",
            )

        await set_tenant_context(self.session, tenant.id)

        settings = await self.repo.get_or_create_settings(tenant.id)
        prod_tuple = await self.repo.get_public_product_by_id(tenant.id, product_id)
        if not prod_tuple:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="El producto solicitado no existe o no está visible en el catálogo público.",
            )

        product, stock_qty, cat_name = prod_tuple
        return PublicProductDetailResponse(
            id=product.id,
            name=product.name,
            sku=product.sku,
            barcode=product.barcode,
            category_name=cat_name,
            price_mxn=product.price_mxn,
            image_url=product.image_url,
            in_stock=stock_qty > 0,
            available_stock=stock_qty,
            store_name=tenant.name,
            store_slug=tenant.slug,
            store_whatsapp=settings.whatsapp_number,
        )

    async def build_whatsapp_order(
        self,
        slug: str,
        request: WhatsAppOrderBuildRequest,
    ) -> WhatsAppOrderBuildResponse:
        """
        Calcula el total del carrito en $ MXN, valida reglas de pedido mínimo y entrega,
        y genera el enlace directo wa.me con mensaje preformateado (RF-24).
        No registra nada: es la vista previa / respaldo cuando no hay folio.
        """
        tenant, settings = await self._require_open_store(slug)
        computed = await self._compute_order(tenant, settings, request)
        return WhatsAppOrderBuildResponse(
            wa_link=computed.wa_link,
            formatted_text=computed.formatted_text,
            subtotal_mxn=computed.subtotal_mxn,
            delivery_fee_mxn=computed.delivery_fee_mxn,
            total_mxn=computed.total_mxn,
            change_mxn=computed.change_mxn,
            item_count=len(computed.items),
        )

    async def submit_order(
        self,
        slug: str,
        request: WhatsAppOrderBuildRequest,
    ) -> CatalogOrderResponse:
        """
        Registra el pedido con folio (RF-24, iteración 3 de QA de la Tarea 13.2): el
        cliente manda por WhatsApp solo folio, total y enlace; la tienda abre el
        ticket completo desde ese enlace. Mismas validaciones que la vista previa.
        """
        tenant, settings = await self._require_open_store(slug)
        computed = await self._compute_order(tenant, settings, request)

        order = CatalogOrder(
            tenant_id=tenant.id,
            folio=await self._next_folio(tenant.id),
            access_key=secrets.token_urlsafe(9)[:12],
            customer_name=request.customer_name.strip(),
            customer_phone=(request.customer_phone or "").strip() or None,
            delivery_method=request.delivery_method.value,
            delivery_address=(request.delivery_address or "").strip() or None,
            payment_method=request.payment_method.value,
            cash_tendered_mxn=request.cash_tendered_mxn,
            order_notes=(request.order_notes or "").strip() or None,
            items=[self._item_to_json(item) for item in computed.items],
            subtotal_mxn=computed.subtotal_mxn,
            delivery_fee_mxn=computed.delivery_fee_mxn,
            total_mxn=computed.total_mxn,
            change_mxn=computed.change_mxn,
            item_count=len(computed.items),
            formatted_text=computed.formatted_text,
            wa_link=computed.wa_link,
        )
        order = await self.repo.create_order(order)
        # Persistir: get_db sólo cierra la sesión, sin commit el folio se perdería.
        await self.session.commit()
        # Tras el commit la conexión puede cambiar: sin re-fijar el tenant, RLS
        # ocultaría los pedidos al buscar duplicados para el evento.
        await set_tenant_context(self.session, tenant.id)

        # Avisar a la app del tendero (WebSocket) — después del commit, para que
        # quien reciba el evento ya pueda leer el pedido por GET.
        from app.modules.whatsapp_catalog.services.order_event_hub import order_event_hub
        from app.modules.whatsapp_catalog.services.store_orders_service import StoreOrdersService
        store_view = await StoreOrdersService(self.session).to_store_response(order, tenant)
        order_event_hub.publish(tenant.id, {"type": "order.new", "order": store_view.model_dump(mode="json")})

        # Quien registró el pedido recibe la clave del enlace (va en el chat).
        return self._order_to_response(order, tenant, include_key=True)

    async def get_order(self, slug: str, folio: str, access_key: Optional[str]) -> CatalogOrderResponse:
        """
        El ticket que abre el cliente desde el enlace del chat. Exige la clave
        del enlace: el folio solo es adivinable (65,536 por día y tienda) y
        el ticket trae nombre, teléfono y dirección.
        """
        tenant = await self.repo.get_tenant_by_slug(slug)
        if not tenant:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"Comercio '{slug}' no encontrado.",
            )
        await set_tenant_context(self.session, tenant.id)
        order = None
        if access_key:
            order = await self.repo.get_order_by_folio_and_key(tenant.id, folio, access_key)
        if not order:
            # Mismo 404 con o sin clave: no revelar si el folio existe.
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"El pedido '{folio}' no existe en este comercio.",
            )
        return self._order_to_response(order, tenant)

    # -------------------------------------------------------------------------
    # Helpers del pedido
    # -------------------------------------------------------------------------

    async def _require_open_store(self, slug: str) -> Tuple[Tenant, CatalogSettings]:
        """Resuelve la tienda por slug, fija el contexto RLS y exige catálogo activo."""
        tenant = await self.repo.get_tenant_by_slug(slug)
        if not tenant:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"Comercio '{slug}' no encontrado.",
            )

        await set_tenant_context(self.session, tenant.id)

        settings = await self.repo.get_or_create_settings(tenant.id)
        if not settings.is_catalog_enabled:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="El catálogo se encuentra temporalmente deshabilitado.",
            )
        return tenant, settings

    async def _compute_order(
        self,
        tenant: Tenant,
        settings: CatalogSettings,
        request: WhatsAppOrderBuildRequest,
        enforce_store_rules: bool = True,
    ) -> "_ComputedOrder":
        """
        Valida el carrito contra las reglas de la tienda y arma totales, mensaje y
        enlace wa.me. Compartido por la vista previa y el registro con folio para
        que ambos digan exactamente lo mismo. Con `enforce_store_rules=False`
        (edición desde la app) el pedido mínimo y los métodos de entrega
        habilitados no aplican: si la tienda lo decide, es su decisión.
        """
        # 1. Validar productos y calcular subtotal
        subtotal_mxn = Decimal("0.00")
        items: List[_OrderItem] = []

        for item_req in request.items:
            prod_tuple = await self.repo.get_public_product_by_id(tenant.id, item_req.product_id)
            if not prod_tuple:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail=f"El producto con ID '{item_req.product_id}' no está disponible para compra.",
                )
            product, stock_qty, cat_name = prod_tuple
            line_total = (product.price_mxn * item_req.quantity).quantize(Decimal("0.01"))
            subtotal_mxn += line_total
            items.append(_OrderItem(
                product_id=product.id,
                name=product.name,
                sku=product.sku,
                category_id=product.category_id,
                category_name=cat_name,
                price_mxn=product.price_mxn,
                image_url=product.image_url,
                quantity=item_req.quantity,
                notes=(item_req.notes or "").strip() or None,
                total_mxn=line_total,
            ))

        # 2. Validar pedido mínimo
        if enforce_store_rules and settings.min_order_amount_mxn > Decimal("0.00") and subtotal_mxn < settings.min_order_amount_mxn:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"El subtotal (${subtotal_mxn:,.2f} MXN) es menor al pedido mínimo requerido (${settings.min_order_amount_mxn:,.2f} MXN).",
            )

        # 3. Validar método de entrega y calcular costo de envío
        delivery_fee_mxn = Decimal("0.00")
        if request.delivery_method == DeliveryMethod.DELIVERY:
            if enforce_store_rules and not settings.delivery_enabled:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="Este comercio no ofrece servicio de entrega a domicilio.",
                )
            if not request.delivery_address or len(request.delivery_address.strip()) < 5:
                raise HTTPException(
                    status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                    detail="Debe proporcionar una dirección de entrega válida para pedidos a domicilio.",
                )
            delivery_fee_mxn = settings.delivery_fee_mxn
        else:
            if enforce_store_rules and not settings.pickup_enabled:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="Este comercio no permite recoger pedidos en tienda física.",
                )

        # 4. Calcular total y cambio
        total_mxn = (subtotal_mxn + delivery_fee_mxn).quantize(Decimal("0.01"))

        change_mxn: Optional[Decimal] = None
        if request.payment_method == PaymentMethodPreview.CASH and request.cash_tendered_mxn is not None:
            if request.cash_tendered_mxn < total_mxn:
                raise HTTPException(
                    status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                    detail=f"El efectivo con el que pagará (${request.cash_tendered_mxn:,.2f} MXN) no puede ser menor al total (${total_mxn:,.2f} MXN).",
                )
            change_mxn = (request.cash_tendered_mxn - total_mxn).quantize(Decimal("0.01"))

        # 5. Construir el mensaje formateado con emojis para WhatsApp
        msg_lines = [
            f"🛒 *¡NUEVO PEDIDO WEB - {tenant.name.upper()}!*",
            "--------------------------------------------",
            f"👤 *Cliente:* {request.customer_name.strip()}",
        ]
        if request.customer_phone:
            msg_lines.append(f"📱 *Teléfono:* {request.customer_phone.strip()}")

        msg_lines.append("")
        msg_lines.append("📋 *DETALLE DE PRODUCTOS:*")
        for idx, item in enumerate(items, start=1):
            qty_str = f"{item.quantity:g}"
            line_str = f"{idx}. *{item.name}* x{qty_str} - ${item.total_mxn:,.2f} MXN"
            if item.notes:
                line_str += f" _(Nota: {item.notes})_"
            msg_lines.append(line_str)

        msg_lines.append("--------------------------------------------")
        msg_lines.append(f"💵 *Subtotal:* ${subtotal_mxn:,.2f} MXN")

        if request.delivery_method == DeliveryMethod.DELIVERY:
            msg_lines.append(f"🛵 *Envío a domicilio:* ${delivery_fee_mxn:,.2f} MXN")
            msg_lines.append(f"📍 *Dirección:* {request.delivery_address.strip()}")
        else:
            msg_lines.append("🏪 *Entrega:* Recoger en tienda")

        msg_lines.append(f"💰 *TOTAL A PAGAR:* ${total_mxn:,.2f} MXN")
        msg_lines.append("--------------------------------------------")

        payment_labels = {
            PaymentMethodPreview.CASH: "Efectivo contra entrega",
            PaymentMethodPreview.TRANSFER: "Transferencia bancaria / SPEI",
            PaymentMethodPreview.CARD_ON_DELIVERY: "Tarjeta contra entrega (Terminal TPV)",
        }
        msg_lines.append(f"💳 *Forma de Pago:* {payment_labels.get(request.payment_method, 'Efectivo')}")
        if request.payment_method == PaymentMethodPreview.CASH and request.cash_tendered_mxn:
            msg_lines.append(f"💵 *Paga con:* ${request.cash_tendered_mxn:,.2f} MXN")
            msg_lines.append(f"🪙 *Cambio a devolver:* ${change_mxn:,.2f} MXN")

        if request.order_notes:
            msg_lines.append(f"📝 *Observaciones:* {request.order_notes.strip()}")

        msg_lines.append("")
        msg_lines.append("_Pedido generado vía InventMX Catálogo Digital_")

        formatted_text = "\n".join(msg_lines)

        # 6. Generar enlace universal wa.me con el mensaje codificado
        phone = self._clean_phone(settings.whatsapp_number)
        encoded_text = urllib.parse.quote(formatted_text)
        wa_link = f"https://wa.me/{phone}?text={encoded_text}" if phone else f"https://wa.me/?text={encoded_text}"

        return _ComputedOrder(
            items=items,
            subtotal_mxn=subtotal_mxn,
            delivery_fee_mxn=delivery_fee_mxn,
            total_mxn=total_mxn,
            change_mxn=change_mxn,
            formatted_text=formatted_text,
            wa_link=wa_link,
        )

    async def _next_folio(self, tenant_id: uuid.UUID) -> str:
        """
        Folio corto y legible para el chat: `P-YYMMDD-XXXX` (fecha + 4 hex al azar).
        Único por comercio; ante colisión (1 en 65,536 por día) se vuelve a sortear.
        """
        today = datetime.now(timezone.utc).strftime("%y%m%d")
        for _ in range(10):
            candidate = f"P-{today}-{secrets.token_hex(2).upper()}"
            if not await self.repo.folio_exists(tenant_id, candidate):
                return candidate
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="No fue posible asignar un folio al pedido. Intente de nuevo.",
        )

    @staticmethod
    def _item_to_json(item: "_OrderItem") -> Dict[str, Any]:
        """Instantánea del renglón para la columna JSONB (UUID/Decimal como texto)."""
        return {
            "product_id": str(item.product_id),
            "name": item.name,
            "sku": item.sku,
            "category_id": str(item.category_id) if item.category_id else None,
            "category_name": item.category_name,
            "price_mxn": str(item.price_mxn),
            "image_url": item.image_url,
            "quantity": str(item.quantity),
            "notes": item.notes,
            "total_mxn": str(item.total_mxn),
        }

    @staticmethod
    def _order_to_response(
        order: CatalogOrder, tenant: Tenant, include_key: bool = False
    ) -> CatalogOrderResponse:
        """Serializa el pedido registrado para la vitrina y el ticket de la tienda."""
        return CatalogOrderResponse(
            access_key=order.access_key if include_key else None,
            folio=order.folio,
            store_slug=tenant.slug,
            store_name=tenant.name,
            created_at=order.created_at,
            customer_name=order.customer_name,
            customer_phone=order.customer_phone,
            delivery_method=DeliveryMethod(order.delivery_method),
            delivery_address=order.delivery_address,
            payment_method=PaymentMethodPreview(order.payment_method),
            cash_tendered_mxn=order.cash_tendered_mxn,
            order_notes=order.order_notes,
            items=[CatalogOrderItemResponse(**item) for item in (order.items or [])],
            subtotal_mxn=order.subtotal_mxn,
            delivery_fee_mxn=order.delivery_fee_mxn,
            total_mxn=order.total_mxn,
            change_mxn=order.change_mxn,
            item_count=order.item_count,
            wa_link=order.wa_link,
            formatted_text=order.formatted_text,
            status=CatalogOrderStatus(order.status or "NEW"),
            status_changed_at=order.status_changed_at,
            cancel_reason=CancelReason(order.cancel_reason) if order.cancel_reason else None,
            store_edited_at=order.edited_at,
            updated_at=order.updated_at,
        )

    async def get_og_metadata(
        self,
        slug: str,
        product_id: Optional[uuid.UUID] = None,
    ) -> OpenGraphMetaResponse:
        """
        Genera metadatos OpenGraph para Server-Side Rendering (SSR) y previsualizaciones
        enriquecidas al compartir en WhatsApp / Facebook / Twitter (Const. Art. 7.4).
        """
        tenant = await self.repo.get_tenant_by_slug(slug)
        if not tenant:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Tienda no encontrada.",
            )

        await set_tenant_context(self.session, tenant.id)

        settings = await self.repo.get_or_create_settings(tenant.id)

        if product_id:
            prod_tuple = await self.repo.get_public_product_by_id(tenant.id, product_id)
            if prod_tuple:
                prod, _, cat_name = prod_tuple
                desc = f"${prod.price_mxn:,.2f} MXN - {prod.name}. Disponible en {tenant.name}."
                if cat_name:
                    desc += f" Categoría: {cat_name}."
                return OpenGraphMetaResponse(
                    og_title=f"{prod.name} - {tenant.name}",
                    og_description=desc,
                    og_image=prod.image_url,
                    og_url=f"https://inventmx.app/c/{tenant.slug}/p/{prod.id}",
                    og_price_amount=prod.price_mxn,
                    og_price_currency="MXN",
                )

        # Metadatos a nivel catálogo de tienda
        welcome = settings.welcome_message or f"Consulta el catálogo digital y haz tus pedidos por WhatsApp en {tenant.name}."
        return OpenGraphMetaResponse(
            og_title=f"Catálogo Digital - {tenant.name}",
            og_description=welcome,
            og_image=None,
            og_url=f"https://inventmx.app/c/{tenant.slug}",
            og_price_amount=None,
            og_price_currency="MXN",
        )

    def _clean_phone(self, phone: Optional[str]) -> str:
        """Normaliza el número telefónico para formato internacional de WhatsApp (México +52)."""
        if not phone:
            return ""
        digits = "".join(c for c in phone if c.isdigit())
        if len(digits) == 10:
            return f"52{digits}"
        if len(digits) == 12 and digits.startswith("52"):
            return digits
        return digits
