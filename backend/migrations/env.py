import os
import sys
from logging.config import fileConfig

from sqlalchemy import create_engine, pool, text

# Asegurar que el directorio raíz del backend esté en sys.path
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from alembic import context
from app.core.config import settings
from app.core.database import Base

# Asegura la carga de todos los modelos en Base.metadata — cada módulo
# registra los suyos en su propio `domain/__init__.py` (arquitectura modular).
from app.modules.auth_tenancy import domain as _auth_tenancy_domain  # noqa: F401
from app.modules.cash_treasury import domain as _cash_treasury_domain  # noqa: F401
from app.modules.community_catalog import domain as _community_catalog_domain  # noqa: F401
from app.modules.customers_credit import domain as _customers_credit_domain  # noqa: F401
from app.modules.inventory import domain as _inventory_domain  # noqa: F401
from app.modules.purchasing_suppliers import domain as _purchasing_suppliers_domain  # noqa: F401
from app.modules.saas_billing import domain as _saas_billing_domain  # noqa: F401
from app.modules.sales_pos import domain as _sales_pos_domain  # noqa: F401
from app.modules.whatsapp_catalog import domain as _whatsapp_catalog_domain  # noqa: F401

# this is the Alembic Config object, which provides
# access to the values within the .ini file in use.
config = context.config

# Interpret the config file for Python logging.
# This line sets up loggers basically.
if config.config_file_name is not None:
    fileConfig(config.config_file_name)

target_metadata = Base.metadata


def run_migrations_offline() -> None:
    """Run migrations in 'offline' mode.

    This configures the context with just a URL
    and not an Engine, though an Engine is acceptable
    here as well.  By skipping the Engine creation
    we don't even need a DBAPI to be available.

    Calls to context.execute() here emit the given string to the
    script output.

    """
    url = settings.DATABASE_URL.replace("postgresql+asyncpg://", "postgresql+psycopg2://")
    context.configure(
        url=url,
        target_metadata=target_metadata,
        literal_binds=True,
        dialect_opts={"paramstyle": "named"},
        version_table_schema="public",
        include_schemas=True,
    )

    with context.begin_transaction():
        context.run_migrations()


def run_migrations_online() -> None:
    """Run migrations in 'online' mode.

    In this scenario we need to create an Engine
    and associate a connection with the context.

    """
    # Reemplazar el driver de asyncpg a psycopg2 para Alembic (que corre sincrónico)
    url = settings.DATABASE_URL.replace("postgresql+asyncpg://", "postgresql+psycopg2://")

    # Crear el motor de base de datos directamente usando la URL de settings
    connectable = create_engine(
        url,
        poolclass=pool.NullPool,
    )

    with connectable.connect() as connection:
        connection.execute(text("SET search_path TO public;"))
        context.configure(
            connection=connection,
            target_metadata=target_metadata,
            version_table_schema="public",
            include_schemas=True,
        )

        with context.begin_transaction():
            context.run_migrations()

        # El `SET search_path` de arriba dispara el autobegin de SQLAlchemy
        # 2.0 en esta conexión *antes* de que Alembic tome el control; al ver
        # una transacción ya abierta, Alembic asume que quien la abrió es
        # responsable de cerrarla y no comitea por su cuenta — sin esto, todo
        # el `run_migrations()` se revierte en silencio al cerrar la conexión.
        connection.commit()


if context.is_offline_mode():
    run_migrations_offline()
else:
    run_migrations_online()


