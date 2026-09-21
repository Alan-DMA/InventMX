# Importación de enumeraciones
import enum
# Importación de fecha y hora del pedido registrado
from datetime import datetime
# Importación de precisión decimal para Pesos Mexicanos
from decimal import Decimal
# Importación de tipado estático
from typing import List, Optional
# Importación de identificadores UUID
import uuid
# Importación de componentes de Pydantic v2
from pydantic import BaseModel, ConfigDict, Field


class DeliveryMethod(str, enum.Enum):
    """Método de entrega seleccionado por el cliente final."""
    PICKUP = "PICKUP"        # Recoger en tienda física
    DELIVERY = "DELIVERY"    # Entrega a domicilio


class PaymentMethodPreview(str, enum.Enum):
    """Método de pago previsto para liquidar el pedido."""
    CASH = "CASH"                        # Efectivo contra entrega
    TRANSFER = "TRANSFER"                # Transferencia bancaria / SPEI
    CARD_ON_DELIVERY = "CARD_ON_DELIVERY" # Tarjeta con terminal punto de venta portátil


class CatalogOrderStatus(str, enum.Enum):
    """Estado del pedido web del lado del tendero (migración 0020)."""
    NEW = "NEW"                # Recibido, pendiente de preparar
    READY = "READY"            # Preparado: listo para recoger o para salir
    DELIVERED = "DELIVERED"    # Entregado (con o sin venta ligada)
    CANCELLED = "CANCELLED"    # Cerrado sin entregar


class CancelReason(str, enum.Enum):
    """Motivo de cancelación — un toque en la app, alimenta reportes."""
    CUSTOMER_CANCELLED = "CUSTOMER_CANCELLED"  # El cliente se retractó por chat
    OUT_OF_STOCK = "OUT_OF_STOCK"              # No había existencias
    NEVER_CONFIRMED = "NEVER_CONFIRMED"        # Nunca mandó el WhatsApp / no contestó
    DUPLICATE = "DUPLICATE"                    # Pedido repetido
    SPAM = "SPAM"                              # Broma o pedido falso
    OTHER = "OTHER"


class PublicStoreInfoResponse(BaseModel):
    """Información pública del comercio para la cabecera del catálogo web."""
    name: str = Field(description="Nombre comercial de la tienda")
    slug: str = Field(description="Identificador URL amigable (ej: abarrotes-don-pepe)")
    whatsapp_number: Optional[str] = Field(default=None, description="Número de WhatsApp configurado")
    welcome_message: Optional[str] = Field(default=None, description="Mensaje de bienvenida")
    business_hours: Optional[str] = Field(default=None, description="Horario de atención")
    min_order_amount_mxn: Decimal = Field(default=Decimal("0.00"), description="Monto mínimo de pedido en $ MXN")
    delivery_fee_mxn: Decimal = Field(default=Decimal("0.00"), description="Costo de entrega en $ MXN")
    delivery_enabled: bool = Field(default=True, description="Servicio a domicilio disponible")
    pickup_enabled: bool = Field(default=True, description="Recogida en tienda disponible")
    is_catalog_enabled: bool = Field(default=True, description="Estado operativo del catálogo")

    model_config = ConfigDict(from_attributes=True)


class PublicProductItemResponse(BaseModel):
    """Renglón de producto visible en el catálogo público."""
    id: uuid.UUID = Field(description="ID único del producto")
    name: str = Field(description="Nombre comercial del producto")
    sku: str = Field(description="Código SKU")
    category_id: Optional[uuid.UUID] = Field(default=None, description="ID de categoría")
    category_name: Optional[str] = Field(default=None, description="Nombre de la categoría")
    price_mxn: Decimal = Field(description="Precio de venta en Pesos Mexicanos ($ MXN)")
    image_url: Optional[str] = Field(default=None, description="Enlace a la fotografía")
    in_stock: bool = Field(default=True, description="Indica si cuenta con existencias disponibles")
    available_stock: Decimal = Field(default=Decimal("0.00"), description="Cantidad disponible en almacén")

    model_config = ConfigDict(from_attributes=True)


class PublicCategoryResponse(BaseModel):
    """Categoría con contador de artículos disponibles."""
    id: uuid.UUID = Field(description="ID de la categoría")
    name: str = Field(description="Nombre de la categoría")
    product_count: int = Field(default=0, description="Cantidad de productos activos en la categoría")

    model_config = ConfigDict(from_attributes=True)


