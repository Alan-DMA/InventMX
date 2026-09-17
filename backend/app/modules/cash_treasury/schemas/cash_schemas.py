# Importación de fecha y hora
from datetime import datetime
# Importación de precisión decimal para moneda mexicana MXN
from decimal import Decimal
# Importación de enumeraciones
from enum import Enum
# Importación de tipado estático
from typing import Any, Dict, List, Optional
# Importación de identificadores UUID
import uuid

# Importación de componentes de Pydantic v2
from pydantic import BaseModel, ConfigDict, Field

# Importación de enums de turnos
from app.modules.sales_pos.domain.cash_shift import ShiftStatus


class CashBalanceResult(str, Enum):
    """Resultado del arqueo de caja frente al saldo teórico."""
    EXACT = "EXACT"  # Cuadre exacto (diferencia 0.00)
    SHORT = "SHORT"  # Faltante de efectivo en caja
    OVER = "OVER"    # Sobrante de efectivo en caja


class CashMovementTypeParam(str, Enum):
    """Tipos canónicos de movimientos de caja menor según OpenAPI."""
    WITHDRAWAL = "WITHDRAWAL"  # Salida o retiro de efectivo (CASH_OUT)
    DEPOSIT = "DEPOSIT"        # Entrada o depósito de cambio (CASH_IN)


class BanxicoDenominationsInput(BaseModel):
    """
    Desglose del cono monetario oficial de Banxico.
    Coincide con BanxicoCount en Flutter (banxico_denomination.dart)
    y BanxicoDenominations en docs/api/components.yaml.
    """
    bills_1000: int = Field(default=0, ge=0, description="Piezas de billete de $1,000 MXN")
    bills_500: int = Field(default=0, ge=0, description="Piezas de billete de $500 MXN")
    bills_200: int = Field(default=0, ge=0, description="Piezas de billete de $200 MXN")
    bills_100: int = Field(default=0, ge=0, description="Piezas de billete de $100 MXN")
    bills_50: int = Field(default=0, ge=0, description="Piezas de billete de $50 MXN")
    bills_20: int = Field(default=0, ge=0, description="Piezas de billete de $20 MXN")
    coins_20: int = Field(default=0, ge=0, description="Piezas de moneda de $20 MXN")
    coins_10: int = Field(default=0, ge=0, description="Piezas de moneda de $10 MXN")
    coins_5: int = Field(default=0, ge=0, description="Piezas de moneda de $5 MXN")
    coins_2: int = Field(default=0, ge=0, description="Piezas de moneda de $2 MXN")
    coins_1: int = Field(default=0, ge=0, description="Piezas de moneda de $1 MXN")
    coins_050: int = Field(default=0, ge=0, description="Piezas de moneda de $0.50 MXN")

    def to_total_mxn(self) -> Decimal:
        """Calcula el total sumado en MXN."""
        return (
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


class DigitalPaymentsSummary(BaseModel):
    """Resumen de cobros electrónicos durante el turno."""
    spei_total_mxn: Decimal = Field(default=Decimal("0.00"))
    card_tpv_total_mxn: Decimal = Field(default=Decimal("0.00"))
    codi_total_mxn: Decimal = Field(default=Decimal("0.00"))


class CashSessionOpenRequest(BaseModel):
    """Petición para iniciar un nuevo turno de caja (POST /cash/open-session)."""
    opening_amount_mxn: Decimal = Field(..., ge=0, description="Fondo inicial calculado en MXN")
    opening_denominations: Optional[BanxicoDenominationsInput] = Field(None, description="Conteo de piezas del fondo")
    warehouse_id: Optional[uuid.UUID] = Field(None, description="Sucursal o caja asociada")
    notes: Optional[str] = Field(None, max_length=200, description="Observaciones iniciales")


class CashSessionCloseRequest(BaseModel):
    """Petición para cierre de turno con arqueo físico (POST /cash/close-session)."""
    physical_denominations: BanxicoDenominationsInput = Field(..., description="Conteo físico de billetes y monedas")
    digital_payments_summary: Optional[DigitalPaymentsSummary] = Field(None, description="Totales informativos de cobros digitales")
    notes: Optional[str] = Field(None, max_length=200, description="Observaciones finales o justificación de diferencias")


class CashMovementCreateRequest(BaseModel):
    """Petición para registrar un movimiento manual de caja menor (POST /cash/sessions/{id}/movements)."""
    type: CashMovementTypeParam = Field(..., description="WITHDRAWAL (salida) o DEPOSIT (entrada)")
    amount_mxn: Decimal = Field(..., gt=0, description="Importe positivo del movimiento")
    description: str = Field(..., min_length=3, max_length=200, description="Concepto del movimiento")
    authorized_by_user_id: Optional[uuid.UUID] = Field(None, description="Usuario que autorizó el movimiento")


class CashMovementResponse(BaseModel):
    """Respuesta descriptiva de un movimiento de caja menor."""
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    shift_id: uuid.UUID
    type: str
    amount_mxn: Decimal
    description: str
    created_at: datetime


class CashSessionResponse(BaseModel):
    """Modelo de datos de una sesión de caja coincidente con CashSession en Flutter y OpenAPI."""
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    cashier_id: uuid.UUID
    cashier_name: str
    status: ShiftStatus
    opening_amount_mxn: Decimal
    expected_cash_mxn: Decimal
    physical_cash_mxn: Optional[Decimal] = None
    difference_mxn: Optional[Decimal] = None
    balance_result: Optional[CashBalanceResult] = None
    opened_at: datetime
    closed_at: Optional[datetime] = None
    notes: Optional[str] = None


class CashBalanceSummary(BaseModel):
    """Resumen comparativo del arqueo de caja."""
    expected_cash_mxn: Decimal
    physical_cash_mxn: Decimal
    difference_mxn: Decimal
    balance_result: CashBalanceResult
    sales_count: int


class CashSessionCloseResponse(BaseModel):
    """Respuesta de éxito tras el cierre de turno con arqueo físico."""
    session: CashSessionResponse
    balance_summary: CashBalanceSummary


class CashSessionReportResponse(BaseModel):
    """Reporte formal de Corte Z de la sesión de caja."""
    session_id: uuid.UUID
    cashier_name: str
    opened_at: datetime
    closed_at: Optional[datetime]
    duration_hours: float
    sales_summary: Dict[str, Any]
    cash_balance: Dict[str, Any]
    denominations_breakdown: Optional[Dict[str, int]] = None
    movements_summary: Dict[str, Any]
    pdf_url: Optional[str] = None
