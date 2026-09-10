# Importación de tipado estático
from datetime import date
from typing import List, Optional
# Importación de identificadores UUID
import uuid
# Importación de FastAPI y componentes de dependencias
from fastapi import APIRouter, Depends, Query, status
from sqlalchemy.ext.asyncio import AsyncSession

# Importación de dependencias de sesión y autenticación
from app.core.database.session import get_db
from app.modules.auth_tenancy.domain.user import User
from app.core.security.deps import get_current_user
# Importación de dominios y esquemas
from app.modules.purchasing_suppliers.domain.account_payable import AccountPayableStatus
from app.modules.purchasing_suppliers.domain.purchase_order import PurchaseOrderStatus
from app.modules.purchasing_suppliers.domain.supplier import SupplierStatus
from app.modules.purchasing_suppliers.schemas.account_payable import (
    AccountPayableResponse,
    AccountsPayableSummaryResponse,
    SupplierPaymentLedgerResponse,
    SupplierPaymentRequest,
    SupplierPaymentResponse,
)
from app.modules.purchasing_suppliers.schemas.ocr_receipt import (
    ReceiptOcrParseRequest,
    ReceiptOcrParseResponse,
    VoiceDictationParseRequest,
    VoiceDictationParseResponse,
)
from app.modules.purchasing_suppliers.schemas.purchase_order import (
    PurchaseOrderCreateRequest,
    PurchaseOrderReceiveRequest,
    PurchaseOrderReceiveResponse,
    PurchaseOrderResponse,
)
from app.modules.purchasing_suppliers.schemas.supplier import (
    SupplierCreateRequest,
    SupplierResponse,
    SupplierUpdateRequest,
)
from app.modules.purchasing_suppliers.services.accounts_payable_service import (
    AccountsPayableService,
)
from app.modules.purchasing_suppliers.services.purchasing_service import (
    PurchasingService,
)
from app.modules.purchasing_suppliers.services.receipt_parser_service import (
    ReceiptParserService,
)
from app.modules.purchasing_suppliers.services.voice_parser_service import (
    VoiceParserService,
)

# Creación del enrutador modular
router = APIRouter(tags=["Compras & Proveedores"])


# -----------------------------------------------------------------------------
# Endpoints de Proveedores (Suppliers)
# -----------------------------------------------------------------------------

