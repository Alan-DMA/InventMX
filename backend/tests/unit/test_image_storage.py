"""
Guardado de fotos de productos (`app/core/storage.py`) — despliegue de prueba.

Sin base de datos ni red: el modo `local` escribe en un directorio temporal y
el modo `supabase` habla con un transporte falso de httpx.
"""
import uuid

import httpx
import jwt as pyjwt
import pytest

from app.core import storage
from app.core.config.settings import settings
from app.core.storage import ImageStorageError, save_image
from app.modules.inventory.api import endpoints

TENANT = "11111111-2222-3333-4444-555555555555"


@pytest.fixture
def supabase_settings(monkeypatch):
    monkeypatch.setattr(settings, "STORAGE_BACKEND", "supabase")
    monkeypatch.setattr(settings, "SUPABASE_URL", "https://abc.supabase.co/")
    monkeypatch.setattr(settings, "SUPABASE_STORAGE_BUCKET", "product-images")
    monkeypatch.setattr(settings, "SUPABASE_SERVICE_KEY", "sb_secret_prueba")


def _fake_client(monkeypatch, handler):
    """Hace que `storage` use un AsyncClient con transporte falso."""
    real_client = httpx.AsyncClient

    def factory(*args, **kwargs):
        return real_client(*args, transport=httpx.MockTransport(handler), **kwargs)

    monkeypatch.setattr(storage.httpx, "AsyncClient", factory)


async def test_local_guarda_en_disco_y_devuelve_ruta_relativa(monkeypatch, tmp_path):
    monkeypatch.setattr(settings, "STORAGE_BACKEND", "local")
    monkeypatch.setattr(settings, "UPLOAD_DIR", str(tmp_path))

    url = await save_image(b"jpeg-bytes", ".jpg", "image/jpeg", folder=TENANT)

    assert url.startswith("/uploads/images/") and url.endswith(".jpg")
    saved = tmp_path / "images" / url.rsplit("/", 1)[1]
    assert saved.read_bytes() == b"jpeg-bytes"


async def test_supabase_sube_al_bucket_en_la_carpeta_del_comercio(monkeypatch, supabase_settings):
    seen = {}

    def handler(request: httpx.Request) -> httpx.Response:
        seen["request"] = request
        return httpx.Response(200, json={"Key": "ok"})

    _fake_client(monkeypatch, handler)

    url = await save_image(b"jpeg-bytes", ".jpg", "image/jpeg", folder=TENANT)

    request = seen["request"]
    assert request.method == "POST"
    assert request.url.path.startswith(f"/storage/v1/object/product-images/{TENANT}/")
    assert request.headers["apikey"] == "sb_secret_prueba"
    # La llave nueva no es JWT: no va como Bearer
    assert "authorization" not in request.headers
    assert request.headers["content-type"] == "image/jpeg"
    assert request.headers["x-upsert"] == "false"
    assert request.content == b"jpeg-bytes"
    object_path = request.url.path.split("/product-images/", 1)[1]
    assert url == f"https://abc.supabase.co/storage/v1/object/public/product-images/{object_path}"


async def test_supabase_llave_heredada_jwt_va_tambien_como_bearer(monkeypatch, supabase_settings):
    monkeypatch.setattr(settings, "SUPABASE_SERVICE_KEY", "eyJhbGciOiJIUzI1NiJ9.x.y")
    seen = {}

    def handler(request: httpx.Request) -> httpx.Response:
        seen["auth"] = request.headers.get("authorization")
        return httpx.Response(200, json={})

    _fake_client(monkeypatch, handler)
    await save_image(b"x", ".png", "image/png", folder=TENANT)

    assert seen["auth"] == "Bearer eyJhbGciOiJIUzI1NiJ9.x.y"


async def test_supabase_rechazo_del_bucket_es_error_de_almacenamiento(monkeypatch, supabase_settings):
    _fake_client(monkeypatch, lambda request: httpx.Response(413, text="Payload too large"))

    with pytest.raises(ImageStorageError, match="413"):
        await save_image(b"x", ".jpg", "image/jpeg", folder=TENANT)


