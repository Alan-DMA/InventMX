# Importación de marcas de fecha
from datetime import datetime
# Importación de tipado estático
from typing import List, Optional
# Importación de identificadores UUID
import uuid
# Importación de componentes de FastAPI
from fastapi import APIRouter, Depends, Query, status
# Importación de sesión asíncrona de base de datos
from sqlalchemy.ext.asyncio import AsyncSession

# Importación de dependencias de seguridad y contexto
from app.core.database.session import get_db
from app.core.security.deps import (
    get_current_user,
    require_permission,
    require_unlocked_tenant,
)
from app.modules.auth_tenancy.domain.user import User
from app.modules.customers_credit.schemas.customer import (
    CustomerCreateRequest,
    CustomerCreditPaymentRequest,
    CustomerCreditPaymentResponse,
    CustomerResponse,
    CustomerStatementResponse,
    CustomerUpdateRequest,
)
from app.modules.customers_credit.services.customer_credit_service import (
    CustomerCreditService,
)

# Router para gestión de clientes y créditos en mostrador
router = APIRouter(prefix="/customers", tags=["Customers & Store Credit"])


@router.post(
    "",
    response_model=CustomerResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Registrar Nuevo Cliente con Límite de Crédito",
    description="Crea un cliente en el catálogo con contacto, RFC y línea de crédito inicial en MXN (RF-06 / Const. Art. 1.2.6).",
)
async def create_customer(
    request: CustomerCreateRequest,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(require_permission("customers.create")),
    _unlocked: None = Depends(require_unlocked_tenant),
):
    """
    Registro formal de un nuevo cliente.
    """
    service = CustomerCreditService(db)
    return await service.create_customer(current_user.tenant_id, request)


@router.get(
    "",
    response_model=List[CustomerResponse],
    status_code=status.HTTP_200_OK,
    summary="Listar y Buscar Clientes en Mostrador",
    description="Consulta clientes con búsqueda por nombre, teléfono, RFC o filtro de saldos deudores pendientes (RF-06).",
)
async def list_customers(
    q: Optional[str] = Query(None, description="Búsqueda por nombre, teléfono, RFC o correo"),
    has_debt: bool = Query(False, description="Filtrar únicamente clientes con saldo deudor > 0"),
    skip: int = Query(0, ge=0, description="Offset de paginación"),
    limit: int = Query(50, ge=1, le=100, description="Límite por página"),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(require_permission("customers.view")),
):
    """
    Listado paginado de clientes.
    """
    service = CustomerCreditService(db)
    return await service.list_customers(
        tenant_id=current_user.tenant_id,
        query=q,
        has_debt_only=has_debt,
        limit=limit,
        offset=skip,
    )


@router.get(
    "/{customer_id}",
    response_model=CustomerResponse,
    status_code=status.HTTP_200_OK,
    summary="Obtener Detalle y Saldo de un Cliente",
    description="Devuelve la información de contacto y el balance crediticio disponible en Pesos Mexicanos.",
)
async def get_customer(
    customer_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(require_permission("customers.view")),
):
    """
    Consulta detallada de un cliente.
    """
    service = CustomerCreditService(db)
    return await service.get_customer(current_user.tenant_id, customer_id)


@router.put(
    "/{customer_id}",
    response_model=CustomerResponse,
    status_code=status.HTTP_200_OK,
    summary="Actualizar Información o Línea de Crédito",
    description="Modifica datos de contacto, estado o límite de crédito concedido al cliente.",
)
async def update_customer(
    customer_id: uuid.UUID,
    request: CustomerUpdateRequest,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(require_permission("customers.update")),
    _unlocked: None = Depends(require_unlocked_tenant),
):
    """
    Actualización de cliente.
    """
    service = CustomerCreditService(db)
    return await service.update_customer(current_user.tenant_id, customer_id, request)


@router.post(
    "/{customer_id}/payments",
    response_model=CustomerCreditPaymentResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Registrar Abono a Cuenta Corriente / Deuda",
    description="Registra un abono contable, disminuye el saldo deudor e inserta el asiento en el libro mayor (RF-15 / Const. Art. 7.2).",
)
async def record_payment(
    customer_id: uuid.UUID,
    request: CustomerCreditPaymentRequest,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(require_permission("customers.payment")),
    _unlocked: None = Depends(require_unlocked_tenant),
):
    """
    Registro contable de abono a crédito.
    """
    service = CustomerCreditService(db)
    return await service.record_credit_payment(
        tenant_id=current_user.tenant_id,
        customer_id=customer_id,
        user_id=current_user.id,
        request=request,
    )


@router.get(
    "/{customer_id}/statement",
    response_model=CustomerStatementResponse,
    status_code=status.HTTP_200_OK,
    summary="Consultar Estado de Cuenta y Movimientos de Crédito",
    description="Devuelve el historial cronológico de cargos, abonos y balance acumulado del cliente en un periodo (RF-15).",
)
async def get_statement(
    customer_id: uuid.UUID,
    start_date: Optional[datetime] = Query(None, description="Fecha inicial del periodo"),
    end_date: Optional[datetime] = Query(None, description="Fecha final del periodo"),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(require_permission("customers.view")),
):
    """
    Estado de cuenta del cliente.
    """
    service = CustomerCreditService(db)
    return await service.get_customer_statement(
        tenant_id=current_user.tenant_id,
        customer_id=customer_id,
        start_date=start_date,
        end_date=end_date,
    )
