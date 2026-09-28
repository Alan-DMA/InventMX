"""
Los datos de un comercio como un todo: exportarlos (LFPDPPP, P18) y borrarlos
(P4, tras la segunda aprobación). Vive fuera de `platform_admin` a propósito: el
panel dispara estas operaciones pero nunca recibe el contenido (P2) — la
exportación va directo al correo del dueño.

"Del comercio" se decide con el mapa **real** de la base (catálogo de
PostgreSQL), no con una lista a mano ni con los modelos: hay llaves foráneas que
sólo existen en las migraciones (p. ej. `sales.cashier_id → users`), y una tabla
nueva queda cubierta sola.
- tablas con `tenant_id` → sus renglones con ese `tenant_id`;
- tablas sin él (p. ej. `b2b_order_items`, `role_permissions`) → los renglones
  que apuntan por llave foránea a algo del comercio;
- lo demás (catálogo semilla, permisos globales, lo de la plataforma) no es del
  comercio y no se toca.
"""
import csv
import io
import json
import uuid
import zipfile
from dataclasses import dataclass, field
from datetime import date, datetime, timezone
from decimal import Decimal
from typing import Dict, List, Optional, Set, Tuple

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database.session import set_tenant_context

SCHEMA = "public"
# Registro de soporte (la solicitud de eliminación, la bitácora) y la versión
# del esquema: sobreviven al borrado y no son datos del comercio.
_SKIP_PREFIXES = ("platform_",)
_SKIP_TABLES = {"alembic_version"}
# Fuera de la exportación: secretos de acceso, no datos del negocio
_EXPORT_SKIP_TABLES = {"login_codes", "support_access_grants"}
_EXPORT_SKIP_COLUMNS = {"hashed_password", "access_key", "code_hash"}


@dataclass
class _ForeignKey:
    column: str
    parent: str
    parent_column: str


@dataclass
class _Schema:
    columns: Dict[str, List[str]] = field(default_factory=dict)
    foreign_keys: Dict[str, List[_ForeignKey]] = field(default_factory=dict)


async def _read_schema(db: AsyncSession) -> _Schema:
    schema = _Schema()
    rows = (await db.execute(text(
        """
        SELECT c.table_name, c.column_name
        FROM information_schema.columns c
        JOIN information_schema.tables t
          ON t.table_schema = c.table_schema AND t.table_name = c.table_name
        WHERE c.table_schema = :s AND t.table_type = 'BASE TABLE'
        ORDER BY c.table_name, c.ordinal_position
        """
    ), {"s": SCHEMA})).all()
    for table, column in rows:
        if table in _SKIP_TABLES or table.startswith(_SKIP_PREFIXES):
            continue
        schema.columns.setdefault(table, []).append(column)
    fks = (await db.execute(text(
        """
        SELECT cl.relname, a.attname, pl.relname, pa.attname
        FROM pg_constraint c
        JOIN pg_class cl ON cl.oid = c.conrelid
        JOIN pg_namespace n ON n.oid = cl.relnamespace
        JOIN pg_class pl ON pl.oid = c.confrelid
        JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = c.conkey[1]
        JOIN pg_attribute pa ON pa.attrelid = c.confrelid AND pa.attnum = c.confkey[1]
        WHERE c.contype = 'f' AND n.nspname = :s AND array_length(c.conkey, 1) = 1
        """
    ), {"s": SCHEMA})).all()
    for child, column, parent, parent_column in fks:
        if child in schema.columns and parent in schema.columns:
            schema.foreign_keys.setdefault(child, []).append(_ForeignKey(column, parent, parent_column))
    return schema


def _q(name: str) -> str:
    return '"' + name.replace('"', '""') + '"'


def _owned_condition(schema: _Schema, table: str, seen: Optional[Set[str]] = None) -> Optional[str]:
    """SQL de "este renglón es del comercio" (parámetro `:t`), o None si la tabla no es de nadie."""
    if table == "tenants":
        return f"{_q(table)}.id = :t"
    if "tenant_id" in schema.columns.get(table, []):
        return f"{_q(table)}.tenant_id = :t"
    seen = (seen or set()) | {table}
    conditions = []
    for fk in schema.foreign_keys.get(table, []):
        if fk.parent in seen:
            continue
        parent_condition = _owned_condition(schema, fk.parent, seen)
        if parent_condition is not None:
            conditions.append(
                f"{_q(table)}.{_q(fk.column)} IN "
                f"(SELECT {_q(fk.parent)}.{_q(fk.parent_column)} FROM {_q(fk.parent)} WHERE {parent_condition})"
            )
    return "(" + " OR ".join(conditions) + ")" if conditions else None


