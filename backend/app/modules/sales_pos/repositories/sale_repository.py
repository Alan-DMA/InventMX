# Importación de marcas de fecha
from datetime import date, datetime
# Importación de tipado estático
from typing import List, Optional, Tuple
# Importación de identificadores UUID
import uuid
# Importación de SQLAlchemy
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

# Importación de modelos de dominio
from app.modules.sales_pos.domain.sale import Sale, SaleItem, SaleStatus


class SaleRepository:
    """
    Repositorio de persistencia y consultas para Ventas y Partidas POS (RF-08, RF-12).
    Asegura integridad referencial, transaccionalidad y aislamiento RLS por tenant.
    """

    def __init__(self, session: AsyncSession):
        # Sesión asíncrona de base de datos
        self.session = session

    async def generate_next_folio(self, tenant_id: uuid.UUID) -> str:
        """
        Genera un folio consecutivo diario único para el inquilino (ej. VTA-20260908-0001).
        """
        # Formato de prefijo de fecha actual YYYYMMDD
        today_str = datetime.now().strftime("%Y%m%d")
        prefix = f"VTA-{today_str}-"

        # Conteo de ventas emitidas hoy por el tenant para determinar el consecutivo
        query = (
            select(func.count(Sale.id))
            .where(Sale.tenant_id == tenant_id)
            .where(Sale.folio.like(f"{prefix}%"))
        )
        result = await self.session.execute(query)
        count = result.scalar_one() or 0
        consecutive = count + 1

        # Formato final con 4 dígitos de relleno
        return f"{prefix}{consecutive:04d}"

    async def create_sale(self, sale: Sale) -> Sale:
        """
        Persiste una nueva venta en la base de datos con sus partidas asociadas.
        """
        self.session.add(sale)
        await self.session.flush()
        return sale

    async def get_by_id(self, sale_id: uuid.UUID, tenant_id: uuid.UUID) -> Optional[Sale]:
        """
        Obtiene una venta por su ID con carga eager de partidas y relaciones bajo RLS.
        """
        query = (
            select(Sale)
            .options(
                selectinload(Sale.items).selectinload(SaleItem.product),
                selectinload(Sale.items).selectinload(SaleItem.combo),
                selectinload(Sale.cashier),
                selectinload(Sale.warehouse),
            )
            .where(Sale.id == sale_id)
            .where(Sale.tenant_id == tenant_id)
        )
        result = await self.session.execute(query)
        return result.scalar_one_or_none()

    async def list_sales(
        self,
        tenant_id: uuid.UUID,
        start_date: Optional[datetime] = None,
        end_date: Optional[datetime] = None,
        cashier_id: Optional[uuid.UUID] = None,
        warehouse_id: Optional[uuid.UUID] = None,
        status: Optional[SaleStatus] = None,
        skip: int = 0,
        limit: int = 50,
    ) -> Tuple[List[Sale], int]:
        """
        Lista el historial de ventas paginado con filtros opcionales (RF-11).
        """
        # Consulta base
        query = (
            select(Sale)
            .options(
                selectinload(Sale.items).selectinload(SaleItem.product),
                selectinload(Sale.items).selectinload(SaleItem.combo),
            )
            .where(Sale.tenant_id == tenant_id)
        )

        # Aplicación de filtros
        if start_date:
            query = query.where(Sale.created_at >= start_date)
        if end_date:
            query = query.where(Sale.created_at <= end_date)
        if cashier_id:
            query = query.where(Sale.cashier_id == cashier_id)
        if warehouse_id:
            query = query.where(Sale.warehouse_id == warehouse_id)
        if status:
            query = query.where(Sale.status == status)

        # Conteo total de registros coincidentes
        count_query = select(func.count()).select_from(query.subquery())
        total_count = (await self.session.execute(count_query)).scalar_one()

        # Ordenamiento descendente por fecha y paginación
        query = query.order_by(Sale.created_at.desc()).offset(skip).limit(limit)
        result = await self.session.execute(query)
        sales = result.scalars().all()

        return list(sales), total_count
