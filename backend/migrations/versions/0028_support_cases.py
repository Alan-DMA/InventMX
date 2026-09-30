"""Soporte dentro de la app, estilo Steam: temas de ayuda servidos por el servidor y casos (Sep 2026)

Decisiones P23–P25 de Eduardo:
- `help_topics`: ayuda por tema + la definición del formulario de ese tema. Se
  sirve desde el servidor para cambiar textos y campos sin publicar la app; se
  edita desde el panel (bitácora `HELP_TOPIC_UPDATED`). Sin RLS: es contenido de
  la plataforma, igual para todos.
- `support_cases` / `support_case_messages`: el caso que llega a soporte y su
  hilo. RLS del comercio (con salto para el panel). Los casos sin sesión
  (P24) no tienen comercio: sólo los ve el panel.

Revision ID: 0028_support_cases
Revises: 0027_support_center
Create Date: 2026-09-29 10:00:00.000000

"""
import json
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects.postgresql import JSONB

revision: str = "0028_support_cases"
down_revision: Union[str, None] = "0027_support_center"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

SCHEMA = "public"

_POLICY = """
    CREATE POLICY tenant_isolation_policy ON {schema}.{table}
    FOR ALL
    USING (
        current_setting('app.bypass_rls', true) = 'on'
        OR tenant_id = NULLIF(current_setting('app.current_tenant', true), '')::uuid
    )
    WITH CHECK (
        current_setting('app.bypass_rls', true) = 'on'
        OR tenant_id = NULLIF(current_setting('app.current_tenant', true), '')::uuid
    );
"""