def _children_first(schema: _Schema) -> List[str]:
    """Orden de borrado: toda tabla antes que aquellas a las que apunta (se ignoran autorreferencias)."""
    parents = {t: {fk.parent for fk in schema.foreign_keys.get(t, []) if fk.parent != t} for t in schema.columns}
    referenced_by: Dict[str, Set[str]] = {t: set() for t in schema.columns}
    for child, its_parents in parents.items():
        for parent in its_parents:
            referenced_by[parent].add(child)
    order: List[str] = []
    pending = set(schema.columns)
    while pending:
        ready = sorted(t for t in pending if not (referenced_by[t] & pending))
        if not ready:  # ciclo: se rompe en orden alfabético; lo que falle, lo dirá la base
            ready = [sorted(pending)[0]]
        for table in ready:
            order.append(table)
            pending.discard(table)
    return order


def _cell(value) -> str:
    if value is None:
        return ""
    if isinstance(value, (datetime, date)):
        return value.isoformat()
    if isinstance(value, Decimal):
        return format(value, "f")
    if isinstance(value, (dict, list)):
        return json.dumps(value, ensure_ascii=False, default=str)
    return str(value)


async def build_tenant_export(db: AsyncSession, tenant_id: uuid.UUID) -> Tuple[str, bytes, int]:
    """
    ZIP con un CSV por tabla del comercio (UTF-8 con BOM: Excel lo abre bien).
    Lee **como el comercio** (su contexto de RLS, sin saltos): aunque la
    condición fallara, la base no le daría renglones de otro. Devuelve
    (nombre del archivo, bytes, tablas con datos).
    """
    schema = await _read_schema(db)
    await set_tenant_context(db, tenant_id)
    buffer = io.BytesIO()
    written: List[str] = []
    slug = "tienda"
    with zipfile.ZipFile(buffer, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for table in sorted(schema.columns):
            if table in _EXPORT_SKIP_TABLES:
                continue
            condition = _owned_condition(schema, table)
            if condition is None:
                continue
            columns = [c for c in schema.columns[table] if c not in _EXPORT_SKIP_COLUMNS]
            select_list = ", ".join(f"{_q(table)}.{_q(c)}" for c in columns)
            rows = (await db.execute(
                text(f"SELECT {select_list} FROM {_q(table)} WHERE {condition}"), {"t": tenant_id},
            )).all()
            if not rows:
                continue
            if table == "tenants":
                slug = rows[0]._mapping.get("slug") or slug
            out = io.StringIO()
            writer = csv.writer(out)
            writer.writerow(columns)
            for row in rows:
                writer.writerow([_cell(v) for v in row])
            archive.writestr(f"{table}.csv", "﻿" + out.getvalue())
            written.append(f"{table}.csv ({len(rows)} renglones)")
        generated = datetime.now(timezone.utc).strftime("%d/%m/%Y %H:%M UTC")
        archive.writestr(
            "LEEME.txt",
            "Copia de los datos de tu tienda en Nexus\n"
            f"Generada el {generated}.\n\n"
            "Cada archivo .csv es una tabla; la primera fila trae los nombres de las columnas.\n"
            "Las contraseñas no se incluyen (en Nexus sólo existen cifradas).\n\n"
            + "\n".join(written) + "\n",
        )
    await set_tenant_context(db, None)
    stamp = datetime.now(timezone.utc).strftime("%Y%m%d")
    return f"nexus-{slug}-{stamp}.zip", buffer.getvalue(), len(written)


async def purge_tenant(db: AsyncSession, tenant_id: uuid.UUID) -> Dict[str, int]:
    """
    Borra el comercio y todo lo suyo, de las hojas a la raíz: varias llaves son
    RESTRICT (ventas → usuarios, compras → proveedores) y un `DELETE` en cascada
    desde `tenants` fallaría según el orden en que PostgreSQL las recorra.

    Corre **como el comercio**: la mayoría de sus tablas sólo dejan ver sus
    renglones al propio comercio (sus políticas no aceptan el salto de RLS, y
    así debe ser). El salto local cubre las pocas compartidas (`users`, `roles`).
    Quien llama confirma (o revierte) todo junto. Devuelve cuántos renglones
    salieron por tabla.
    """
    schema = await _read_schema(db)
    removed: Dict[str, int] = {}
    await set_tenant_context(db, tenant_id)
    await db.execute(text("SELECT set_config('app.bypass_rls', 'on', true);"))
    for table in _children_first(schema):
        condition = _owned_condition(schema, table)
        if condition is None:
            continue
        result = await db.execute(text(f"DELETE FROM {_q(table)} WHERE {condition}"), {"t": tenant_id})
        if result.rowcount:
            removed[table] = result.rowcount
    await db.execute(text("SELECT set_config('app.bypass_rls', 'off', true);"))
    await set_tenant_context(db, None)
    return removed