class PublicCatalogResponse(BaseModel):
    """Respuesta completa del catálogo digital público (RF-23)."""
    store: PublicStoreInfoResponse = Field(description="Datos del comercio")
    categories: List[PublicCategoryResponse] = Field(default_factory=list, description="Categorías de artículos")
    products: List[PublicProductItemResponse] = Field(default_factory=list, description="Listado de productos")
    total_products: int = Field(default=0, description="Total de productos catalogados")


class PublicProductDetailResponse(BaseModel):
    """Detalle completo de un producto para vista individual y metadatos."""
    id: uuid.UUID = Field(description="ID único del producto")
    name: str = Field(description="Nombre del producto")
    sku: str = Field(description="SKU interno")
    barcode: Optional[str] = Field(default=None, description="Código de barras EAN/UPC")
    category_name: Optional[str] = Field(default=None, description="Categoría")
    price_mxn: Decimal = Field(description="Precio en Pesos Mexicanos ($ MXN)")
    image_url: Optional[str] = Field(default=None, description="Fotografía del producto")
    in_stock: bool = Field(description="Disponibilidad física")
    available_stock: Decimal = Field(description="Stock disponible")
    store_name: str = Field(description="Nombre de la tienda")
    store_slug: str = Field(description="Slug de la tienda")
    store_whatsapp: Optional[str] = Field(default=None, description="WhatsApp de la tienda")


class WhatsAppOrderItemRequest(BaseModel):
    """Artículo individual agregado al carrito de compras."""
    product_id: uuid.UUID = Field(description="ID del producto solicitado")
    quantity: Decimal = Field(gt=0, description="Cantidad solicitada")
    notes: Optional[str] = Field(default=None, max_length=200, description="Instrucción especial (ej: bien frío)")


class WhatsAppOrderBuildRequest(BaseModel):
    """Solicitud de generación de pedido y enlace de WhatsApp (RF-24)."""
    customer_name: str = Field(min_length=2, max_length=100, description="Nombre del cliente")
    customer_phone: Optional[str] = Field(default=None, max_length=20, description="Teléfono del cliente")
    delivery_method: DeliveryMethod = Field(default=DeliveryMethod.PICKUP, description="Método de entrega")
    delivery_address: Optional[str] = Field(default=None, max_length=300, description="Dirección si es a domicilio")
    payment_method: PaymentMethodPreview = Field(default=PaymentMethodPreview.CASH, description="Forma de pago")
    cash_tendered_mxn: Optional[Decimal] = Field(
        default=None,
        ge=0,
        description="Monto en efectivo con el que pagará para calcular cambio exacto",
    )
    items: List[WhatsAppOrderItemRequest] = Field(min_length=1, description="Lista de artículos seleccionados")
    order_notes: Optional[str] = Field(default=None, max_length=500, description="Notas generales del pedido")


class WhatsAppOrderBuildResponse(BaseModel):
    """Respuesta con el enlace universal wa.me y texto estructurado."""
    wa_link: str = Field(description="Enlace directo a WhatsApp con texto codificado (https://wa.me/...)")
    formatted_text: str = Field(description="Mensaje formateado con emojis y desglose en Pesos Mexicanos")
    subtotal_mxn: Decimal = Field(description="Subtotal de productos en $ MXN")
    delivery_fee_mxn: Decimal = Field(default=Decimal("0.00"), description="Costo de entrega en $ MXN")
    total_mxn: Decimal = Field(description="Importe total a pagar en $ MXN")
    change_mxn: Optional[Decimal] = Field(default=None, description="Cambio a entregar al cliente si pagó en efectivo")
    item_count: int = Field(description="Cantidad de renglones solicitados")


class OpenGraphMetaResponse(BaseModel):
    """Metadatos OpenGraph para previsualización enriquecida al compartir enlaces (Const. Art. 7.4)."""
    og_title: str = Field(description="Título para la tarjeta de previsualización")
    og_description: str = Field(description="Descripción comercial")
    og_image: Optional[str] = Field(default=None, description="Imagen destacada para redes sociales y WhatsApp")
    og_url: str = Field(description="URL canónica del catálogo o producto")
    og_price_amount: Optional[Decimal] = Field(default=None, description="Precio numérico en caso de ser producto")
    og_price_currency: str = Field(default="MXN", description="Código de divisa ISO 4217 (MXN)")


