# Importación de marcas de fecha y tiempo
from datetime import datetime
# Importación de precisión decimal para montos monetarios en MXN
from decimal import Decimal
# Importación de tipado estático
from typing import List, Optional
# Importación de identificadores únicos universales UUID
import uuid
# Importación de componentes de Pydantic v2
from pydantic import BaseModel, ConfigDict, Field

# Importación de enumeraciones de dominio
from app.modules.sales_pos.domain.cash_movement import CashMovementType
from app.modules.sales_pos.domain.cash_shift import DifferenceStatus, ShiftStatus


class CashShiftOpenRequest(BaseModel):
    """
    Contrato de solicitud para apertura de un nuevo turno de caja (RF-16 / Const. Art. 3.3).
    """
    # Fondo de caja inicial para cambio (debe ser >= 0.00 MXN)
    opening_balance_mxn: Decimal = Field(
        default=Decimal("0.00"),
        ge=0,
        description="Fondo inicial de efectivo asignado a la caja para cambio en Pesos Mexicanos ($ MXN)",
    )
    # Identificador de la sucursal o almacén asignado a la caja (opcional)
    warehouse_id: Optional[uuid.UUID] = Field(
        default=None,
        description="Identificador del almacén o sucursal donde opera el cajero",
    )
    # Observaciones o notas de apertura
    notes: Optional[str] = Field(
        default=None,
        max_length=500,
        description="Notas u observaciones de apertura de caja",
    )


class CashMovementCreateRequest(BaseModel):
    """
    Contrato de solicitud para registro de un movimiento manual de efectivo en caja chica (RF-16).
    """
    # Tipo de movimiento (CASH_IN = Entrada, CASH_OUT = Salida)
    movement_type: CashMovementType = Field(
        description="Tipo de movimiento de efectivo en caja chica (CASH_IN o CASH_OUT)",
    )
    # Monto en Pesos Mexicanos (estrictamente mayor a 0)
    amount_mxn: Decimal = Field(
        gt=0,
        description="Monto en Pesos Mexicanos ($ MXN) a ingresar o retirar de la caja (estrictamente > 0)",
    )
    # Motivo descriptivo obligatorio del movimiento
    reason: str = Field(
        min_length=3,
        max_length=255,
        description="Motivo o justificación del movimiento (ej: 'Pago de garrafón', 'Fondo extra')",
    )
    # Notas adicionales explicativas (opcional)
    notes: Optional[str] = Field(
        default=None,
        max_length=500,
        description="Detalles adicionales o justificación contable",
    )
    # Identificador del supervisor que autorizó el movimiento (opcional)
    authorized_by_user_id: Optional[uuid.UUID] = Field(
        default=None,
        description="Identificador del supervisor que autoriza el movimiento",
    )


class CashShiftCloseRequest(BaseModel):
    """
    Contrato de solicitud para el arqueo a ciegas y cierre de turno de caja (RF-17 / Const. Art. 7.2).
    """
    # Conteo físico de dinero en efectivo ingresado por el cajero (sin conocer el saldo esperado)
    counted_cash_mxn: Decimal = Field(
        ge=0,
        description="Monto físico real contado en caja en Pesos Mexicanos ($ MXN)",
    )
    # Observaciones o justificación de diferencias en el arqueo
    notes: Optional[str] = Field(
        default=None,
        max_length=500,
        description="Observaciones, justificación de sobrantes/faltantes o notas finales de auditoría",
    )


class CashMovementResponse(BaseModel):
    """
    Esquema de respuesta para un movimiento manual de caja chica registrado.
    """
    # Identificador único del movimiento
    id: uuid.UUID = Field(description="Identificador único del movimiento de caja")
    # Identificador del inquilino
    tenant_id: uuid.UUID = Field(description="Identificador del inquilino propietario")
    # Identificador del turno
    shift_id: uuid.UUID = Field(description="Identificador del turno de caja asociado")
    # Tipo de movimiento (CASH_IN / CASH_OUT)
    movement_type: CashMovementType = Field(description="Tipo de movimiento (Entrada o Salida)")
    # Monto en MXN
    amount_mxn: Decimal = Field(description="Monto del movimiento en Pesos Mexicanos ($ MXN)")
    # Razón o concepto
    reason: str = Field(description="Motivo del movimiento")
    # Notas adicionales
    notes: Optional[str] = Field(default=None, description="Notas adicionales")
    # Supervisor que autorizó
    authorized_by_user_id: Optional[uuid.UUID] = Field(default=None, description="Supervisor autorizador")
    # Usuario que registró
    created_by_user_id: uuid.UUID = Field(description="Usuario cajero que registró el movimiento")
    # Fecha y hora de registro
    created_at: datetime = Field(description="Fecha y hora de creación")

    # Configuración de Pydantic v2 para compatibilidad con atributos ORM
    model_config = ConfigDict(from_attributes=True)


