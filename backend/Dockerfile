# Imagen del API de Nexus (FastAPI + uvicorn).
# Construir desde la raíz del repo:  docker build -t nexus-api backend
# Explicación paso a paso: docs/deployment/despliegue_prueba.md → "Docker".

# 1. Imagen base: un Linux mínimo (Debian "slim") con Python ya instalado.
#    La versión exacta es la misma de tu .venv local.
FROM python:3.12.10-slim

# 2. Ajustes de Python dentro del contenedor:
#    - no escribir .pyc (el contenedor es desechable, no sirven de caché)
#    - no retener la salida: los print/log aparecen al instante en `docker logs`
#    - pip sin caché ni aviso de versión (imagen más chica, build más limpio)
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

# 3. Carpeta de trabajo dentro de la imagen (como hacer `cd /app`)
WORKDIR /app

# 4. Dependencias ANTES que el código. Cada instrucción es una "capa" que
#    Docker guarda en caché: si sólo cambias código, esta capa (la lenta) se
#    reutiliza y el build tarda segundos en vez de minutos.
COPY requirements.txt .
RUN pip install -r requirements.txt

# 5. El código. Lo que no debe entrar (.venv, .env, uploads, tests) lo
#    excluye .dockerignore.
COPY . .

# 6. No correr como root: si alguien explotara una falla del API, no tendría
#    permisos de administrador dentro del contenedor. `uploads/` debe ser
#    escribible porque main.py crea esa carpeta al arrancar.
RUN useradd --create-home --uid 10001 nexus \
    && mkdir -p uploads/images \
    && chown -R nexus:nexus uploads
USER nexus

# 7. Documenta el puerto (no lo abre: eso lo hace `docker run -p`).
EXPOSE 8000

# 8. Qué se ejecuta al arrancar un contenedor de esta imagen. Render (y casi
#    cualquier proveedor) indica el puerto en $PORT; en tu PC cae en 8000.
#    `exec` hace que uvicorn reciba directo la señal de apagado.
CMD ["sh", "-c", "exec uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8000} --proxy-headers --forwarded-allow-ips='*'"]