class CatalogSettingsResponse(BaseModel):
    """Configuración actual del catálogo digital del comercio (RF-26)."""
    id: uuid.UUID = Field(description="ID de la configuración")
    tenant_id: uuid.UUID = Field(description="ID del comercio")
    # Nombre y slug del comercio: el panel "Mi catálogo" los necesita para armar
    # el enlace público y el QR sin depender de lo que guardó el login.
    store_name: str = Field(description="Nombre comercial de la tienda")
    store_slug: str = Field(description="Slug público de la tienda (/tienda/{slug})")
    is_catalog_enabled: bool = Field(description="Catálogo web activado")
    whatsapp_number: Optional[str] = Field(default=None, description="Número de WhatsApp oficial")
    welcome_message: Optional[str] = Field(default=None, description="Mensaje de bienvenida")
    min_order_amount_mxn: Decimal = Field(description="Monto mínimo de pedido en $ MXN")
    delivery_fee_mxn: Decimal = Field(description="Costo de entrega en $ MXN")
    delivery_enabled: bool = Field(description="Entrega a domicilio permitida")
    pickup_enabled: bool = Field(description="Recoger en tienda permitido")
    business_hours: Optional[str] = Field(default=None, description="Horario de atención")

    model_config = ConfigDict(from_attributes=True)


class CatalogSettingsUpdateRequest(BaseModel):
    """Actualización de parámetros del catálogo por parte del dueño."""
    is_catalog_enabled: Optional[bool] = Field(default=None, description="Habilitar/Deshabilitar catálogo")
    whatsapp_number: Optional[str] = Field(default=None, max_length=20, description="Número de WhatsApp")
    welcome_message: Optional[str] = Field(default=None, max_length=1000, description="Mensaje de bienvenida")
    min_order_amount_mxn: Optional[Decimal] = Field(default=None, ge=0, description="Monto mínimo en $ MXN")
    delivery_fee_mxn: Optional[Decimal] = Field(default=None, ge=0, description="Costo de envío en $ MXN")
    delivery_enabled: Optional[bool] = Field(default=None, description="Permitir envíos")
    pickup_enabled: Optional[bool] = Field(default=None, description="Permitir pickup")
    business_hours: Optional[str] = Field(default=None, max_length=500, description="Horario de servicio")


class CatalogOrderItemResponse(BaseModel):
    """Renglón de un pedido registrado — instantánea del producto al momento de pedir."""
    product_id: uuid.UUID = Field(description="ID del producto pedido")
    name: str = Field(description="Nombre del producto al momento del pedido")
    sku: str = Field(description="SKU del producto")
    category_id: Optional[uuid.UUID] = Field(default=None, description="ID de categoría")
    category_name: Optional[str] = Field(default=None, description="Nombre de categoría")
    price_mxn: Decimal = Field(description="Precio unitario en $ MXN al momento del pedido")
    image_url: Optional[str] = Field(default=None, description="Fotografía del producto")
    quantity: Decimal = Field(gt=0, description="Cantidad pedida")
    notes: Optional[str] = Field(default=None, description="Instrucción especial del renglón")
    total_mxn: Decimal = Field(description="Importe del renglón en $ MXN")


