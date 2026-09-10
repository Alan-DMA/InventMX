# Importación de marcas de fecha
from datetime import datetime
# Importación de precisión decimal
from decimal import Decimal
# Importación de tipado estático
from typing import List, Optional
# Importación de UUID
import uuid
# Importación de Pydantic v2
from pydantic import BaseModel, ConfigDict, Field

# Importación de la enumeración de tipos de comisión
from app.modules.sales_pos.domain.commission import CommissionType


class SaleCommissionResponse(BaseModel):
    """
    Esquema de salida para el registro inmutable de comisiones devengadas por una venta (RF-10 / Const. Art. 8.2).
    """
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    tenant_id: uuid.UUID
    sale_id: uuid.UUID
    user_id: uuid.UUID
    user_name: Optional[str] = None
    commission_type: CommissionType
    commission_rate: Decimal
    base_amount_mxn: Decimal
    commission_amount_mxn: Decimal
    is_settled: bool
    settled_at: Optional[datetime] = None
    created_at: datetime


class UserCommissionSummary(BaseModel):
    """
    Resumen consolidado de comisiones para un cajero o vendedor específico en un periodo.
    """
    model_config = ConfigDict(from_attributes=True)

    user_id: uuid.UUID
    user_name: str
    user_email: str
    total_sales_count: int
    total_sales_amount_mxn: Decimal
    total_commission_amount_mxn: Decimal
    pending_settlement_mxn: Decimal
    settled_commission_mxn: Decimal


class CommissionSummaryResponse(BaseModel):
    """
    Esquema de respuesta para la reportería ejecutiva de comisiones del comercio.
    """
    model_config = ConfigDict(from_attributes=True)

    start_date: Optional[datetime] = None
    end_date: Optional[datetime] = None
    total_commissions_mxn: Decimal
    total_sales_count: int
    summaries_by_user: List[UserCommissionSummary]