@router.post(
    "/suppliers",
    response_model=SupplierResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Crear nuevo proveedor comercial",
)
async def create_supplier(
    request: SupplierCreateRequest,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> SupplierResponse:
    """Registra un nuevo proveedor en el sistema (RF-15)."""
    service = PurchasingService(db)
    return await service.create_supplier(request, current_user)


@router.get(
    "/suppliers",
    response_model=List[SupplierResponse],
    status_code=status.HTTP_200_OK,
    summary="Listar proveedores del comercio",
)
async def list_suppliers(
    search: Optional[str] = Query(None, description="Búsqueda por nombre o RFC"),
    status: Optional[SupplierStatus] = Query(None, description="Filtrar por estado activo/inactivo"),
    limit: int = Query(50, ge=1, le=200),
    offset: int = Query(0, ge=0),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> List[SupplierResponse]:
    """Retorna la lista de proveedores asociados al comercio."""
    service = PurchasingService(db)
    items, _ = await service.list_suppliers(
        current_user=current_user,
        search=search,
        status_filter=status,
        limit=limit,
        offset=offset,
    )
    return items


@router.get(
    "/suppliers/{supplier_id}",
    response_model=SupplierResponse,
    status_code=status.HTTP_200_OK,
    summary="Obtener detalle de proveedor específico",
)
async def get_supplier(
    supplier_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> SupplierResponse:
    """Retorna la información completa de un proveedor."""
    service = PurchasingService(db)
    return await service.get_supplier(supplier_id, current_user)


@router.put(
    "/suppliers/{supplier_id}",
    response_model=SupplierResponse,
    status_code=status.HTTP_200_OK,
    summary="Actualizar información del proveedor",
)
async def update_supplier(
    supplier_id: uuid.UUID,
    request: SupplierUpdateRequest,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> SupplierResponse:
    """Actualiza datos de contacto o condiciones de crédito del proveedor."""
    service = PurchasingService(db)
    return await service.update_supplier(supplier_id, request, current_user)


@router.delete(
    "/suppliers/{supplier_id}",
    response_model=SupplierResponse,
    status_code=status.HTTP_200_OK,
    summary="Desactivar proveedor",
)
async def deactivate_supplier(
    supplier_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> SupplierResponse:
    """Marca como inactivo al proveedor."""
    service = PurchasingService(db)
    return await service.deactivate_supplier(supplier_id, current_user)


# -----------------------------------------------------------------------------
# Endpoints de Órdenes de Compra (Purchase Orders)
# -----------------------------------------------------------------------------

@router.post(
    "/purchase-orders",
    response_model=PurchaseOrderResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Crear nueva orden de compra",
)
async def create_purchase_order(
    request: PurchaseOrderCreateRequest,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> PurchaseOrderResponse:
    """Emite una nueva orden de compra a proveedor en Pesos Mexicanos (RF-15)."""
    service = PurchasingService(db)
    return await service.create_purchase_order(request, current_user)


@router.get(
    "/purchase-orders",
    response_model=List[PurchaseOrderResponse],
    status_code=status.HTTP_200_OK,
    summary="Listar órdenes de compra",
)
async def list_purchase_orders(
    supplier_id: Optional[uuid.UUID] = Query(None, description="Filtrar por proveedor"),
    status: Optional[PurchaseOrderStatus] = Query(None, description="Filtrar por estado"),
    date_from: Optional[date] = Query(None, description="Fecha desde"),
    date_to: Optional[date] = Query(None, description="Fecha hasta"),
    limit: int = Query(50, ge=1, le=200),
    offset: int = Query(0, ge=0),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> List[PurchaseOrderResponse]:
    """Retorna las órdenes de compra con filtros opcionales."""
    service = PurchasingService(db)
    items, _ = await service.list_purchase_orders(
        current_user=current_user,
        supplier_id=supplier_id,
        status_filter=status,
        date_from=date_from,
        date_to=date_to,
        limit=limit,
        offset=offset,
    )
    return items


@router.get(
    "/purchase-orders/{order_id}",
    response_model=PurchaseOrderResponse,
    status_code=status.HTTP_200_OK,
    summary="Obtener detalle de orden de compra",
)
async def get_purchase_order(
    order_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> PurchaseOrderResponse:
    """Retorna los datos de la orden y sus renglones."""
    service = PurchasingService(db)
    return await service.get_purchase_order(order_id, current_user)


@router.post(
    "/purchase-orders/{order_id}/receive",
    response_model=PurchaseOrderReceiveResponse,
    status_code=status.HTTP_200_OK,
    summary="Recepcionar mercancía física en inventario y asentar Kardex",
)
async def receive_purchase_order(
    order_id: uuid.UUID,
    request: PurchaseOrderReceiveRequest,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> PurchaseOrderReceiveResponse:
    """
    Registra la entrada física de mercancía al almacén, actualiza el Kardex (PURCHASE_ENTRY)
    y genera la cuenta por pagar a crédito (RF-15, RF-17).
    """
    service = PurchasingService(db)
    return await service.receive_purchase_order(order_id, request, current_user)


# -----------------------------------------------------------------------------
# Endpoints de Cuentas por Pagar (Accounts Payable)
# -----------------------------------------------------------------------------

@router.get(
    "/accounts-payable",
    response_model=List[AccountPayableResponse],
    status_code=status.HTTP_200_OK,
    summary="Listar cuentas por pagar a proveedores",
)
async def list_accounts_payable(
    supplier_id: Optional[uuid.UUID] = Query(None, description="Filtrar por proveedor"),
    status: Optional[AccountPayableStatus] = Query(None, description="Filtrar por estado de pago"),
    overdue_only: bool = Query(False, description="Mostrar únicamente facturas vencidas"),
    limit: int = Query(50, ge=1, le=200),
    offset: int = Query(0, ge=0),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> List[AccountPayableResponse]:
    """Retorna el listado de cuentas por pagar (RF-16)."""
    service = AccountsPayableService(db)
    items, _ = await service.list_accounts_payable(
        current_user=current_user,
        supplier_id=supplier_id,
        status_filter=status,
        overdue_only=overdue_only,
        limit=limit,
        offset=offset,
    )
    return items


@router.get(
    "/accounts-payable/summary",
    response_model=AccountsPayableSummaryResponse,
    status_code=status.HTTP_200_OK,
    summary="Obtener resumen financiero de cuentas por pagar",
)
async def get_accounts_payable_summary(
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> AccountsPayableSummaryResponse:
    """Retorna totales pendientes, pagados y montos vencidos en $ MXN."""
    service = AccountsPayableService(db)
    return await service.get_summary(current_user)


@router.get(
    "/accounts-payable/{account_id}",
    response_model=AccountPayableResponse,
    status_code=status.HTTP_200_OK,
    summary="Obtener detalle de cuenta por pagar",
)
async def get_account_payable(
    account_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> AccountPayableResponse:
    """Consulta una cuenta por pagar específica."""
    service = AccountsPayableService(db)
    return await service.get_account_payable(account_id, current_user)


@router.post(
    "/accounts-payable/{account_id}/pay",
    response_model=SupplierPaymentResponse,
    status_code=status.HTTP_200_OK,
    summary="Registrar pago o abono a cuenta por pagar de proveedor",
)
async def pay_account_payable(
    account_id: uuid.UUID,
    request: SupplierPaymentRequest,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> SupplierPaymentResponse:
    """Registra un egreso de dinero para abonar o liquidar deuda con un proveedor (RF-16)."""
    service = AccountsPayableService(db)
    return await service.record_supplier_payment(account_id, request, current_user)


@router.get(
    "/accounts-payable/{account_id}/payments",
    response_model=List[SupplierPaymentLedgerResponse],
    status_code=status.HTTP_200_OK,
    summary="Listar historial de pagos aplicados a la cuenta",
)
async def list_account_payments(
    account_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> List[SupplierPaymentLedgerResponse]:
    """Retorna todos los abonos registrados para la cuenta por pagar."""
    service = AccountsPayableService(db)
    return await service.list_account_payments(account_id, current_user)


# -----------------------------------------------------------------------------
# Endpoints de OCR On-Device y Dictado de Voz (RF-28, SR-09)
# -----------------------------------------------------------------------------

@router.post(
    "/purchases/parse-receipt",
    response_model=ReceiptOcrParseResponse,
    status_code=status.HTTP_200_OK,
    summary="Parsear texto plano OCR de factura y emparejar con catálogo",
)
async def parse_receipt(
    request: ReceiptOcrParseRequest,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> ReceiptOcrParseResponse:
    """
    Interpreta el texto extraído por Google ML Kit en el dispositivo cliente, detecta productos,
    cantidades y costos unitarios, y busca coincidencias en el inventario del comercio (RF-28).
    """
    service = ReceiptParserService(db)
    return await service.parse_receipt_text(request, current_user)


@router.post(
    "/purchases/parse-voice-dictation",
    response_model=VoiceDictationParseResponse,
    status_code=status.HTTP_200_OK,
    summary="Interpretar dictado de voz nativo para autocompletar 3 campos vitales",
)
async def parse_voice_dictation(
    request: VoiceDictationParseRequest,
    current_user: User = Depends(get_current_user),
) -> VoiceDictationParseResponse:
    """
    Procesa el texto dictado por voz en español y extrae los 3 Campos Vitales: Nombre, Precio y Stock (SR-09).
    """
    service = VoiceParserService()
    return service.parse_voice_text(request)

