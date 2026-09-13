# Importación de precisión decimal para Pesos Mexicanos
from decimal import Decimal
# Importación de codificación URL para enlaces wa.me
import urllib.parse
# Importación de tipado estático
from typing import List, Optional
# Importación de identificadores UUID
import uuid

# Importación de excepciones HTTP de FastAPI
from fastapi import HTTPException, status
# Importación de la sesión asíncrona de base de datos y set_tenant_context
from sqlalchemy.ext.asyncio import AsyncSession
from app.core.database.session import set_tenant_context

# Importación de repositorios de dominio
from app.modules.whatsapp_catalog.repositories.catalog_repository import CatalogRepository
# Importación de esquemas Pydantic
from app.modules.whatsapp_catalog.schemas.public_catalog import (
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
        """
        # 1. Validar comercio
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

        # 2. Validar y cotizar partidas del carrito
        subtotal_mxn = Decimal("0.00")
        line_items_detail = []

        for item_req in request.items:
            prod_tuple = await self.repo.get_public_product_by_id(tenant.id, item_req.product_id)
            if not prod_tuple:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail=f"El producto con ID '{item_req.product_id}' no está disponible para compra.",
                )
            product, stock_qty, _ = prod_tuple
            line_total = (product.price_mxn * item_req.quantity).quantize(Decimal("0.01"))
            subtotal_mxn += line_total
            line_items_detail.append({
                "name": product.name,
                "quantity": item_req.quantity,
                "unit_price_mxn": product.price_mxn,
                "total_mxn": line_total,
                "notes": item_req.notes,
            })

        # 3. Validar Pedido Mínimo en MXN
        if settings.min_order_amount_mxn > Decimal("0.00") and subtotal_mxn < settings.min_order_amount_mxn:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"El subtotal (${subtotal_mxn:,.2f} MXN) es menor al pedido mínimo requerido (${settings.min_order_amount_mxn:,.2f} MXN).",
            )

        # 4. Validar Método de Entrega
        delivery_fee_mxn = Decimal("0.00")
        if request.delivery_method == DeliveryMethod.DELIVERY:
            if not settings.delivery_enabled:
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
            if not settings.pickup_enabled:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="Este comercio no permite recoger pedidos en tienda física.",
                )

        total_mxn = (subtotal_mxn + delivery_fee_mxn).quantize(Decimal("0.01"))

        # 5. Validar Pago en Efectivo y Cálculo de Cambio
        change_mxn: Optional[Decimal] = None
        if request.payment_method == PaymentMethodPreview.CASH and request.cash_tendered_mxn is not None:
            if request.cash_tendered_mxn < total_mxn:
                raise HTTPException(
                    status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                    detail=f"El efectivo con el que pagará (${request.cash_tendered_mxn:,.2f} MXN) no puede ser menor al total (${total_mxn:,.2f} MXN).",
                )
            change_mxn = (request.cash_tendered_mxn - total_mxn).quantize(Decimal("0.01"))

        # 6. Ensamblar Mensaje Estructurado para WhatsApp
        msg_lines = [
            f"🛒 *¡NUEVO PEDIDO WEB - {tenant.name.upper()}!*",
            "--------------------------------------------",
            f"👤 *Cliente:* {request.customer_name.strip()}",
        ]
        if request.customer_phone:
            msg_lines.append(f"📱 *Teléfono:* {request.customer_phone.strip()}")

        msg_lines.append("")
        msg_lines.append("📋 *DETALLE DE PRODUCTOS:*")
        for idx, item in enumerate(line_items_detail, start=1):
            qty_str = f"{item['quantity']:g}"
            line_str = f"{idx}. *{item['name']}* x{qty_str} - ${item['total_mxn']:,.2f} MXN"
            if item["notes"]:
                line_str += f" _(Nota: {item['notes']})_"
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

        # Método de pago
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

        # 7. Formatear enlace wa.me
        phone = self._clean_phone(settings.whatsapp_number)
        encoded_text = urllib.parse.quote(formatted_text)
        wa_link = f"https://wa.me/{phone}?text={encoded_text}" if phone else f"https://wa.me/?text={encoded_text}"

        return WhatsAppOrderBuildResponse(
            wa_link=wa_link,
            formatted_text=formatted_text,
            subtotal_mxn=subtotal_mxn,
            delivery_fee_mxn=delivery_fee_mxn,
            total_mxn=total_mxn,
            change_mxn=change_mxn,
            item_count=len(line_items_detail),
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
