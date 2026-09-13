# Importación de enumeraciones
import enum
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