async def test_supabase_sin_red_es_error_de_almacenamiento(monkeypatch, supabase_settings):
    def handler(request: httpx.Request) -> httpx.Response:
        raise httpx.ConnectError("sin red", request=request)

    _fake_client(monkeypatch, handler)

    with pytest.raises(ImageStorageError, match="contactar"):
        await save_image(b"x", ".jpg", "image/jpeg", folder=TENANT)


async def test_supabase_sin_credenciales_falla_antes_de_llamar(monkeypatch, supabase_settings):
    monkeypatch.setattr(settings, "SUPABASE_SERVICE_KEY", "")

    with pytest.raises(ImageStorageError, match="SUPABASE_SERVICE_KEY"):
        await save_image(b"x", ".jpg", "image/jpeg", folder=TENANT)


async def test_destino_desconocido_es_error(monkeypatch):
    monkeypatch.setattr(settings, "STORAGE_BACKEND", "ftp")

    with pytest.raises(ImageStorageError, match="desconocido"):
        await save_image(b"x", ".jpg", "image/jpeg", folder=TENANT)


# ---------------------------------------------------------------------------
# Endpoint POST /inventory/upload-image (contrato sin cambios para la app)
# ---------------------------------------------------------------------------

async def _owner_headers(client):
    suffix = uuid.uuid4().hex[:6]
    resp = await client.post(
        "/api/v1/auth/register",
        json={
            "store_name": f"Fotos {suffix}",
            "slug": f"fotos-{suffix}",
            "full_name": "Dueña Fotos",
            "email": f"fotos_{suffix}@tienda.mx",
            "password": "password123",
        },
    )
    assert resp.status_code == 201
    token = resp.json()["access_token"]
    tenant_id = pyjwt.decode(token, options={"verify_signature": False})["tenant_id"]
    return {"Authorization": f"Bearer {token}"}, tenant_id


async def test_endpoint_guarda_en_la_carpeta_del_comercio_del_token(client, monkeypatch):
    calls = {}

    async def fake_save(content, ext, content_type, folder):
        calls.update(content=content, ext=ext, content_type=content_type, folder=folder)
        return "https://cdn.test/foto.jpg"

    monkeypatch.setattr(endpoints, "save_image", fake_save)
    headers, tenant_id = await _owner_headers(client)

    resp = await client.post(
        "/api/v1/inventory/upload-image",
        files={"file": ("foto.JPG", b"jpeg-bytes", "image/jpeg")},
        headers=headers,
    )

    assert resp.status_code == 200
    assert resp.json() == {"url": "https://cdn.test/foto.jpg"}
    assert calls == {
        "content": b"jpeg-bytes",
        "ext": ".jpg",
        "content_type": "image/jpeg",
        "folder": tenant_id,
    }


async def test_endpoint_rechaza_vacia_y_demasiado_pesada(client):
    headers, _ = await _owner_headers(client)

    empty = await client.post(
        "/api/v1/inventory/upload-image",
        files={"file": ("foto.jpg", b"", "image/jpeg")},
        headers=headers,
    )
    assert empty.status_code == 400

    too_big = await client.post(
        "/api/v1/inventory/upload-image",
        files={"file": ("foto.jpg", b"x" * (5 * 1024 * 1024 + 1), "image/jpeg")},
        headers=headers,
    )
    assert too_big.status_code == 413


async def test_endpoint_falla_del_almacenamiento_es_502(client, monkeypatch):
    async def failing_save(*args, **kwargs):
        raise ImageStorageError("bucket caído")

    monkeypatch.setattr(endpoints, "save_image", failing_save)
    headers, _ = await _owner_headers(client)

    resp = await client.post(
        "/api/v1/inventory/upload-image",
        files={"file": ("foto.jpg", b"jpeg-bytes", "image/jpeg")},
        headers=headers,
    )
    assert resp.status_code == 502
    assert "bucket" not in resp.text  # el detalle interno no sale al cliente
