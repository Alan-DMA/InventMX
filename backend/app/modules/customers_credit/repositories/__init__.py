# Exportación de repositorios del módulo de clientes y crédito
from app.modules.customers_credit.repositories.credit_ledger_repository import (
    CreditLedgerRepository,
)
from app.modules.customers_credit.repositories.customer_repository import (
    CustomerRepository,
)

__all__ = [
    "CreditLedgerRepository",
    "CustomerRepository",
]
