# Importación de enumeraciones
import enum
# Importación del módulo datetime
from datetime import datetime
# Importación del módulo decimal para operaciones monetarias exactas
from decimal import Decimal
# Importación de tipado estático
from typing import Dict, List, Optional
# Importación de identificadores UUID
import uuid

# Importación de Pydantic v2
from pydantic import BaseModel, ConfigDict, Field


class DateRangePreset(str, enum.Enum):
    """Rangos predefinidos para filtros analíticos y reportes."""
    TODAY = "TODAY"
    THIS_WEEK = "THIS_WEEK"
    THIS_MONTH = "THIS_MONTH"
    LAST_MONTH = "LAST_MONTH"
    CUSTOM = "CUSTOM"


class PaymentMethodMetric(BaseModel):
    """Métrica desglosada por método de pago."""
    payment_method: str = Field(..., description="Método de pago (CASH, CARD, TRANSFER, CREDIT, etc.)")
    total_mxn: Decimal = Field(..., description="Monto total cobrado en Pesos Mexicanos ($ MXN)")
    transaction_count: int = Field(..., description="Número de transacciones registradas")
    percentage: Decimal = Field(..., description="Porcentaje respecto al total de ventas")

    model_config = ConfigDict(from_attributes=True)


class ExecutiveFinancialSummaryResponse(BaseModel):
    """Resumen financiero ejecutivo de rentabilidad (RF-18 / Const. Art. 7.6)."""
    period_start: datetime = Field(..., description="Fecha inicial del periodo analizado")
    period_end: datetime = Field(..., description="Fecha final del periodo analizado")
    gross_sales_mxn: Decimal = Field(..., description="Ventas brutas totales en $ MXN")
    discounts_mxn: Decimal = Field(..., description="Descuentos aplicados en $ MXN")
    net_sales_mxn: Decimal = Field(..., description="Ventas netas totales en $ MXN")
    cogs_mxn: Decimal = Field(..., description="Costo de lo Vendido (COGS) en $ MXN basado en costo histórico congelado")
    gross_profit_mxn: Decimal = Field(..., description="Utilidad bruta en $ MXN (Ventas Netas - COGS)")
    profit_margin_pct: Decimal = Field(..., description="Margen de utilidad bruta porcentual (Gross Profit / Net Sales * 100)")
    average_ticket_mxn: Decimal = Field(..., description="Ticket promedio por venta en $ MXN")
    total_transactions: int = Field(..., description="Cantidad total de ventas completadas en el periodo")
    payment_methods: List[PaymentMethodMetric] = Field(default_factory=list, description="Desglose por método de pago")

    model_config = ConfigDict(from_attributes=True)


class CashFlowSummaryResponse(BaseModel):
    """Resumen de Flujo de Caja y Tesorería Real (RF-19 / Const. Art. 7.6)."""
    period_start: datetime = Field(..., description="Fecha inicial del periodo analizado")
    period_end: datetime = Field(..., description="Fecha final del periodo analizado")
    cash_sales_inflow_mxn: Decimal = Field(..., description="Entradas por ventas de contado en efectivo en $ MXN")
    credit_collections_inflow_mxn: Decimal = Field(..., description="Entradas por cobranza de créditos a clientes en $ MXN")
    cash_income_movements_mxn: Decimal = Field(..., description="Otras entradas manuales a caja en $ MXN")
    total_inflow_mxn: Decimal = Field(..., description="Total general de entradas de efectivo en $ MXN")
    
    supplier_payments_outflow_mxn: Decimal = Field(..., description="Salidas por pagos a proveedores en $ MXN")
    cash_expense_movements_mxn: Decimal = Field(..., description="Salidas por gastos operativos y retiros de caja en $ MXN")
    total_outflow_mxn: Decimal = Field(..., description="Total general de salidas de efectivo en $ MXN")
    
    net_cash_flow_mxn: Decimal = Field(..., description="Flujo de caja neto del periodo en $ MXN (Entradas - Salidas)")

    model_config = ConfigDict(from_attributes=True)


class TopSellingProductResponse(BaseModel):
    """Métrica de rotación para productos más vendidos (RF-20)."""
    product_id: uuid.UUID = Field(..., description="Identificador del producto")
    product_name: str = Field(..., description="Nombre comercial del producto")
    sku: str = Field(..., description="Código SKU o de barras")
    units_sold: Decimal = Field(..., description="Total de unidades o kilogramos vendidos")
    revenue_mxn: Decimal = Field(..., description="Ingresos brutos generados en $ MXN")
    profit_mxn: Decimal = Field(..., description="Utilidad bruta generada en $ MXN")

    model_config = ConfigDict(from_attributes=True)


class CriticalStockProductResponse(BaseModel):
    """Producto con existencias en nivel de alerta crítica (RF-20)."""
    product_id: uuid.UUID = Field(..., description="Identificador del producto")
    product_name: str = Field(..., description="Nombre comercial del producto")
    sku: str = Field(..., description="Código SKU o de barras")
    current_stock: Decimal = Field(..., description="Existencias físicas actuales")
    min_stock: Decimal = Field(..., description="Umbral de stock mínimo configurado")
    is_out_of_stock: bool = Field(..., description="Indica si el producto está totalmente agotado")

    model_config = ConfigDict(from_attributes=True)


class InventoryValuationResponse(BaseModel):
    """Valuación financiera de existencias en almacén (RF-20)."""
    total_active_skus: int = Field(..., description="Total de productos activos en catálogo")
    total_units_in_stock: Decimal = Field(..., description="Total de unidades físicas en inventario")
    total_inventory_cost_mxn: Decimal = Field(..., description="Valor total del inventario a precio de costo en $ MXN")
    total_inventory_retail_mxn: Decimal = Field(..., description="Valor total del inventario a precio de venta en $ MXN")
    potential_gross_profit_mxn: Decimal = Field(..., description="Ganancia potencial estimada en $ MXN")

    model_config = ConfigDict(from_attributes=True)


class InventoryHealthResponse(BaseModel):
    """Diagnóstico consolidado de inventario y rotación de mercancía (RF-20)."""
    valuation: InventoryValuationResponse = Field(..., description="Valuación del inventario actual")
    top_selling_products: List[TopSellingProductResponse] = Field(default_factory=list, description="Top productos más vendidos")
    critical_stock_products: List[CriticalStockProductResponse] = Field(default_factory=list, description="Artículos en nivel crítico de reorden")

    model_config = ConfigDict(from_attributes=True)


class WorkingCapitalResponse(BaseModel):
    """Diagnóstico de capital de trabajo y posición de liquidez neta (RF-21 / Const. Art. 7.6)."""
    as_of_date: datetime = Field(..., description="Fecha y hora del corte de liquidez")
    cash_in_register_mxn: Decimal = Field(..., description="Efectivo disponible en cajas activas en $ MXN")
    accounts_receivable_mxn: Decimal = Field(..., description="Cuentas por cobrar a clientes (cartera de crédito) en $ MXN")
    accounts_payable_mxn: Decimal = Field(..., description="Cuentas por pagar a proveedores pendientes en $ MXN")
    net_working_capital_mxn: Decimal = Field(..., description="Capital de trabajo neto en $ MXN (Caja + Por Cobrar - Por Pagar)")

    model_config = ConfigDict(from_attributes=True)
