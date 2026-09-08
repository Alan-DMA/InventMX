# Importación de tipado estático
from typing import List, Optional
# Importación de constructores de SQLAlchemy
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

# Importación del modelo de dominio SeedProduct
from app.modules.inventory.domain.seed_product import SeedProduct


class SeedProductRepository:
    """
    Repositorio de datos para el Catálogo Semilla Maestro EAN-13 México (Tier 1).
    Proporciona consultas de alta velocidad (< 5ms) para el escáner de códigos de barras (RF-29).
    """

    def __init__(self, db: AsyncSession):
        # Inyección de la sesión asíncrona de base de datos
        self.db = db

    async def get_by_barcode(self, barcode: str) -> Optional[SeedProduct]:
        """
        Busca un producto oficial por su código de barras exacto (EAN-13 / GS1 México).
        Aprovecha el índice B-Tree en 'barcode' para resolver en microsegundos.
        """
        # Limpieza de espacios en blanco
        clean_barcode = barcode.strip()
        # Construcción de la sentencia SQL filtrada
        stmt = (
            select(SeedProduct)
            .where(SeedProduct.barcode == clean_barcode)
            .execution_options(populate_existing=True)
        )
        # Ejecución asíncrona en PostgreSQL
        result = await self.db.execute(stmt)
        # Retorno de la entidad o None si no existe
        return result.scalar_one_or_none()

    async def search_by_name(self, query: str, limit: int = 10) -> List[SeedProduct]:
        """
        Búsqueda difusa por coincidencia de nombre o marca en el catálogo semilla.
        """
        # Limpieza y preparación del patrón de búsqueda
        clean_q = f"%{query.strip()}%"
        # Construcción de la consulta con orden alfabético
        stmt = (
            select(SeedProduct)
            .where(
                (SeedProduct.name.ilike(clean_q)) | (SeedProduct.brand.ilike(clean_q))
            )
            .order_by(SeedProduct.name.asc())
            .limit(limit)
        )
        # Ejecución y retorno de resultados
        result = await self.db.execute(stmt)
        return list(result.scalars().all())
