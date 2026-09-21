# Importación de enumeraciones
import enum
# Importación del módulo datetime
from datetime import date, datetime
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
    refunds_mxn: Decimal = Field(Decimal("0.00"), description="Reembolsos del periodo en $ MXN (ya restados de las ventas netas)")
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


class DailySalesPointResponse(BaseModel):
    """Un día natural de la serie de ventas (RF-21 / dashboard en tiempo real)."""
    period: date = Field(..., description="Día natural (YYYY-MM-DD)")
    revenue_mxn: Decimal = Field(..., description="Ingreso neto del día en $ MXN (ventas − reembolsos)")
    orders_count: int = Field(..., description="Tickets cobrados en el día")
    gross_profit_mxn: Decimal = Field(..., description="Utilidad bruta del día en $ MXN")

    model_config = ConfigDict(from_attributes=True)


class DashboardPeriodInfo(BaseModel):
    """Información del periodo consultado para el Dashboard."""
    # Nombre del periodo (TODAY, YESTERDAY, WEEK, MONTH, etc.)
    period: str = Field(..., description="Periodo analizado")
    # Fecha de inicio en formato ISO
    start_date: str = Field(..., description="Fecha inicial del periodo")
    # Fecha de término en formato ISO
    end_date: str = Field(..., description="Fecha final del periodo")

    model_config = ConfigDict(from_attributes=True)


class SalesTrendsResponse(BaseModel):
    """Serie diaria de ventas del periodo; incluye en cero los días sin venta (RF-21)."""
    period_start: datetime = Field(..., description="Fecha inicial del periodo analizado")
    period_end: datetime = Field(..., description="Fecha final del periodo analizado")
    granularity: str = Field("daily", description="Granularidad de la serie (sólo 'daily' en el MVP)")
    trends: List[DailySalesPointResponse] = Field(default_factory=list, description="Un punto por día natural")

    model_config = ConfigDict(from_attributes=True)


class DashboardSalesMetrics(BaseModel):
    """Métricas de ventas en tiempo real para el Dashboard principal."""
    # Total de ingresos netos cobrados en Pesos Mexicanos
    total_revenue_mxn: Decimal = Field(..., description="Venta total neta en Pesos Mexicanos ($ MXN)")
    # Conteo de tickets de venta cobrados
    total_orders: int = Field(..., description="Número total de transacciones completadas")
    # Ticket promedio de compra
    average_ticket_mxn: Decimal = Field(..., description="Ticket promedio en Pesos Mexicanos ($ MXN)")
    # Variación porcentual contra el periodo anterior (ej. ayer)
    revenue_change_percent: Optional[Decimal] = Field(None, description="Cambio porcentual vs periodo anterior")

    model_config = ConfigDict(from_attributes=True)


class DashboardProfitability(BaseModel):
    """Métricas de rentabilidad y margen en tiempo real."""
    # Utilidad bruta en Pesos Mexicanos (Venta - COGS)
    gross_profit_mxn: Decimal = Field(..., description="Utilidad bruta en Pesos Mexicanos ($ MXN)")
    # Margen bruto porcentual sobre ventas netas
    gross_margin_percent: Decimal = Field(..., description="Margen bruto porcentual")
    # Variación porcentual del margen contra el periodo anterior (ej. ayer)
    margin_change_percent: Optional[Decimal] = Field(None, description="Cambio porcentual de margen vs periodo anterior")

    model_config = ConfigDict(from_attributes=True)


class DashboardInventoryMetrics(BaseModel):
    """Métricas de salud del inventario para el Dashboard."""
    # Total de SKUs activos
    total_products: int = Field(..., description="Total de productos activos")
    # SKUs con inventario positivo
    products_with_stock: int = Field(..., description="Productos con stock disponible")
    # Cantidad de productos en o por debajo del umbral mínimo de stock
    low_stock_alerts: int = Field(..., description="Cantidad de productos con alerta de stock bajo")
    # Valuación económica total del inventario físico
    inventory_value_mxn: Decimal = Field(..., description="Valuación del inventario a precio de costo en $ MXN")
    # Tasa de rotación opcional
    turnover_rate: Optional[Decimal] = Field(None, description="Tasa de rotación estimada")

    model_config = ConfigDict(from_attributes=True)


class PendingPurchaseAlertSchema(BaseModel):
    """Alerta de orden de compra pendiente de recepción o vencida."""
    # Identificador único de la orden de compra
    id: uuid.UUID = Field(..., description="Identificador único de la orden de compra")
    # Folio comercial (ej. OC-00012)
    folio: str = Field(..., description="Folio oficial de la orden de compra")
    # Nombre del proveedor
    supplier_name: str = Field(..., description="Nombre comercial del proveedor")
    # Monto total comprometido
    total_mxn: Decimal = Field(..., description="Monto total de la compra en $ MXN")
    # Días transcurridos desde la emisión
    days_pending: int = Field(..., description="Días transcurridos desde que se emitió la orden")
    # Indica si ya superó la fecha prometida de entrega
    is_overdue: bool = Field(..., description="Verdadero si la entrega prometida está vencida")

    model_config = ConfigDict(from_attributes=True)


class DashboardTopProductItem(BaseModel):
    """Producto destacado en el ranking del periodo."""
    # Nombre del artículo
    product_name: str = Field(..., description="Nombre del producto")
    # Unidades vendidas en el periodo
    units_sold: Decimal = Field(..., description="Cantidad de unidades vendidas")
    # Ingreso total generado
    revenue_mxn: Decimal = Field(..., description="Ingresos en Pesos Mexicanos ($ MXN)")
    # Utilidad bruta generada
    profit_mxn: Decimal = Field(..., description="Utilidad bruta en Pesos Mexicanos ($ MXN)")

    model_config = ConfigDict(from_attributes=True)


class DashboardKPIResponse(BaseModel):
    """Respuesta unificada de KPIs del Dashboard principal (docs/api/analytics.yaml)."""
    # Contexto del periodo evaluado
    period_info: DashboardPeriodInfo = Field(..., description="Datos del periodo analizado")
    # Indicadores de venta
    sales_metrics: DashboardSalesMetrics = Field(..., description="Métricas de ventas")
    # Indicadores de margen y utilidad
    profitability: DashboardProfitability = Field(..., description="Métricas de rentabilidad")
    # Indicadores de inventario
    inventory_metrics: DashboardInventoryMetrics = Field(..., description="Métricas de existencias")
    # Top 5 productos más vendidos del periodo
    top_products: List[DashboardTopProductItem] = Field(default_factory=list, description="Top productos vendidos")
    # Alertas de productos con stock bajo o agotado
    critical_stock_alerts: List[CriticalStockProductResponse] = Field(default_factory=list, description="Alertas de stock bajo")
    # Alertas de órdenes de compra pendientes o vencidas
    pending_purchases: List[PendingPurchaseAlertSchema] = Field(default_factory=list, description="Órdenes de compra pendientes")

    model_config = ConfigDict(from_attributes=True)
