# Importación de fecha y hora
from datetime import datetime, timezone
# Importación de precisión decimal
from decimal import Decimal
# Importación de tipado estático
from typing import Any, Dict, List, Optional, Tuple
# Importación de identificadores UUID
import uuid

# Importación de FastAPI HTTPException
from fastapi import HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

# Importación de modelos de base de datos
from app.modules.cash_treasury.domain.cash_session_denomination import CashSessionDenomination
from app.modules.cash_treasury.repositories.cash_treasury_repository import CashTreasuryRepository
from app.modules.cash_treasury.schemas.cash_schemas import (
    BanxicoDenominationsInput,
    CashBalanceResult,
    CashBalanceSummary,
    CashMovementCreateRequest,
    CashMovementResponse,
    CashMovementTypeParam,
    CashSessionCloseRequest,
    CashSessionCloseResponse,
    CashSessionOpenRequest,
    CashSessionReportResponse,
    CashSessionResponse,
)
from app.modules.sales_pos.domain.cash_movement import CashMovement, CashMovementType
from app.modules.sales_pos.domain.cash_shift import CashShift, ShiftStatus


class CashTreasuryService:
    """
    Servicio de Dominio para el Módulo de Caja y Tesorería (docs/api/cash.yaml).
    Garantiza el arqueo ciego Banxico, control de flujo en efectivo y generación del Corte Z.
    """

    def __init__(self, session: AsyncSession) -> None:
        self.session = session
        self.repo = CashTreasuryRepository(session)

    async def open_session(
        self,
        tenant_id: uuid.UUID,
        cashier_id: uuid.UUID,
        cashier_name: str,
        request: CashSessionOpenRequest,
    ) -> CashSessionResponse:
        """
        Abre un nuevo turno de caja (POST /cash/open-session).
        Regla: Solo puede existir 1 sesión activa (OPEN) por cajero.
        """
        # 1. Validar que no exista turno previo abierto
        existing = await self.repo.get_active_shift_by_cashier(cashier_id=cashier_id, tenant_id=tenant_id)
        if existing:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
                detail="Ya tienes una sesión de caja activa. Ciérrala antes de abrir una nueva.",
            )

        # 2. Si se suministró desglose por denominaciones, verificar suma
        opening_amount = request.opening_amount_mxn
        if request.opening_denominations:
            calc_total = request.opening_denominations.to_total_mxn()
            if calc_total > 0 and abs(calc_total - opening_amount) > Decimal("0.01"):
                opening_amount = calc_total

        # 3. Crear el turno de caja
        shift = CashShift(
            tenant_id=tenant_id,
            cashier_id=cashier_id,
            warehouse_id=request.warehouse_id,
            status=ShiftStatus.OPEN,
            opening_balance_mxn=opening_amount,
            expected_cash_mxn=opening_amount,
            notes=request.notes,
        )
        await self.repo.create_shift(shift)

        # 4. Guardar denominaciones si se suministraron
        if request.opening_denominations:
            denoms = CashSessionDenomination(
                shift_id=shift.id,
                tenant_id=tenant_id,
                is_opening=True,
                bills_1000=request.opening_denominations.bills_1000,
                bills_500=request.opening_denominations.bills_500,
                bills_200=request.opening_denominations.bills_200,
                bills_100=request.opening_denominations.bills_100,
                bills_50=request.opening_denominations.bills_50,
                bills_20=request.opening_denominations.bills_20,
                coins_20=request.opening_denominations.coins_20,
                coins_10=request.opening_denominations.coins_10,
                coins_5=request.opening_denominations.coins_5,
                coins_2=request.opening_denominations.coins_2,
                coins_1=request.opening_denominations.coins_1,
                coins_050=request.opening_denominations.coins_050,
                total_calculated_mxn=opening_amount,
            )
            await self.repo.save_denominations(denoms)

        await self.session.commit()

        return CashSessionResponse(
            id=shift.id,
            cashier_id=cashier_id,
            cashier_name=cashier_name,
            status=shift.status,
            opening_amount_mxn=shift.opening_balance_mxn,
            expected_cash_mxn=shift.expected_cash_mxn,
            opened_at=shift.opened_at,
            notes=shift.notes,
        )

    async def close_session(
        self,
        tenant_id: uuid.UUID,
        cashier_id: uuid.UUID,
        cashier_name: str,
        request: CashSessionCloseRequest,
    ) -> CashSessionCloseResponse:
        """
        Cierra la sesión activa realizando el arqueo físico Banxico (POST /cash/close-session).
        Compara el conteo físico con el saldo teórico y determina si hubo cuadre exacto, faltante o sobrante.
        """
        shift = await self.repo.get_active_shift_by_cashier(cashier_id=cashier_id, tenant_id=tenant_id)
        if not shift:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="No tienes una sesión de caja activa para cerrar.",
            )

        now = datetime.now(timezone.utc)

        # 1. Total físico de billetes y monedas contados
        physical_cash = request.physical_denominations.to_total_mxn()

        # 2. Ventas cobradas en efectivo durante el turno
        cash_sales, sales_count = await self.repo.get_shift_sales_cash_total(
            tenant_id=tenant_id,
            cashier_id=cashier_id,
            opened_at=shift.opened_at,
            closed_at=now,
        )

        # 3. Neto de movimientos menores (entradas - salidas)
        movements_net = await self.repo.get_shift_movements_net_mxn(shift.id)

        # 4. Saldo teórico esperado de efectivo en el cajón de dinero
        expected_cash = shift.opening_balance_mxn + cash_sales + movements_net

        # 5. Diferencia del arqueo (Físico - Teórico)
        diff = physical_cash - expected_cash

        # 6. Clasificación del balance
        if abs(diff) < Decimal("0.01"):
            balance_result = CashBalanceResult.EXACT
        elif diff < Decimal("0.00"):
            balance_result = CashBalanceResult.SHORT
        else:
            balance_result = CashBalanceResult.OVER

        # 7. Actualizar el registro del turno
        shift.status = ShiftStatus.CLOSED
        shift.counted_cash_mxn = physical_cash
        shift.expected_cash_mxn = expected_cash
        shift.difference_mxn = diff
        shift.closed_at = now
        shift.closed_by_user_id = cashier_id
        if request.notes:
            shift.notes = f"{shift.notes or ''} | Cierre: {request.notes}".strip(" |")

        await self.repo.update_shift(shift)

        # 8. Persistir el arqueo físico por denominación
        denoms = CashSessionDenomination(
            shift_id=shift.id,
            tenant_id=tenant_id,
            is_opening=False,
            bills_1000=request.physical_denominations.bills_1000,
            bills_500=request.physical_denominations.bills_500,
            bills_200=request.physical_denominations.bills_200,
            bills_100=request.physical_denominations.bills_100,
            bills_50=request.physical_denominations.bills_50,
            bills_20=request.physical_denominations.bills_20,
            coins_20=request.physical_denominations.coins_20,
            coins_10=request.physical_denominations.coins_10,
            coins_5=request.physical_denominations.coins_5,
            coins_2=request.physical_denominations.coins_2,
            coins_1=request.physical_denominations.coins_1,
            coins_050=request.physical_denominations.coins_050,
            total_calculated_mxn=physical_cash,
        )
        await self.repo.save_denominations(denoms)

        await self.session.commit()

        session_resp = CashSessionResponse(
            id=shift.id,
            cashier_id=cashier_id,
            cashier_name=cashier_name,
            status=shift.status,
            opening_amount_mxn=shift.opening_balance_mxn,
            expected_cash_mxn=expected_cash,
            physical_cash_mxn=physical_cash,
            difference_mxn=diff,
            balance_result=balance_result,
            opened_at=shift.opened_at,
            closed_at=now,
            notes=shift.notes,
        )

        balance_summary = CashBalanceSummary(
            expected_cash_mxn=expected_cash,
            physical_cash_mxn=physical_cash,
            difference_mxn=diff,
            balance_result=balance_result,
            sales_count=sales_count,
        )

        return CashSessionCloseResponse(
            session=session_resp,
            balance_summary=balance_summary,
        )

    async def get_active_session(
        self,
        tenant_id: uuid.UUID,
        cashier_id: uuid.UUID,
        cashier_name: str,
    ) -> Optional[CashSessionResponse]:
        """Recupera la sesión de caja activa del cajero en sesión."""
        shift = await self.repo.get_active_shift_by_cashier(cashier_id=cashier_id, tenant_id=tenant_id)
        if not shift:
            return None

        return CashSessionResponse(
            id=shift.id,
            cashier_id=cashier_id,
            cashier_name=cashier_name,
            status=shift.status,
            opening_amount_mxn=shift.opening_balance_mxn,
            expected_cash_mxn=shift.expected_cash_mxn or shift.opening_balance_mxn,
            opened_at=shift.opened_at,
            notes=shift.notes,
        )

    async def list_sessions(
        self,
        tenant_id: uuid.UUID,
        cashier_id: Optional[uuid.UUID] = None,
        status_filter: Optional[ShiftStatus] = None,
        date_from: Optional[datetime] = None,
        date_to: Optional[datetime] = None,
        page: int = 1,
        page_size: int = 20,
    ) -> Dict[str, Any]:
        """Lista las sesiones de caja con paginación."""
        offset = (page - 1) * page_size
        shifts, total = await self.repo.list_shifts(
            tenant_id=tenant_id,
            cashier_id=cashier_id,
            status_filter=status_filter,
            date_from=date_from,
            date_to=date_to,
            limit=page_size,
            offset=offset,
        )

        items = []
        for s in shifts:
            items.append(
                CashSessionResponse(
                    id=s.id,
                    cashier_id=s.cashier_id,
                    cashier_name="Cajero",
                    status=s.status,
                    opening_amount_mxn=s.opening_balance_mxn,
                    expected_cash_mxn=s.expected_cash_mxn or s.opening_balance_mxn,
                    physical_cash_mxn=s.counted_cash_mxn,
                    difference_mxn=s.difference_mxn,
                    opened_at=s.opened_at,
                    closed_at=s.closed_at,
                    notes=s.notes,
                )
            )

        return {"items": items, "total": total}

    async def get_session_detail(
        self,
        session_id: uuid.UUID,
        tenant_id: uuid.UUID,
    ) -> CashSessionResponse:
        """Consulta el detalle de una sesión de caja por ID."""
        shift = await self.repo.get_shift_by_id(session_id, tenant_id=tenant_id)
        if not shift:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Sesión no encontrada.")

        return CashSessionResponse(
            id=shift.id,
            cashier_id=shift.cashier_id,
            cashier_name="Cajero",
            status=shift.status,
            opening_amount_mxn=shift.opening_balance_mxn,
            expected_cash_mxn=shift.expected_cash_mxn or shift.opening_balance_mxn,
            physical_cash_mxn=shift.counted_cash_mxn,
            difference_mxn=shift.difference_mxn,
            opened_at=shift.opened_at,
            closed_at=shift.closed_at,
            notes=shift.notes,
        )

    async def register_movement(
        self,
        session_id: uuid.UUID,
        tenant_id: uuid.UUID,
        user_id: uuid.UUID,
        request: CashMovementCreateRequest,
    ) -> CashMovementResponse:
        """
        Registra un retiro o depósito manual de caja chica (POST /cash/sessions/{id}/movements).
        """
        shift = await self.repo.get_shift_by_id(session_id, tenant_id=tenant_id)
        if not shift:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Sesión no encontrada.")

        if shift.status != ShiftStatus.OPEN:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="No se pueden registrar movimientos en una sesión cerrada.",
            )

        m_type = CashMovementType.CASH_OUT if request.type == CashMovementTypeParam.WITHDRAWAL else CashMovementType.CASH_IN

        movement = CashMovement(
            tenant_id=tenant_id,
            shift_id=session_id,
            movement_type=m_type,
            amount_mxn=request.amount_mxn,
            reason=request.description,
            authorized_by_user_id=request.authorized_by_user_id or user_id,
            created_by_user_id=user_id,
        )
        await self.repo.create_cash_movement(movement)

        # Actualizar el saldo esperado del turno
        if m_type == CashMovementType.CASH_IN:
            shift.expected_cash_mxn = (shift.expected_cash_mxn or shift.opening_balance_mxn) + request.amount_mxn
        else:
            shift.expected_cash_mxn = (shift.expected_cash_mxn or shift.opening_balance_mxn) - request.amount_mxn

        await self.repo.update_shift(shift)
        await self.session.commit()

        return CashMovementResponse(
            id=movement.id,
            shift_id=session_id,
            type=request.type.value,
            amount_mxn=movement.amount_mxn,
            description=movement.reason,
            created_at=movement.created_at,
        )

    async def list_movements(
        self,
        session_id: uuid.UUID,
        tenant_id: uuid.UUID,
    ) -> List[CashMovementResponse]:
        """Lista los movimientos registrados durante la sesión."""
        shift = await self.repo.get_shift_by_id(session_id, tenant_id=tenant_id)
        if not shift:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Sesión no encontrada.")

        movements = await self.repo.list_movements(session_id)
        return [
            CashMovementResponse(
                id=m.id,
                shift_id=session_id,
                type="WITHDRAWAL" if m.movement_type == CashMovementType.CASH_OUT else "DEPOSIT",
                amount_mxn=m.amount_mxn,
                description=m.reason,
                created_at=m.created_at,
            )
            for m in movements
        ]

    async def generate_z_report(
        self,
        session_id: uuid.UUID,
        tenant_id: uuid.UUID,
    ) -> CashSessionReportResponse:
        """Genera el reporte de corte consolidado Z del turno."""
        shift = await self.repo.get_shift_by_id(session_id, tenant_id=tenant_id)
        if not shift:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Sesión no encontrada.")

        denoms = await self.repo.get_denominations(shift.id, is_opening=False)
        denoms_dict = None
        if denoms:
            denoms_dict = {
                "bills_1000": denoms.bills_1000,
                "bills_500": denoms.bills_500,
                "bills_200": denoms.bills_200,
                "bills_100": denoms.bills_100,
                "bills_50": denoms.bills_50,
                "bills_20": denoms.bills_20,
                "coins_20": denoms.coins_20,
                "coins_10": denoms.coins_10,
                "coins_5": denoms.coins_5,
                "coins_2": denoms.coins_2,
                "coins_1": denoms.coins_1,
                "coins_050": denoms.coins_050,
            }

        now = shift.closed_at or datetime.now(timezone.utc)
        duration_hours = max(0.0, (now - shift.opened_at).total_seconds() / 3600.0)

        diff = shift.difference_mxn or Decimal("0.00")
        bal_res = CashBalanceResult.EXACT if abs(diff) < Decimal("0.01") else (CashBalanceResult.SHORT if diff < 0 else CashBalanceResult.OVER)

        return CashSessionReportResponse(
            session_id=shift.id,
            cashier_name="Cajero",
            opened_at=shift.opened_at,
            closed_at=shift.closed_at,
            duration_hours=round(duration_hours, 2),
            sales_summary={
                "total_sales_count": 0,
                "cash_sales_mxn": shift.expected_cash_mxn or Decimal("0.00"),
                "digital_sales_mxn": Decimal("0.00"),
                "average_ticket_mxn": Decimal("0.00"),
            },
            cash_balance={
                "opening_amount_mxn": shift.opening_balance_mxn,
                "expected_closing_mxn": shift.expected_cash_mxn or shift.opening_balance_mxn,
                "physical_closing_mxn": shift.counted_cash_mxn or Decimal("0.00"),
                "difference_mxn": diff,
                "balance_result": bal_res,
            },
            denominations_breakdown=denoms_dict,
            movements_summary={
                "total_withdrawals_mxn": Decimal("0.00"),
                "total_deposits_mxn": Decimal("0.00"),
                "movements_count": 0,
            },
            pdf_url=None,
        )