class PaymentMethodSummary(BaseModel):
    """
    Desglose financiero consolidado por método de pago dentro de un turno de caja.
    """
    # Método de pago (CASH_MXN, CARD_TPV, SPEI, CODI, OTHER)
    payment_method: str = Field(description="Método de pago agrupado")
    # Monto total cobrado por este método en MXN
    total_mxn: Decimal = Field(description="Monto total cobrado en Pesos Mexicanos ($ MXN)")
    # Número de transacciones cobradas por este método
    transaction_count: int = Field(description="Cantidad de transacciones realizadas con este método")


class CashShiftSummaryResponse(BaseModel):
    """
    Esquema de respuesta para el resumen contable y auditoría de un turno de caja (RF-16, RF-17).
    """
    # Identificador del turno
    shift_id: uuid.UUID = Field(description="Identificador único del turno de caja")
    # Identificador del cajero
    cashier_id: uuid.UUID = Field(description="Identificador del cajero responsable")
    # Identificador de la sucursal / almacén
    warehouse_id: Optional[uuid.UUID] = Field(default=None, description="Sucursal o almacén")
    # Estado del turno
    status: ShiftStatus = Field(description="Estado del turno (OPEN o CLOSED)")
    # Fecha de apertura
    opened_at: datetime = Field(description="Fecha y hora de apertura")
    # Fecha de cierre
    closed_at: Optional[datetime] = Field(default=None, description="Fecha y hora de cierre")
    # Fondo inicial de caja
    opening_balance_mxn: Decimal = Field(description="Fondo inicial de efectivo en $ MXN")
    # Total de ventas cobradas en efectivo
    total_cash_sales_mxn: Decimal = Field(description="Ventas totales cobradas en efectivo en $ MXN")
    # Total de entradas manuales de efectivo (CASH_IN)
    total_cash_in_mxn: Decimal = Field(description="Total de depósitos manuales en $ MXN")
    # Total de salidas manuales de efectivo (CASH_OUT)
    total_cash_out_mxn: Decimal = Field(description="Total de retiros manuales o gastos en $ MXN")
    # Saldo teórico esperado de efectivo en caja
    expected_cash_mxn: Decimal = Field(description="Saldo teórico esperado en efectivo en $ MXN")
    # Conteo físico real ingresado en el arqueo
    counted_cash_mxn: Optional[Decimal] = Field(default=None, description="Efectivo físico contado en $ MXN")
    # Diferencia de arqueo (counted - expected)
    difference_mxn: Optional[Decimal] = Field(default=None, description="Diferencia monetaria en $ MXN")
    # Clasificación de la diferencia (EXACT, SURPLUS, SHORTAGE)
    difference_status: Optional[DifferenceStatus] = Field(default=None, description="Clasificación del arqueo")
    # Desglose por método de pago
    payment_methods_summary: List[PaymentMethodSummary] = Field(
        default_factory=list,
        description="Desglose de cobros por cada método de pago",
    )
    # Total de ventas brutas del turno (todos los métodos)
    total_sales_mxn: Decimal = Field(description="Ventas brutas totales en $ MXN")
    # Total de transacciones de venta completadas
    total_sales_count: int = Field(description="Cantidad de transacciones de venta")


class CashShiftResponse(BaseModel):
    """
    Esquema de respuesta detallado de un turno de caja con sus movimientos.
    """
    # Identificador único del turno
    id: uuid.UUID = Field(description="Identificador único del turno")
    # Identificador del inquilino
    tenant_id: uuid.UUID = Field(description="Identificador del inquilino")
    # Identificador del cajero responsable
    cashier_id: uuid.UUID = Field(description="Identificador del cajero responsable")
    # Identificador del almacén
    warehouse_id: Optional[uuid.UUID] = Field(default=None, description="Identificador del almacén")
    # Estado del turno (OPEN o CLOSED)
    status: ShiftStatus = Field(description="Estado del turno")
    # Fondo inicial de caja
    opening_balance_mxn: Decimal = Field(description="Fondo de caja inicial en $ MXN")
    # Conteo físico de efectivo
    counted_cash_mxn: Optional[Decimal] = Field(default=None, description="Efectivo físico contado en $ MXN")
    # Saldo esperado por el sistema
    expected_cash_mxn: Optional[Decimal] = Field(default=None, description="Saldo esperado por el sistema en $ MXN")
    # Diferencia de arqueo
    difference_mxn: Optional[Decimal] = Field(default=None, description="Diferencia monetaria en $ MXN")
    # Fecha de apertura
    opened_at: datetime = Field(description="Fecha y hora de apertura")
    # Fecha de cierre
    closed_at: Optional[datetime] = Field(default=None, description="Fecha y hora de cierre")
    # Usuario que cerró el turno
    closed_by_user_id: Optional[uuid.UUID] = Field(default=None, description="Usuario que cerró el turno")
    # Observaciones o notas
    notes: Optional[str] = Field(default=None, description="Observaciones y notas de auditoría")
    # Lista de movimientos manuales de caja chica asociados
    movements: List[CashMovementResponse] = Field(
        default_factory=list,
        description="Movimientos manuales de efectivo registrados en el turno",
    )
    # Fecha de creación
    created_at: datetime = Field(description="Fecha de creación del registro")
    # Fecha de última actualización
    updated_at: datetime = Field(description="Fecha de última modificación")

    # Configuración de Pydantic v2
    model_config = ConfigDict(from_attributes=True)
