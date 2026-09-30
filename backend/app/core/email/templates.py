"""
Textos de los correos al tendero: cortos, en sus palabras y sin enlaces (un
correo de "recupera tu cuenta" con enlace es justo lo que imita el phishing).
"""
from datetime import datetime
from typing import Optional

from app.core.email.sender import Attachment, EmailMessage

_SIGNATURE = "\n\n— Soporte Nexus"


def _when(moment: datetime) -> str:
    return moment.strftime("%d/%m/%Y %H:%M") + " (UTC)"


def login_code_email(
    to_email: str,
    full_name: str,
    code: str,
    expires_at: datetime,
    assisted: bool,
) -> EmailMessage:
    if assisted:
        intro = (
            "Soporte Nexus revisó tu solicitud para recuperar el acceso a tu tienda y te generó "
            "este código de un solo uso:"
        )
        warning = "Si no hablaste con soporte, no uses el código y respóndenos a este correo."
    else:
        intro = "Pediste recuperar tu contraseña. Tu código de un solo uso es:"
        warning = "Si no lo pediste tú, ignora este correo: tu contraseña sigue siendo la misma."
    text = (
        f"Hola, {full_name}:\n\n"
        f"{intro}\n\n"
        f"    {code}\n\n"
        "En la app, toca \"¿Olvidaste tu contraseña?\" → \"Ya tengo un código\", escribe tu correo y "
        "este código. Al entrar te pediremos una contraseña nueva.\n\n"
        f"Vence el {_when(expires_at)} y sólo sirve una vez. Nadie de Nexus te lo va a pedir.\n"
        f"{warning}"
        f"{_SIGNATURE}"
    )
    return EmailMessage(
        to_email=to_email,
        to_name=full_name,
        subject="Tu código para entrar a Nexus",
        text=text,
    )


def data_export_email(to_email: str, full_name: str, store_name: str, filename: str, content: bytes) -> EmailMessage:
    text = (
        f"Hola, {full_name}:\n\n"
        f"Te enviamos la copia de los datos de {store_name} que pediste a soporte. Va adjunta en un "
        "archivo .zip con una hoja (CSV) por cada tipo de dato: productos, ventas, clientes, compras, "
        "caja y lo demás. Se abren con Excel o Google Sheets.\n\n"
        "Nadie de soporte vio el contenido: el archivo se generó y se envió directo a tu correo."
        f"{_SIGNATURE}"
    )
    return EmailMessage(
        to_email=to_email,
        to_name=full_name,
        subject=f"Copia de los datos de {store_name}",
        text=text,
        attachments=[Attachment(filename=filename, content=content)],
    )


def store_deleted_email(to_email: str, full_name: str, store_name: str) -> EmailMessage:
    text = (
        f"Hola, {full_name}:\n\n"
        f"Como lo pediste, eliminamos la tienda {store_name} y todos sus datos de Nexus. "
        "Ya no se pueden recuperar.\n\n"
        "Gracias por haber usado Nexus. Si algún día quieres volver, puedes registrarte de nuevo desde la app."
        f"{_SIGNATURE}"
    )
    return EmailMessage(to_email=to_email, to_name=full_name, subject=f"Eliminamos {store_name} de Nexus", text=text)


def case_reply_email(to_email: str, name: Optional[str], number: int, title: str, reply: str, in_app: bool) -> EmailMessage:
    """Soporte respondió un caso. Va el texto completo: quien escribió sin sesión no tiene otro lugar donde leerlo."""
    where = (
        "Puedes seguir la conversación en la app, en el menú ☰ · Soporte."
        if in_app
        else "Si necesitas agregar algo, vuelve a escribirnos desde \"No puedo entrar a mi cuenta\" y menciona "
             f"el caso {number}."
    )
    text = (
        f"Hola{', ' + name if name else ''}:\n\n"
        f"Soporte respondió tu caso {number} ({title}):\n\n"
        f"{reply}\n\n"
        f"{where}"
        f"{_SIGNATURE}"
    )
    return EmailMessage(to_email=to_email, to_name=name, subject=f"Respuesta a tu caso {number}", text=text)


def public_case_received_email(to_email: str, name: Optional[str], number: int) -> EmailMessage:
    text = (
        f"Hola{', ' + name if name else ''}:\n\n"
        f"Recibimos tu caso {number}. Lo revisamos y te respondemos a este correo.\n\n"
        "Si lo que pasa es que no puedes entrar, es posible que te pidamos algunos datos de tu tienda para "
        "confirmar que la cuenta es tuya. Nadie de Nexus te va a pedir tu contraseña."
        f"{_SIGNATURE}"
    )
    return EmailMessage(to_email=to_email, to_name=name, subject=f"Recibimos tu caso {number}", text=text)
