"""
Alta y mantenimiento de operadores del panel de plataforma (Fase 1, Sep 2026).

Es la **única** forma de crear un operador: no hay registro por API. Se corre en
el servidor, desde `backend/`:

    .venv/Scripts/python.exe -m scripts.platform_operator create --email alan@nexus.mx --name "Alan"
    .venv/Scripts/python.exe -m scripts.platform_operator reset-totp --email alan@nexus.mx
    .venv/Scripts/python.exe -m scripts.platform_operator deactivate --email alan@nexus.mx

La contraseña se pide por teclado (dos veces, mínimo 12 caracteres); nunca va en
la línea de comandos. `reset-totp` es para cuando se pierde el teléfono y no
quedan códigos de recuperación: el siguiente acceso vuelve a mostrar el QR.
Todo queda en la bitácora de la plataforma.
"""
import argparse
import asyncio
import getpass
import sys

from sqlalchemy import delete

# Registra todos los modelos (vía los routers de la app): SQLAlchemy configura
# el registro completo en la primera consulta y, sin esto, falla al resolver
# relaciones de modelos que el script no importa (hallado en QA, Sep 28).
import app.main  # noqa: F401
from app.core.database.session import AsyncSessionLocal, engine
from app.core.security.password import get_password_hash
from app.modules.platform_admin.domain.audit_log import AuditAction
from app.modules.platform_admin.domain.operator import PlatformOperator, PlatformRecoveryCode
from app.modules.platform_admin.repositories.audit_repository import AuditRepository, RequestMeta
from app.modules.platform_admin.repositories.operator_repository import OperatorRepository

MIN_PASSWORD_LENGTH = 12
CLI_META = RequestMeta(ip_address="cli", user_agent="scripts.platform_operator")


def _ask_password() -> str:
    first = getpass.getpass("Contraseña (mínimo 12 caracteres): ")
    if len(first) < MIN_PASSWORD_LENGTH:
        sys.exit("La contraseña es demasiado corta.")
    if getpass.getpass("Repite la contraseña: ") != first:
        sys.exit("Las contraseñas no coinciden.")
    return first


async def create(email: str, name: str) -> None:
    async with AsyncSessionLocal() as db:
        repo = OperatorRepository(db)
        if await repo.get_by_email(email):
            sys.exit(f"Ya existe un operador con el correo {email}.")
        operator = PlatformOperator(
            email=email.strip().lower(),
            full_name=name.strip(),
            hashed_password=get_password_hash(_ask_password()),
        )
        db.add(operator)
        await db.flush()
        await AuditRepository(db).append(
            AuditAction.OPERATOR_CREATED, target_type="operator", target_id=str(operator.id),
            details={"email": operator.email}, meta=CLI_META,
        )
        await db.commit()
        print(f"Operador creado: {operator.email}. En su primer acceso vinculará Google Authenticator.")


async def reset_totp(email: str) -> None:
    async with AsyncSessionLocal() as db:
        operator = await OperatorRepository(db).get_by_email(email)
        if operator is None:
            sys.exit(f"No existe el operador {email}.")
        operator.totp_secret_encrypted = None
        operator.totp_enabled_at = None
        operator.totp_last_step = None
        await db.execute(delete(PlatformRecoveryCode).where(PlatformRecoveryCode.operator_id == operator.id))
        await AuditRepository(db).append(
            AuditAction.TOTP_RESET, target_type="operator", target_id=str(operator.id), meta=CLI_META,
        )
        await db.commit()
        print(f"TOTP de {email} reiniciado: el siguiente acceso mostrará un QR nuevo.")


async def deactivate(email: str) -> None:
    async with AsyncSessionLocal() as db:
        operator = await OperatorRepository(db).get_by_email(email)
        if operator is None:
            sys.exit(f"No existe el operador {email}.")
        operator.is_active = False
        await AuditRepository(db).append(
            AuditAction.OPERATOR_DEACTIVATED, target_type="operator", target_id=str(operator.id), meta=CLI_META,
        )
        await db.commit()
        print(f"Operador {email} desactivado.")


def main() -> None:
    parser = argparse.ArgumentParser(description="Operadores del panel de plataforma")
    sub = parser.add_subparsers(dest="command", required=True)
    c = sub.add_parser("create", help="Crear un operador")
    c.add_argument("--email", required=True)
    c.add_argument("--name", required=True)
    r = sub.add_parser("reset-totp", help="Volver a vincular Google Authenticator")
    r.add_argument("--email", required=True)
    d = sub.add_parser("deactivate", help="Quitar el acceso a un operador")
    d.add_argument("--email", required=True)
    args = parser.parse_args()
    # En desarrollo el motor imprime cada SQL; en una herramienta de consola estorba
    engine.echo = False

    if args.command == "create":
        asyncio.run(_run(create(args.email, args.name)))
    elif args.command == "reset-totp":
        asyncio.run(_run(reset_totp(args.email)))
    else:
        asyncio.run(_run(deactivate(args.email)))


async def _run(command) -> None:
    """Ejecuta y libera las conexiones del pool antes de cerrar el loop."""
    try:
        await command
    finally:
        await engine.dispose()


if __name__ == "__main__":
    main()
