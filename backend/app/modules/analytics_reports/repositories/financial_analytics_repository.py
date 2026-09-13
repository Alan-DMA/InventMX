# Importación de precisión decimal para Pesos Mexicanos
from datetime import datetime, time, timedelta
from decimal import Decimal
# Importación de tipado estático
from typing import Any, Dict, List, Optional, Tuple
# Importación de identificadores UUID
import uuid

# Importación de constructs de SQLAlchemy
from sqlalchemy import case, func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

# Importación de entidades de dominio
from app.modules.customers_credit.domain.customer import Customer
from app.modules.customers_credit.domain.credit_ledger import CustomerCreditLedger, LedgerEntryType
from app.modules.inventory.domain.product import Product
from app.modules.inventory.domain.product_stock import ProductStock
from app.modules.purchasing_suppliers.domain.account_payable import (
    AccountPayable,
    AccountPayableStatus,
    SupplierPaymentLedger,
)
from app.modules.sales_pos.domain.cash_movement import CashMovement, CashMovementType
from app.modules.sales_pos.domain.cash_shift import CashShift, ShiftStatus
from app.modules.sales_pos.domain.payment import PaymentMethod, SalePayment
from app.modules.sales_pos.domain.sale import Sale, SaleItem, SaleStatus


class FinancialAnalyticsRepository:
    """
    Repositorio de consultas agregadas y métricas analíticas de alta velocidad (RF-18, RF-19, RF-20, RF-21).
    """

    def __init__(self, session: AsyncSession) -> None:
        self.session = session

    async def get_financial_summary_metrics(
        self,
        tenant_id: uuid.UUID,
        start_date: datetime,
        end_date: datetime,
    ) -> Dict[str, Decimal]:
        """
        Calcula las ventas brutas, netas, descuentos, COGS histórico y utilidades en el rango de fechas.
        """
        # 1. Consulta agregada sobre ventas completadas
        sales_stmt = select(
            func.coalesce(func.sum(Sale.subtotal_mxn), Decimal("0.00")),
            func.coalesce(func.sum(Sale.discount_mxn), Decimal("0.00")),
            func.coalesce(func.sum(Sale.total_mxn), Decimal("0.00")),
            func.coalesce(func.sum(Sale.total_cost_mxn), Decimal("0.00")),
            func.count(Sale.id),
        ).where(
            Sale.tenant_id == tenant_id,
            Sale.status.in_([SaleStatus.COMPLETED, SaleStatus.PAID]),
            Sale.created_at >= start_date,
            Sale.created_at <= end_date,
        )
        sales_res = await self.session.execute(sales_stmt)
        gross_sales, discounts, net_sales, cogs_total, transaction_count = sales_res.one()

        gross_profit = (net_sales - cogs_total).quantize(Decimal("0.01"))
        profit_margin_pct = (
            (gross_profit / net_sales * Decimal("100.00")).quantize(Decimal("0.01"))
            if net_sales > Decimal("0.00")
            else Decimal("0.00")
        )
        avg_ticket = (
            (net_sales / Decimal(transaction_count)).quantize(Decimal("0.01"))
            if transaction_count > 0
            else Decimal("0.00")
        )

        return {
            "gross_sales_mxn": Decimal(str(gross_sales)).quantize(Decimal("0.01")),
            "discounts_mxn": Decimal(str(discounts)).quantize(Decimal("0.01")),
            "net_sales_mxn": Decimal(str(net_sales)).quantize(Decimal("0.01")),
            "cogs_mxn": Decimal(str(cogs_total)).quantize(Decimal("0.01")),
            "gross_profit_mxn": gross_profit,
            "profit_margin_pct": profit_margin_pct,
            "average_ticket_mxn": avg_ticket,
            "total_transactions": transaction_count,
        }

    async def get_payment_methods_breakdown(
        self,
        tenant_id: uuid.UUID,
        start_date: datetime,
        end_date: datetime,
        net_sales: Decimal,
    ) -> List[Dict[str, Any]]:
        """Calcula el desglose de ingresos por método de pago."""
        stmt = (
            select(
                SalePayment.payment_method,
                func.coalesce(
                    func.sum(SalePayment.amount_paid_mxn - SalePayment.change_returned_mxn),
                    Decimal("0.00"),
                ),
                func.count(SalePayment.id),
            )
            .join(Sale, Sale.id == SalePayment.sale_id)
            .where(
                Sale.tenant_id == tenant_id,
                Sale.status.in_([SaleStatus.COMPLETED, SaleStatus.PAID]),
                Sale.created_at >= start_date,
                Sale.created_at <= end_date,
            )
            .group_by(SalePayment.payment_method)
        )
        result = await self.session.execute(stmt)
        rows = result.all()

        breakdown: List[Dict[str, Any]] = []
        for method, total_amount, count in rows:
            method_str = method.value if hasattr(method, "value") else str(method)
            pct = (
                (Decimal(str(total_amount)) / net_sales * Decimal("100.00")).quantize(Decimal("0.01"))
                if net_sales > Decimal("0.00")
                else Decimal("0.00")
            )
            breakdown.append({
                "payment_method": method_str,
                "total_mxn": Decimal(str(total_amount)).quantize(Decimal("0.01")),
                "transaction_count": count,
                "percentage": pct,
            })
        return breakdown

    async def get_cash_flow_metrics(
        self,
        tenant_id: uuid.UUID,
        start_date: datetime,
        end_date: datetime,
    ) -> Dict[str, Decimal]:
        """
        Calcula las entradas reales de efectivo (ventas contado + abonos de crédito + entradas de caja)
        y las salidas reales (pagos a proveedores + gastos de caja).
        """
        # 1. Ventas en efectivo (CASH_MXN)
        cash_sales_stmt = (
            select(
                func.coalesce(
                    func.sum(SalePayment.amount_paid_mxn - SalePayment.change_returned_mxn),
                    Decimal("0.00"),
                )
            )
            .join(Sale, Sale.id == SalePayment.sale_id)
            .where(
                Sale.tenant_id == tenant_id,
                Sale.status.in_([SaleStatus.COMPLETED, SaleStatus.PAID]),
                SalePayment.payment_method == PaymentMethod.CASH_MXN,
                Sale.created_at >= start_date,
                Sale.created_at <= end_date,
            )
        )
        cash_sales = (await self.session.execute(cash_sales_stmt)).scalar() or Decimal("0.00")

        # 2. Cobranza de créditos a clientes (PAYMENT)
        credit_col_stmt = select(
            func.coalesce(func.sum(CustomerCreditLedger.amount_mxn), Decimal("0.00"))
        ).where(
            CustomerCreditLedger.tenant_id == tenant_id,
            CustomerCreditLedger.entry_type == LedgerEntryType.PAYMENT,
            CustomerCreditLedger.created_at >= start_date,
            CustomerCreditLedger.created_at <= end_date,
        )
        credit_collections = (await self.session.execute(credit_col_stmt)).scalar() or Decimal("0.00")

        # 3. Movimientos de ingreso directo a caja (CASH_IN)
        cash_income_stmt = select(
            func.coalesce(func.sum(CashMovement.amount_mxn), Decimal("0.00"))
        ).where(
            CashMovement.tenant_id == tenant_id,
            CashMovement.movement_type == CashMovementType.CASH_IN,
            CashMovement.created_at >= start_date,
            CashMovement.created_at <= end_date,
        )
        cash_income = (await self.session.execute(cash_income_stmt)).scalar() or Decimal("0.00")

        # 4. Pagos realizados a proveedores
        supplier_pay_stmt = select(
            func.coalesce(func.sum(SupplierPaymentLedger.amount_paid_mxn), Decimal("0.00"))
        ).where(
            SupplierPaymentLedger.tenant_id == tenant_id,
            SupplierPaymentLedger.created_at >= start_date,
            SupplierPaymentLedger.created_at <= end_date,
        )
        supplier_payments = (await self.session.execute(supplier_pay_stmt)).scalar() or Decimal("0.00")

        # 5. Gastos y retiros directos de caja (CASH_OUT)
        cash_expense_stmt = select(
            func.coalesce(func.sum(CashMovement.amount_mxn), Decimal("0.00"))
        ).where(
            CashMovement.tenant_id == tenant_id,
            CashMovement.movement_type == CashMovementType.CASH_OUT,
            CashMovement.created_at >= start_date,
            CashMovement.created_at <= end_date,
        )
        cash_expenses = (await self.session.execute(cash_expense_stmt)).scalar() or Decimal("0.00")

        total_inflow = (
            Decimal(str(cash_sales)) + Decimal(str(credit_collections)) + Decimal(str(cash_income))
        ).quantize(Decimal("0.01"))

        total_outflow = (
            Decimal(str(supplier_payments)) + Decimal(str(cash_expenses))
        ).quantize(Decimal("0.01"))

        net_cash_flow = (total_inflow - total_outflow).quantize(Decimal("0.01"))

        return {
            "cash_sales_inflow_mxn": Decimal(str(cash_sales)).quantize(Decimal("0.01")),
            "credit_collections_inflow_mxn": Decimal(str(credit_collections)).quantize(Decimal("0.01")),
            "cash_income_movements_mxn": Decimal(str(cash_income)).quantize(Decimal("0.01")),
            "total_inflow_mxn": total_inflow,
            "supplier_payments_outflow_mxn": Decimal(str(supplier_payments)).quantize(Decimal("0.01")),
            "cash_expense_movements_mxn": Decimal(str(cash_expenses)).quantize(Decimal("0.01")),
            "total_outflow_mxn": total_outflow,
            "net_cash_flow_mxn": net_cash_flow,
        }

    async def get_inventory_valuation(self, tenant_id: uuid.UUID) -> Dict[str, Any]:
        """Calcula la valuación total del inventario físico en Pesos Mexicanos."""
        stmt = (
            select(
                func.count(func.distinct(Product.id)),
                func.coalesce(func.sum(ProductStock.current_stock), Decimal("0.00")),
                func.coalesce(
                    func.sum(ProductStock.current_stock * Product.cost_mxn),
                    Decimal("0.00"),
                ),
                func.coalesce(
                    func.sum(ProductStock.current_stock * Product.price_mxn),
                    Decimal("0.00"),
                ),
            )
            .join(ProductStock, ProductStock.product_id == Product.id)
            .where(
                Product.tenant_id == tenant_id,
                Product.is_active == True,
            )
        )
        res = await self.session.execute(stmt)
        total_skus, total_units, cost_val, retail_val = res.one()

        cost_val_dec = Decimal(str(cost_val)).quantize(Decimal("0.01"))
        retail_val_dec = Decimal(str(retail_val)).quantize(Decimal("0.01"))
        potential_profit = (retail_val_dec - cost_val_dec).quantize(Decimal("0.01"))

        return {
            "total_active_skus": total_skus,
            "total_units_in_stock": Decimal(str(total_units)).quantize(Decimal("0.01")),
            "total_inventory_cost_mxn": cost_val_dec,
            "total_inventory_retail_mxn": retail_val_dec,
            "potential_gross_profit_mxn": potential_profit,
        }

    async def get_top_selling_products(
        self,
        tenant_id: uuid.UUID,
        start_date: datetime,
        end_date: datetime,
        limit: int = 10,
    ) -> List[Dict[str, Any]]:
        """Obtiene el ranking de los productos más vendidos en el periodo."""
        stmt = (
            select(
                Product.id,
                Product.name,
                Product.sku,
                func.coalesce(func.sum(SaleItem.quantity), Decimal("0.00")).label("units_sold"),
                func.coalesce(func.sum(SaleItem.total_mxn), Decimal("0.00")).label("revenue_mxn"),
                func.coalesce(
                    func.sum(SaleItem.total_mxn - (SaleItem.quantity * SaleItem.unit_cost_mxn)),
                    Decimal("0.00"),
                ).label("profit_mxn"),
            )
            .join(SaleItem, SaleItem.product_id == Product.id)
            .join(Sale, Sale.id == SaleItem.sale_id)
            .where(
                Sale.tenant_id == tenant_id,
                Sale.status.in_([SaleStatus.COMPLETED, SaleStatus.PAID]),
                Sale.created_at >= start_date,
                Sale.created_at <= end_date,
            )
            .group_by(Product.id, Product.name, Product.sku)
            .order_by(func.sum(SaleItem.quantity).desc())
            .limit(limit)
        )
        result = await self.session.execute(stmt)
        rows = result.all()

        return [
            {
                "product_id": r.id,
                "product_name": r.name,
                "sku": r.sku or "",
                "units_sold": Decimal(str(r.units_sold)).quantize(Decimal("0.01")),
                "revenue_mxn": Decimal(str(r.revenue_mxn)).quantize(Decimal("0.01")),
                "profit_mxn": Decimal(str(r.profit_mxn)).quantize(Decimal("0.01")),
            }
            for r in rows
        ]

    async def get_critical_stock_products(self, tenant_id: uuid.UUID) -> List[Dict[str, Any]]:
        """Obtiene los productos cuyas existencias están en o por debajo del umbral mínimo."""
        stmt = (
            select(
                Product.id,
                Product.name,
                Product.sku,
                func.coalesce(func.sum(ProductStock.current_stock), Decimal("0.00")).label("stock"),
                Product.min_stock_alert,
            )
            .join(ProductStock, ProductStock.product_id == Product.id)
            .where(
                Product.tenant_id == tenant_id,
                Product.is_active == True,
            )
            .group_by(Product.id, Product.name, Product.sku, Product.min_stock_alert)
            .having(func.sum(ProductStock.current_stock) <= Product.min_stock_alert)
            .order_by(func.sum(ProductStock.current_stock).asc())
        )
        result = await self.session.execute(stmt)
        rows = result.all()

        return [
            {
                "product_id": r.id,
                "product_name": r.name,
                "sku": r.sku or "",
                "current_stock": Decimal(str(r.stock)).quantize(Decimal("0.01")),
                "min_stock": Decimal(str(r.min_stock_alert)).quantize(Decimal("0.01")),
                "is_out_of_stock": Decimal(str(r.stock)) <= Decimal("0.00"),
            }
            for r in rows
        ]

    async def get_working_capital_metrics(self, tenant_id: uuid.UUID) -> Dict[str, Decimal]:
        """Calcula el capital de trabajo neto (Efectivo en caja + Cuentas por cobrar - Cuentas por pagar)."""
        # 1. Cuentas por cobrar (saldo de clientes fiados)
        rec_stmt = select(
            func.coalesce(func.sum(Customer.credit_balance_mxn), Decimal("0.00"))
        ).where(
            Customer.tenant_id == tenant_id,
            Customer.is_active == True,
            Customer.credit_balance_mxn > 0,
        )
        receivables = (await self.session.execute(rec_stmt)).scalar() or Decimal("0.00")

        # 2. Cuentas por pagar (cuentas a proveedores pendientes o parciales)
        pay_stmt = select(
            func.coalesce(func.sum(AccountPayable.total_mxn - AccountPayable.amount_paid_mxn), Decimal("0.00"))
        ).where(
            AccountPayable.tenant_id == tenant_id,
            AccountPayable.status.in_([
                AccountPayableStatus.PENDING,
                AccountPayableStatus.PARTIALLY_PAID,
                AccountPayableStatus.OVERDUE,
            ]),
        )
        payables = (await self.session.execute(pay_stmt)).scalar() or Decimal("0.00")

        # 3. Efectivo en caja (turnos abiertos o última caja registrada)
        cash_stmt = select(
            func.coalesce(func.sum(CashShift.opening_balance_mxn), Decimal("0.00"))
        ).where(
            CashShift.tenant_id == tenant_id,
            CashShift.status == ShiftStatus.OPEN,
        )
        cash_in_register = (await self.session.execute(cash_stmt)).scalar() or Decimal("0.00")

        rec_dec = Decimal(str(receivables)).quantize(Decimal("0.01"))
        pay_dec = Decimal(str(payables)).quantize(Decimal("0.01"))
        cash_dec = Decimal(str(cash_in_register)).quantize(Decimal("0.01"))
        net_working = (cash_dec + rec_dec - pay_dec).quantize(Decimal("0.01"))

        return {
            "cash_in_register_mxn": cash_dec,
            "accounts_receivable_mxn": rec_dec,
            "accounts_payable_mxn": pay_dec,
            "net_working_capital_mxn": net_working,
        }
