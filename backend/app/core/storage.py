"""
Guardado de las fotos de productos (despliegue de prueba, Oct 2026).

Una sola puerta, `save_image`, con dos destinos según `STORAGE_BACKEND`:
- `local`: disco del servidor bajo UPLOAD_DIR/images, servido en /uploads
  (desarrollo). Devuelve la ruta relativa de siempre.
- `supabase`: bucket público de Supabase Storage. Devuelve la URL absoluta
  del CDN, así las fotos se descargan de Supabase y no del API.

La app sólo ve `{"url": ...}`: pasar a otro proveedor (S3, R2, el que traiga
el plan de pago) es otra rama aquí, sin tocar la app ni la base.
"""
import os
import uuid

import httpx

from app.core.config.settings import settings


class ImageStorageError(Exception):
    """El destino no recibió la foto (red, credenciales o límite del bucket)."""


async def save_image(content: bytes, ext: str, content_type: str, folder: str) -> str:
    """Guarda la foto con un nombre único y devuelve la URL con que se muestra."""
    filename = f"{uuid.uuid4().hex}{ext}"
    backend = settings.STORAGE_BACKEND.strip().lower()

    if backend == "local":
        images_dir = os.path.join(settings.UPLOAD_DIR, "images")
        os.makedirs(images_dir, exist_ok=True)
        with open(os.path.join(images_dir, filename), "wb") as f:
            f.write(content)
        return f"/uploads/images/{filename}"

    if backend == "supabase":
        return await _save_to_supabase(content, f"{folder}/{filename}", content_type)

    raise ImageStorageError(f"STORAGE_BACKEND desconocido: {settings.STORAGE_BACKEND!r}")


async def _save_to_supabase(content: bytes, object_path: str, content_type: str) -> str:
    base_url = settings.SUPABASE_URL.rstrip("/")
    bucket = settings.SUPABASE_STORAGE_BUCKET
    key = settings.SUPABASE_SERVICE_KEY
    if not base_url or not key:
        raise ImageStorageError("Faltan SUPABASE_URL o SUPABASE_SERVICE_KEY.")

    headers = {
        "apikey": key,
        "Content-Type": content_type,
        # El nombre es único y nunca se reescribe: el CDN y el teléfono pueden
        # guardarla un año sin volver a descargarla (ahorra cuota de salida).
        "cache-control": "max-age=31536000",
        "x-upsert": "false",
    }
    # Las llaves heredadas (service_role) son JWT y Storage las espera también
    # como Bearer; las nuevas (sb_secret_...) no son JWT y van sólo en `apikey`.
    if key.startswith("eyJ"):
        headers["Authorization"] = f"Bearer {key}"

    try:
        async with httpx.AsyncClient(timeout=30) as client:
            response = await client.post(
                f"{base_url}/storage/v1/object/{bucket}/{object_path}",
                content=content,
                headers=headers,
            )
    except httpx.HTTPError as exc:
        raise ImageStorageError(f"No se pudo contactar el almacenamiento: {exc}") from exc

    if response.status_code >= 400:
        raise ImageStorageError(
            f"El almacenamiento rechazó la foto ({response.status_code}): {response.text[:200]}"
        )
    return f"{base_url}/storage/v1/object/public/{bucket}/{object_path}"
