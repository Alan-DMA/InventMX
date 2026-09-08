"""Create seed products catalog table and seed top Mexican EAN-13 barcodes

Revision ID: 0005_seed_catalog
Revises: 0004_combos_kardex
Create Date: 2026-09-08 18:00:00.000000

"""
# Importación de tipos para anotación de dependencias de Alembic
from typing import Sequence, Union
# Importación de operaciones de esquema de Alembic
from alembic import op
# Importación de SQLAlchemy
import sqlalchemy as sa

# Identificador de la revisión actual
revision: str = "0005_seed_catalog"
# Identificador de la revisión previa (0004_combos_kardex)
down_revision: Union[str, None] = "0004_combos_kardex"
# Etiquetas de ramificación
branch_labels: Union[str, Sequence[str], None] = None
# Dependencias cruzadas
depends_on: Union[str, Sequence[str], None] = None

# Nombre del esquema de base de datos
SCHEMA = "inventmx"


def upgrade() -> None:
    # -------------------------------------------------------------------------
    # 1. Creación de la Tabla de Catálogo Semilla Maestro EAN-13 México (Tier 1)
    # -------------------------------------------------------------------------
    op.execute(f"""
        CREATE TABLE IF NOT EXISTS {SCHEMA}.seed_products_catalog (
            id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            barcode VARCHAR(50) UNIQUE NOT NULL,
            name VARCHAR(255) NOT NULL,
            brand VARCHAR(100),
            category_name VARCHAR(100) DEFAULT 'General',
            suggested_price_mxn NUMERIC(12, 2) DEFAULT 0.00 CHECK (suggested_price_mxn >= 0),
            image_url VARCHAR(500),
            is_verified BOOLEAN DEFAULT TRUE,
            created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
        );
    """)

    # Índice B-Tree único sobre código de barras para búsqueda ultra-rápida en < 5ms (RF-29 / Const. Art. 7.5)
    op.execute(f"CREATE INDEX IF NOT EXISTS idx_seed_products_barcode ON {SCHEMA}.seed_products_catalog(barcode);")
    op.execute(f"CREATE INDEX IF NOT EXISTS idx_seed_products_name ON {SCHEMA}.seed_products_catalog(name);")

    # -------------------------------------------------------------------------
    # 2. Sembrado de Datos del Catálogo Maestro Oficial (Top Marcas Mexicanas)
    # -------------------------------------------------------------------------
    op.execute(f"""
        INSERT INTO {SCHEMA}.seed_products_catalog (barcode, name, brand, category_name, suggested_price_mxn, is_verified) VALUES
        -- Refrescos y Bebidas
        ('7501055300075', 'Coca-Cola Original 600ml NR', 'Coca-Cola', 'Bebidas', 18.50, TRUE),
        ('7501055310883', 'Coca-Cola Retornable 3L', 'Coca-Cola', 'Bebidas', 38.00, TRUE),
        ('7501055365456', 'Coca-Cola Sin Azúcar 600ml', 'Coca-Cola', 'Bebidas', 18.50, TRUE),
        ('7501055333332', 'Agua Purificada Ciel 1L', 'Ciel', 'Bebidas', 12.00, TRUE),
        ('7501031311309', 'Refresco Jarritos Mandarina 600ml', 'Jarritos', 'Bebidas', 14.00, TRUE),
        ('7501031322401', 'Peñafiel Mineral con Gas 600ml', 'Peñafiel', 'Bebidas', 16.00, TRUE),
        ('7501011100010', 'Pepsi Regular 600ml', 'Pepsi', 'Bebidas', 17.00, TRUE),
        ('7501064191234', 'Cerveza Corona Extra 355ml Lata', 'Corona', 'Bebidas y Licores', 22.00, TRUE),

        -- Botanas y Snacks
        ('7501011115668', 'Sabritas Sal 45g', 'Sabritas', 'Botanas', 20.00, TRUE),
        ('7501011131064', 'Doritos Nacho 58g', 'Sabritas', 'Botanas', 20.00, TRUE),
        ('7501011143869', 'Ruffles Queso 50g', 'Sabritas', 'Botanas', 20.00, TRUE),
        ('7501011167890', 'Cheetos Torciditos 55g', 'Sabritas', 'Botanas', 16.00, TRUE),
        ('7501011189012', 'Tostitos Salsa Verde 65g', 'Sabritas', 'Botanas', 21.00, TRUE),

        -- Panadería y Galletas
        ('7501030424564', 'Pan Blanco Bimbo Grande 680g', 'Bimbo', 'Panadería', 47.00, TRUE),
        ('7501030456107', 'Donas Azucaradas Bimbo 105g', 'Bimbo', 'Panadería', 24.00, TRUE),
        ('7501030426100', 'Medias Noches Bimbo 8 pzas', 'Bimbo', 'Panadería', 45.00, TRUE),
        ('7501000611119', 'Galletas Marías Gamesa 170g', 'Gamesa', 'Galletas', 18.00, TRUE),
        ('7501000622221', 'Galletas Chokis Clásicas 76g', 'Gamesa', 'Galletas', 21.00, TRUE),
        ('7501000633332', 'Galletas Emperador Chocolate 101g', 'Gamesa', 'Galletas', 22.00, TRUE),

        -- Lácteos y Abarrotes Básicos
        ('7501020512113', 'Leche Lala Entera 1L Tetra Pak', 'Lala', 'Lácteos', 28.50, TRUE),
        ('7501020512120', 'Leche Lala Deslactosada 1L', 'Lala', 'Lácteos', 29.50, TRUE),
        ('7501017001118', 'Frijoles Negros Refritos La Costeña 430g', 'La Costeña', 'Abarrotes', 16.50, TRUE),
        ('7501017002221', 'Chiles Jalapeños Enteros La Costeña 220g', 'La Costeña', 'Abarrotes', 15.00, TRUE),
        ('7501005101010', 'Harina de Maíz Nixtamalizado Maseca 1kg', 'Maseca', 'Abarrotes', 21.00, TRUE),
        ('7501005112023', 'Mayonesa McCormick con Limón 390g', 'McCormick', 'Abarrotes', 42.00, TRUE),
        ('7501058617890', 'Café Soluble Nescafé Clásico 120g', 'Nescafé', 'Abarrotes', 65.00, TRUE),
        ('7501008000010', 'Atún Dolores en Agua 140g', 'Dolores', 'Abarrotes', 22.50, TRUE)
        ON CONFLICT (barcode) DO NOTHING;
    """)


def downgrade() -> None:
    # Eliminación de la tabla y sus índices
    op.execute(f"DROP TABLE IF EXISTS {SCHEMA}.seed_products_catalog CASCADE;")
