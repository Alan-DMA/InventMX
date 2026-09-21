# Importación de fecha y hora
from datetime import datetime
# Importación de precisión decimal para Pesos Mexicanos
from decimal import Decimal
# Importación de tipado estático
from typing import Any, List, Optional
# Importación de identificadores UUID
import uuid
# Importación de componentes de SQLAlchemy
from sqlalchemy import (
    CheckConstraint,
    DateTime,
    ForeignKey,
    Integer,
    Numeric,
    String,
    Text,
    UniqueConstraint,
    func,
)
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.core.database.base import Base, SCHEMA


class CatalogOrder(Base):
    """
    Pedido registrado desde la vitrina pública (RF-24, Tarea 13.2 iteración 3 de QA).

    El mensaje de WhatsApp que recibe la tienda lleva solo folio, total y enlace al
    ticket; el detalle completo vive aquí para que editar el chat no altere el pedido.
    Los renglones se guardan como instantánea (nombre y precio al momento del pedido),
    no como referencia viva al producto.
    """
    # Nombre de la tabla física en PostgreSQL
    __tablename__ = "catalog_orders"
    __table_args__ = (
        # El folio es único por comercio (dos tiendas pueden repetir folio, una no)
        UniqueConstraint("tenant_id", "folio", name="uq_catalog_orders_tenant_folio"),
        CheckConstraint("subtotal_mxn >= 0", name="chk_catalog_orders_subtotal_non_negative"),
        CheckConstraint("total_mxn >= 0", name="chk_catalog_orders_total_non_negative"),
        {"schema": SCHEMA},
    )

    # Identificador único UUID del pedido
    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        primary_key=True,
        default=uuid.uuid4,
        doc="Identificador único universal del pedido",
    )

    # Comercio dueño del pedido (Aislamiento Multi-Tenant)
    tenant_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey(f"{SCHEMA}.tenants.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
        doc="Clave foránea hacia el comercio (Tenant)",
    )

    # Folio legible que viaja en el chat: P-YYMMDD-XXXX
    folio: Mapped[str] = mapped_column(
        String(20),
        nullable=False,
        doc="Folio corto del pedido (P-260918-3F2A)",
    )

    # Datos del cliente final (sin cuenta)
    customer_name: Mapped[str] = mapped_column(String(100), nullable=False, doc="Nombre del cliente")
    customer_phone: Mapped[Optional[str]] = mapped_column(String(20), nullable=True, doc="Teléfono del cliente")

    # Entrega y pago — valores de DeliveryMethod / PaymentMethodPreview
    delivery_method: Mapped[str] = mapped_column(String(20), nullable=False, doc="PICKUP o DELIVERY")
    delivery_address: Mapped[Optional[str]] = mapped_column(String(300), nullable=True, doc="Dirección de entrega")
    payment_method: Mapped[str] = mapped_column(String(30), nullable=False, doc="CASH, TRANSFER o CARD_ON_DELIVERY")
    cash_tendered_mxn: Mapped[Optional[Decimal]] = mapped_column(
        Numeric(12, 2), nullable=True, doc="Con cuánto paga el cliente (solo efectivo)"
    )
    order_notes: Mapped[Optional[str]] = mapped_column(Text, nullable=True, doc="Observaciones generales")

    # Instantánea de los renglones: [{product_id, name, sku, price_mxn, quantity, notes, ...}]
    items: Mapped[List[Any]] = mapped_column(
        JSONB,
        nullable=False,
        default=list,
        doc="Renglones del pedido con nombre y precio al momento de pedir",
    )

    # Totales en Pesos Mexicanos calculados por el servidor
    subtotal_mxn: Mapped[Decimal] = mapped_column(Numeric(12, 2), nullable=False, doc="Subtotal en $ MXN")
    delivery_fee_mxn: Mapped[Decimal] = mapped_column(
        Numeric(12, 2), nullable=False, default=Decimal("0.00"), doc="Costo de envío en $ MXN"
    )
    total_mxn: Mapped[Decimal] = mapped_column(Numeric(12, 2), nullable=False, doc="Total a pagar en $ MXN")
    change_mxn: Mapped[Optional[Decimal]] = mapped_column(Numeric(12, 2), nullable=True, doc="Cambio a devolver")
    item_count: Mapped[int] = mapped_column(Integer, nullable=False, default=0, doc="Cantidad de renglones")

    # Clave del enlace del ticket público (migración 0021): el folio solo es
    # adivinable; sin esta clave el ticket no se abre. Viaja en el chat.
    access_key: Mapped[str] = mapped_column(String(32), nullable=False, doc="Clave del enlace público")

    # Mensaje completo y enlace wa.me, tal como los armó el servidor
    formatted_text: Mapped[str] = mapped_column(Text, nullable=False, doc="Mensaje formateado del pedido")
    wa_link: Mapped[str] = mapped_column(Text, nullable=False, doc="Enlace universal wa.me con el mensaje")

    # -------------------------------------------------------------------------
    # Ciclo de vida del lado del tendero (migración 0020)
    # NEW → READY → DELIVERED; cualquiera → CANCELLED; cerrados se pueden reabrir.
    # -------------------------------------------------------------------------
    status: Mapped[str] = mapped_column(
        String(20), nullable=False, default="NEW", doc="NEW, READY, DELIVERED o CANCELLED"
    )
    status_changed_at: Mapped[Optional[datetime]] = mapped_column(
        DateTime(timezone=True), nullable=True, doc="Último cambio de estado"
    )
    cancel_reason: Mapped[Optional[str]] = mapped_column(
        String(40), nullable=True, doc="Motivo de cancelación (CancelReason)"
    )

    # "Visto" es una marca, no un estado: se pone sola al abrir el pedido en la app
    seen_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), nullable=True)
    seen_by: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True), ForeignKey(f"{SCHEMA}.users.id", ondelete="SET NULL"), nullable=True
    )
    # Quién movió el pedido por última vez (para "Lo atiende Juan")
    attended_by: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True), ForeignKey(f"{SCHEMA}.users.id", ondelete="SET NULL"), nullable=True
    )

    # Edición tras cambios por chat: la versión anterior se guarda en `revisions`
    edited_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), nullable=True)
    edited_by: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True), ForeignKey(f"{SCHEMA}.users.id", ondelete="SET NULL"), nullable=True
    )
    revisions: Mapped[List[Any]] = mapped_column(
        JSONB, nullable=False, default=list, doc="Instantáneas previas [{at, by, items, totals, entrega}]"
    )

    # Venta del POS que cobró este pedido ("Cobrar en caja")
    sale_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True), ForeignKey(f"{SCHEMA}.sales.id", ondelete="SET NULL"), nullable=True
    )

    # Fecha y hora en que el cliente envió el pedido
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        nullable=False,
        doc="Estampa de tiempo de creación del pedido",
    )

    # Control de concurrencia optimista: el cliente manda `expected_updated_at`
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        onupdate=func.now(),
        nullable=False,
        doc="Última modificación (estado, edición, visto)",
    )