# Temas iniciales (P23). Cuerpo: párrafos separados por línea en blanco; "• " al
# inicio = viñeta. Acciones: claves que la app traduce a pantallas.
TOPICS = [
    {
        "key": "account_suspended",
        "title": "Mi cuenta está suspendida",
        "summary": "Por qué se suspende una cuenta y cómo se reactiva.",
        "body": (
            "Una cuenta se suspende por una de dos razones, y la pantalla de suspensión te dice cuál:\n\n"
            "• Tu suscripción venció y terminaron los días de gracia. Al renovar, la cuenta se reactiva al momento.\n"
            "• Soporte Nexus la suspendió por un uso indebido. En ese caso renovar no la levanta: "
            "escríbenos y revisamos tu caso.\n\n"
            "Mientras está suspendida no se borra nada: tus productos, ventas y reportes siguen guardados."
        ),
        "actions": [{"label": "Ver Mi suscripción", "target": "subscription"}],
        "form_fields": [
            {"key": "since", "label": "¿Desde cuándo está suspendida?", "type": "text", "required": False},
        ],
        "audience": "ALL",
        "sort_order": 10,
    },
    {
        "key": "subscription",
        "title": "Mi suscripción y pagos",
        "summary": "Vigencia, días de gracia, cobros y planes.",
        "body": (
            "Tu suscripción vale un mes desde el día en que se activa. Al vencer tienes 10 días de gracia con "
            "la app completa; después se suspende hasta renovar.\n\n"
            "En Mi suscripción ves hasta cuándo está pagada, tu plan y lo que soporte haya hecho en tu cuenta."
        ),
        "actions": [{"label": "Ver Mi suscripción", "target": "subscription"}],
        "form_fields": [
            {
                "key": "kind", "label": "¿Sobre qué es tu duda?", "type": "select", "required": True,
                "options": ["Vigencia o fechas", "Un cobro", "Cambiar de plan", "Otra cosa"],
            },
        ],
        "audience": "OWNER",
        "sort_order": 20,
    },
    {
        "key": "something_broken",
        "title": "Algo no funciona",
        "summary": "Un error al vender, en el inventario, la caja u otra parte.",
        "body": (
            "Antes de escribirnos, prueba esto:\n\n"
            "• Revisa que tengas internet.\n"
            "• Cierra la app por completo y vuelve a abrirla.\n"
            "• Actualiza la app si la tienda de Google te lo ofrece.\n\n"
            "Si sigue pasando, cuéntanos qué hacías y qué viste: con eso lo encontramos más rápido."
        ),
        "actions": [],
        "form_fields": [
            {
                "key": "module", "label": "¿En qué parte de la app?", "type": "select", "required": True,
                "options": ["Ventas", "Inventario", "Caja", "Compras", "Catálogo web", "Otra"],
            },
            {"key": "when", "label": "¿Cuándo pasó?", "type": "text", "required": False},
            {"key": "steps", "label": "¿Qué estabas haciendo?", "type": "textarea", "required": False},
        ],
        "audience": "ALL",
        "sort_order": 30,
    },
    {
        "key": "my_data",
        "title": "Mis datos",
        "summary": "Pedir una copia de tus datos o eliminar tu tienda.",
        "body": (
            "Tus datos son tuyos. Puedes pedirnos:\n\n"
            "• Una copia: la generamos y te llega al correo del dueño. Nadie de soporte ve el contenido.\n"
            "• Eliminar tu tienda: borra la tienda y todos sus datos, sin forma de recuperarlos. Por seguridad, "
            "la aprueban dos personas de soporte.\n\n"
            "Si vas a eliminarla, te recomendamos pedir antes la copia."
        ),
        "actions": [],
        "form_fields": [
            {
                "key": "request", "label": "¿Qué necesitas?", "type": "select", "required": True,
                "options": ["Una copia de mis datos", "Eliminar mi tienda"],
            },
        ],
        "audience": "OWNER",
        "sort_order": 40,
    },
    {
        "key": "staff_access",
        "title": "Otro usuario de mi tienda no puede entrar",
        "summary": "Un empleado olvidó su contraseña o no puede iniciar sesión.",
        "body": (
            "Quien administra la tienda puede ponerle una contraseña nueva a un empleado desde Usuarios y "
            "permisos, sin esperar a soporte.\n\n"
            "Si quien no puede entrar es el dueño, en la pantalla de acceso toca \"¿Olvidaste tu contraseña?\"."
        ),
        "actions": [{"label": "Ir a Usuarios y permisos", "target": "manage_members"}],
        "form_fields": [
            {"key": "who", "label": "¿Quién no puede entrar? (nombre o correo)", "type": "text", "required": True},
        ],
        "audience": "ALL",
        "sort_order": 50,
    },
    {
        "key": "other",
        "title": "Otra pregunta",
        "summary": "Cualquier otra cosa en la que te podamos ayudar.",
        "body": "Cuéntanos qué necesitas y te respondemos aquí mismo, en la app.",
        "actions": [],
        "form_fields": [],
        "audience": "ALL",
        "sort_order": 90,
    },
    {
        "key": "cannot_login",
        "title": "No puedo entrar a mi cuenta",
        "summary": "No te llega el código o perdiste acceso a tu correo.",
        "body": (
            "Si olvidaste tu contraseña, en la pantalla de acceso toca \"¿Olvidaste tu contraseña?\" y te "
            "enviamos un código a tu correo.\n\n"
            "• El código vence en 30 minutos: usa el más reciente.\n"
            "• Revisa también la carpeta de spam o promociones.\n\n"
            "Si aun así no puedes entrar, escríbenos: revisamos que la cuenta sea tuya y te ayudamos a recuperarla."
        ),
        "actions": [{"label": "Pedir un código", "target": "forgot_password"}],
        "form_fields": [
            {
                "key": "problem", "label": "¿Qué está pasando?", "type": "select", "required": True,
                "options": ["No me llega el código", "Perdí acceso a mi correo", "Otra cosa"],
            },
        ],
        "audience": "ANONYMOUS",
        "sort_order": 100,
    },
]


