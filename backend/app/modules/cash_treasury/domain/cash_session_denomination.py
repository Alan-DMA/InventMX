# Importación de precisión decimal para cálculos monetarios en Pesos Mexicanos
from decimal import Decimal
# Importación de tipado
from typing import Optional
# Importación de identificadores únicos UUID
import uuid

# Importación de componentes de SQLAlchemy
from sqlalchemy import (
    Boolean,
    DateTime,
    ForeignKey,
    Integer,
    Numeric,
    func,
)
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

# Importación de la clase Base y el esquema canónico 'public'
from app.core.database.base import Base, SCHEMA


class CashSessionDenomination(Base):
    """
    Modelo de Dominio para el Desglose Físico de Denominaciones del Cono Monetario Banxico.
    Tabla física: public.cash_session_denominations.
    Regla Constitucional: Artículo VII (7.2), Doc. Maestro RF-18 / RF-19.
    Registra el conteo pormenorizado de piezas físicas al momento de la apertura y el arqueo de cierre.
    """
    # Nombre físico de la tabla en PostgreSQL
    __tablename__ = "cash_session_denominations"
    # Esquema universal de datos
    __table_args__ = {"schema": SCHEMA}

    # Identificador único universal del registro de denominaciones
    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        primary_key=True,
        default=uuid.uuid4,
        doc="Identificador único universal del desglose de denominaciones",
    )

    # Identificador del turno / sesión de caja al que corresponde el conteo
    shift_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey(f"{SCHEMA}.cash_shifts.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
        doc="Sesión de caja a la que pertenece este conteo de efectivo",
    )

    # Identificador del comercio / tenant para aislamiento multi-inquilino estricto (RLS)
    tenant_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey(f"{SCHEMA}.tenants.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
        doc="Comercio titular del turno de caja",
    )

    # Bandera que indica si el conteo corresponde a la apertura (True) o al arqueo de cierre (False)
    is_opening: Mapped[bool] = mapped_column(
        Boolean,
        default=True,
        nullable=False,
        doc="True si es fondo inicial de apertura, False si es conteo físico de cierre",
    )

    # --- Billetes Oficiales de Banxico ---
    bills_1000: Mapped[int] = mapped_column(Integer, default=0, nullable=False, doc="Piezas de billete de $1,000 MXN")
    bills_500: Mapped[int] = mapped_column(Integer, default=0, nullable=False, doc="Piezas de billete de $500 MXN")
    bills_200: Mapped[int] = mapped_column(Integer, default=0, nullable=False, doc="Piezas de billete de $200 MXN")
    bills_100: Mapped[int] = mapped_column(Integer, default=0, nullable=False, doc="Piezas de billete de $100 MXN")
    bills_50: Mapped[int] = mapped_column(Integer, default=0, nullable=False, doc="Piezas de billete de $50 MXN")
    bills_20: Mapped[int] = mapped_column(Integer, default=0, nullable=False, doc="Piezas de billete de $20 MXN")

    # --- Monedas Oficiales de Banxico ---
    coins_20: Mapped[int] = mapped_column(Integer, default=0, nullable=False, doc="Piezas de moneda de $20 MXN")
    coins_10: Mapped[int] = mapped_column(Integer, default=0, nullable=False, doc="Piezas de moneda de $10 MXN")
    coins_5: Mapped[int] = mapped_column(Integer, default=0, nullable=False, doc="Piezas de moneda de $5 MXN")
    coins_2: Mapped[int] = mapped_column(Integer, default=0, nullable=False, doc="Piezas de moneda de $2 MXN")
    coins_1: Mapped[int] = mapped_column(Integer, default=0, nullable=False, doc="Piezas de moneda de $1 MXN")
    coins_050: Mapped[int] = mapped_column(Integer, default=0, nullable=False, doc="Piezas de moneda de $0.50 MXN (50 centavos)")

    # Monto total calculado en base a la suma ponderada de todas las piezas
    total_calculated_mxn: Mapped[Decimal] = mapped_column(
        Numeric(12, 2),
        default=Decimal("0.00"),
        nullable=False,
        doc="Suma monetaria total en Pesos Mexicanos resultante de multiplicar piezas por denominación",
    )

    # Fecha y hora de captura del conteo físico
    created_at: Mapped[DateTime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        nullable=False,
        doc="Estampa de tiempo del registro físico de denominaciones",
    )

    def calculate_total_mxn(self) -> Decimal:
        """
        Calcula el importe monetario total a partir del número de piezas por denominación.
        Garantiza precisión contable sin redondeos de punto flotante.
        """
        total = (
            Decimal(self.bills_1000) * Decimal("1000.00")
            + Decimal(self.bills_500) * Decimal("500.00")
            + Decimal(self.bills_200) * Decimal("200.00")
            + Decimal(self.bills_100) * Decimal("100.00")
            + Decimal(self.bills_50) * Decimal("50.00")
            + Decimal(self.bills_20) * Decimal("20.00")
            + Decimal(self.coins_20) * Decimal("20.00")
            + Decimal(self.coins_10) * Decimal("10.00")
            + Decimal(self.coins_5) * Decimal("5.00")
            + Decimal(self.coins_2) * Decimal("2.00")
            + Decimal(self.coins_1) * Decimal("1.00")
            + Decimal(self.coins_050) * Decimal("0.50")
        )
        self.total_calculated_mxn = total
        return total