class CatalogOrderResponse(BaseModel):
    """
    Pedido registrado desde la vitrina (RF-24). Es lo que abre la tienda desde el
    enlace del chat: el mensaje de WhatsApp solo lleva folio, total y este enlace.
    """
    folio: str = Field(description="Folio corto del pedido (P-260918-3F2A)")
    store_slug: str = Field(description="Slug de la tienda")
    store_name: str = Field(description="Nombre de la tienda")
    created_at: datetime = Field(description="Fecha y hora en que se registró el pedido")
    customer_name: str = Field(description="Nombre del cliente")
    customer_phone: Optional[str] = Field(default=None, description="Teléfono del cliente")
    delivery_method: DeliveryMethod = Field(description="Método de entrega")
    delivery_address: Optional[str] = Field(default=None, description="Dirección si es a domicilio")
    payment_method: PaymentMethodPreview = Field(description="Forma de pago prevista")
    cash_tendered_mxn: Optional[Decimal] = Field(default=None, description="Con cuánto paga (efectivo)")
    order_notes: Optional[str] = Field(default=None, description="Observaciones generales")
    items: List[CatalogOrderItemResponse] = Field(default_factory=list, description="Renglones del pedido")
    subtotal_mxn: Decimal = Field(description="Subtotal en $ MXN")
    delivery_fee_mxn: Decimal = Field(default=Decimal("0.00"), description="Costo de envío en $ MXN")
    total_mxn: Decimal = Field(description="Total a pagar en $ MXN")
    change_mxn: Optional[Decimal] = Field(default=None, description="Cambio a devolver si pagó en efectivo")
    item_count: int = Field(description="Cantidad de renglones")
    wa_link: str = Field(description="Enlace wa.me con el mensaje completo")
    formatted_text: str = Field(description="Mensaje formateado completo del pedido")
    # Estado visible también en el ticket público (el cliente ve "Listo para recoger")
    status: CatalogOrderStatus = Field(default=CatalogOrderStatus.NEW, description="Estado del pedido")
    status_changed_at: Optional[datetime] = Field(default=None, description="Último cambio de estado")
    cancel_reason: Optional[CancelReason] = Field(default=None, description="Motivo si está cancelado")
    store_edited_at: Optional[datetime] = Field(
        default=None, description="Última edición hecha por la tienda (el ticket público la anuncia)"
    )
    updated_at: Optional[datetime] = Field(default=None, description="Versión para concurrencia optimista")
    # Sólo se entrega a quien creó el pedido (respuesta del POST) y al tendero
    # autenticado; el GET público la exige como `?k=` y no la devuelve.
    access_key: Optional[str] = Field(default=None, description="Clave del enlace del ticket (…/pedido/{folio}?k=)")


class OrderRevisionResponse(BaseModel):
    """Instantánea previa de un pedido editado por la tienda."""
    at: datetime = Field(description="Cuándo se reemplazó esta versión")
    by_name: Optional[str] = Field(default=None, description="Quién la editó")
    delivery_method: DeliveryMethod
    delivery_address: Optional[str] = None
    order_notes: Optional[str] = None
    items: List[CatalogOrderItemResponse] = Field(default_factory=list)
    subtotal_mxn: Decimal
    delivery_fee_mxn: Decimal
    total_mxn: Decimal


class StoreOrderResponse(CatalogOrderResponse):
    """
    Pedido tal como lo ve el tendero en la app: además del ticket, quién lo vio,
    quién lo atiende, la venta que lo cobró y el historial de ediciones.
    """
    seen_at: Optional[datetime] = None
    seen_by_name: Optional[str] = None
    attended_by_name: Optional[str] = None
    edited_by_name: Optional[str] = None
    sale_id: Optional[uuid.UUID] = Field(default=None, description="Venta del POS que cobró el pedido")
    revisions: List[OrderRevisionResponse] = Field(default_factory=list)
    possible_duplicate_of: Optional[str] = Field(
        default=None, description="Folio de un pedido igual del mismo cliente en los últimos minutos"
    )


class StoreOrderListResponse(BaseModel):
    """Lista de pedidos del tendero con el conteo de nuevos (badge, siempre del servidor)."""
    items: List[StoreOrderResponse] = Field(default_factory=list)
    total: int = Field(default=0, description="Total en el alcance pedido")
    new_count: int = Field(default=0, description="Pedidos en estado NEW sin ver")
    active_count: int = Field(default=0, description="Pedidos NEW + READY")


class StoreOrderStatusUpdate(BaseModel):
    """Cambio de estado desde la app (un toque)."""
    status: CatalogOrderStatus
    cancel_reason: Optional[CancelReason] = Field(default=None, description="Obligatorio al cancelar")
    sale_id: Optional[uuid.UUID] = Field(default=None, description="Venta que cobró el pedido (Cobrar en caja)")
    expected_updated_at: Optional[datetime] = Field(
        default=None, description="Versión que el cliente vio; 409 si alguien más cambió el pedido"
    )


class StoreOrderEditRequest(BaseModel):
    """Edición del pedido tras cambios acordados por chat."""
    items: List[WhatsAppOrderItemRequest] = Field(min_length=1)
    delivery_method: DeliveryMethod
    delivery_address: Optional[str] = Field(default=None, max_length=300)
    order_notes: Optional[str] = Field(default=None, max_length=500)
    customer_name: Optional[str] = Field(default=None, min_length=2, max_length=100)
    customer_phone: Optional[str] = Field(default=None, max_length=20)
    expected_updated_at: Optional[datetime] = None