def upgrade() -> None:
    op.execute(f"""
        CREATE TABLE {SCHEMA}.help_topics (
            key VARCHAR(40) PRIMARY KEY,
            title VARCHAR(120) NOT NULL,
            summary VARCHAR(200) NOT NULL DEFAULT '',
            body TEXT NOT NULL DEFAULT '',
            actions JSONB NOT NULL DEFAULT '[]'::jsonb,
            form_fields JSONB NOT NULL DEFAULT '[]'::jsonb,
            audience VARCHAR(10) NOT NULL CHECK (audience IN ('ALL', 'OWNER', 'ANONYMOUS')),
            sort_order INTEGER NOT NULL DEFAULT 100,
            is_active BOOLEAN NOT NULL DEFAULT TRUE,
            updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
            updated_by UUID NULL REFERENCES {SCHEMA}.platform_operators(id) ON DELETE RESTRICT
        );
    """)
    topics = sa.table(
        "help_topics",
        sa.column("key", sa.String), sa.column("title", sa.String), sa.column("summary", sa.String),
        sa.column("body", sa.Text), sa.column("actions", JSONB), sa.column("form_fields", JSONB),
        sa.column("audience", sa.String), sa.column("sort_order", sa.Integer),
        schema=SCHEMA,
    )
    op.bulk_insert(topics, [json.loads(json.dumps(t)) for t in TOPICS])

    op.execute(f"""
        CREATE TABLE {SCHEMA}.support_cases (
            id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            number BIGINT GENERATED ALWAYS AS IDENTITY (START WITH 1001) UNIQUE,
            tenant_id UUID NULL REFERENCES {SCHEMA}.tenants(id) ON DELETE CASCADE,
            author_user_id UUID NULL REFERENCES {SCHEMA}.users(id) ON DELETE SET NULL,
            channel VARCHAR(10) NOT NULL CHECK (channel IN ('APP', 'PUBLIC')),
            topic_key VARCHAR(40) NOT NULL,
            topic_title VARCHAR(120) NOT NULL,
            details JSONB NOT NULL DEFAULT '{{}}'::jsonb,
            status VARCHAR(20) NOT NULL CHECK (status IN ('WAITING_SUPPORT', 'ANSWERED', 'RESOLVED')),
            contact_email VARCHAR(255) NOT NULL,
            contact_name VARCHAR(150) NULL,
            claimed_store_name VARCHAR(150) NULL,
            suggested_tenant_id UUID NULL,
            requester_ip VARCHAR(64) NULL,
            requester_unread BOOLEAN NOT NULL DEFAULT FALSE,
            created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
            updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
            last_message_at TIMESTAMPTZ NOT NULL DEFAULT now()
        );
    """)
    op.execute(f"CREATE INDEX ix_support_cases_tenant ON {SCHEMA}.support_cases (tenant_id, last_message_at DESC);")
    op.execute(f"CREATE INDEX ix_support_cases_status ON {SCHEMA}.support_cases (status, last_message_at);")

    op.execute(f"""
        CREATE TABLE {SCHEMA}.support_case_messages (
            id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            case_id UUID NOT NULL REFERENCES {SCHEMA}.support_cases(id) ON DELETE CASCADE,
            tenant_id UUID NULL REFERENCES {SCHEMA}.tenants(id) ON DELETE CASCADE,
            author_kind VARCHAR(10) NOT NULL CHECK (author_kind IN ('REQUESTER', 'SUPPORT')),
            author_user_id UUID NULL REFERENCES {SCHEMA}.users(id) ON DELETE SET NULL,
            operator_id UUID NULL REFERENCES {SCHEMA}.platform_operators(id) ON DELETE RESTRICT,
            body TEXT NOT NULL,
            created_at TIMESTAMPTZ NOT NULL DEFAULT now()
        );
    """)
    op.execute(f"CREATE INDEX ix_support_case_messages_case ON {SCHEMA}.support_case_messages (case_id, created_at);")

    for table in ("support_cases", "support_case_messages"):
        op.execute(f"ALTER TABLE {SCHEMA}.{table} ENABLE ROW LEVEL SECURITY;")
        op.execute(f"ALTER TABLE {SCHEMA}.{table} FORCE ROW LEVEL SECURITY;")
        op.execute(_POLICY.format(schema=SCHEMA, table=table))


def downgrade() -> None:
    op.execute(f"DROP TABLE IF EXISTS {SCHEMA}.support_case_messages;")
    op.execute(f"DROP TABLE IF EXISTS {SCHEMA}.support_cases;")
    op.execute(f"DROP TABLE IF EXISTS {SCHEMA}.help_topics;")
