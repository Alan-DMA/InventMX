# Despliegue de prueba — Render + Supabase (infraestructura gratis)

> **Para qué es:** poner Nexus en internet para **una tienda de prueba** con planes gratuitos y entender, paso por paso, qué hace cada pieza.
> **Qué no es:** el despliegue comercial definitivo. Al final hay una sección sobre qué cambia cuando pasen a planes de pago (spoiler: casi solo variables de entorno).
>
> Preparado el 1 de octubre de 2026. Los límites de los planes gratuitos cambian: revísalos en las páginas de precios de cada servicio antes de empezar.

---

## 0. El mapa mental: qué es "desplegar"

En tu PC, todo vive en la misma máquina: Postgres, `uvicorn`, la carpeta `uploads/` y la app en el emulador o en el teléfono por la red local. Desplegar es **separar esas piezas y ponerlas en servidores que siempre están en internet**, cada una en el servicio que mejor la aloja:

```
 Teléfono (APK)                Navegador (vitrina /tienda/...)
      │  HTTPS + WSS                 │ HTTPS (archivos estáticos)
      ▼                              ▼
┌───────────────────┐        ┌────────────────────┐
│ Render            │        │ Render Static Site │  ← Flutter Web compilado
│ nexus-api         │        │ nexus-tienda       │     (HTML/JS, sin servidor)
│ (FastAPI/uvicorn) │        └────────────────────┘
└───┬───────────┬───┘                   │ <img src=https://...supabase.co/...>
    │ SQL       │ sube la foto          │
    ▼           ▼                       ▼
┌─────────────────────────────────────────────────┐
│ Supabase                                        │
│  • Postgres (las tablas, RLS)                   │
│  • Storage: bucket "product-images" (CDN)  ◄────┘  las fotos se DESCARGAN
└─────────────────────────────────────────────────┘    directo de aquí
```

Seis conceptos que aparecen en toda la guía:

| Concepto | En tu PC | En producción |
|---|---|---|
| **Configuración** | `backend/.env` | **Variables de entorno** en el panel de Render. El código es el mismo; solo cambia la configuración. `pydantic-settings` lee primero las variables del sistema y luego el `.env` |
| **Build vs. start** | Instalaste dependencias una vez y luego corres `uvicorn` | Render ejecuta un *build command* (`pip install …`) en cada deploy y después un *start command* (`uvicorn …`) |
| **Puerto** | `:8000` fijo | Render asigna un puerto en `$PORT` y pone delante su propio proxy con HTTPS. Tú solo ves `https://nexus-api.onrender.com` |
| **Disco** | Permanente | **Efímero:** se borra en cada deploy o reinicio. Por eso las fotos van a Supabase Storage y no a `uploads/` |
| **Migraciones** | `alembic upgrade head` contra tu Postgres | Un paso **aparte** del deploy, que corres tú desde tu PC contra la base de Supabase |
| **Valores horneados en la app** | `API_URL` cae en `127.0.0.1` / `10.0.2.2` | Flutter no lee la URL al arrancar: se "hornea" al compilar con `--dart-define`. Si cambia la URL, se recompila el APK |

### Archivos que ya quedaron listos en el repo

| Archivo | Qué hace |
|---|---|
| [`render.yaml`](../../render.yaml) | **Blueprint:** describe los dos servicios de Render (API y vitrina) y sus variables |
| [`tools/render_build_web.sh`](../../tools/render_build_web.sh) | Build de la vitrina en Render: descarga Flutter y compila con las URLs de producción |
| [`tools/build_apk_prueba.ps1`](../../tools/build_apk_prueba.ps1) | Compila el APK apuntando al servidor desplegado |
| [`backend/scripts/supabase_bootstrap.sql`](../../backend/scripts/supabase_bootstrap.sql) | Prepara Supabase: rol `nexus_app`, extensión `pg_trgm`, bucket de fotos y consultas de verificación |
| [`backend/.env.production.example`](../../backend/.env.production.example) | Lista de variables de producción y de dónde sale cada valor |
| `backend/app/core/storage.py` | Guarda las fotos en disco (`STORAGE_BACKEND=local`) o en Supabase (`=supabase`) |

---

## 1. Antes de empezar

- [ ] El código con estos archivos está **en GitHub** (rama `main` de `Alan-DMA/InventMX`). Render despliega desde GitHub, no desde tu PC.
- [ ] **Acceso de Render al repositorio.** El repo es de la cuenta de Alan. Para que Render lo vea, hay dos caminos:
  - Alan instala la app de Render en su GitHub y le da acceso a ese repo.
  - O haces un *fork* a tu cuenta y despliegas desde ahí. En ese caso, recuerda sincronizar el fork.
- [ ] Cuentas creadas: [supabase.com](https://supabase.com), [render.com](https://render.com) (entra con GitHub), [brevo.com](https://brevo.com) para el correo y [cron-job.org](https://cron-job.org) para el ping.
- [ ] Un gestor de contraseñas o una nota segura. Vas a generar 3 o 4 secretos y no deben ir al repo ni al chat.

---

## 2. Supabase: base de datos y almacenamiento de fotos

### 2.1 Crear el proyecto
1. *New project* → nombre `nexus-prueba` → **Region: East US (North Virginia) `us-east-1`**. Es la región más cercana a Render Virginia: cada consulta SQL viaja entre los dos servicios, así que estar cerca importa.
2. *Database password*: genera una y guárdala. Es la del usuario `postgres` (el administrador) y **no** la usará la app.

### 2.2 Preparar la base (parte 1 del script)
1. Genera la contraseña de `nexus_app` en tu PC:
   ```powershell
   python -c "import secrets; print(secrets.token_urlsafe(24))"
   ```
2. Supabase → **SQL Editor** → pega la **PARTE 1** de [`supabase_bootstrap.sql`](../../backend/scripts/supabase_bootstrap.sql), reemplaza `CAMBIA_ESTA_CONTRASENA` y ejecuta.
3. Revisa los tres resultados de verificación al final. Deben coincidir con los comentarios "Esperado".

**Por qué un rol propio:** en Supabase, `postgres` tiene el atributo `BYPASSRLS`. Si la app se conectara con él, las políticas de RLS que separan a un comercio de otro **no se aplicarían**. `nexus_app` es idéntico al de tu Postgres local: es dueño de las tablas y no tiene bypass.

### 2.3 Apagar la Data API
Supabase publica automáticamente una API REST (PostgREST) sobre el esquema `public`. Nexus no la usa: todo pasa por FastAPI. Apágala para que no sea una puerta extra a tus tablas:

**Project Settings → Data API →** desactiva la Data API. Si tu versión del panel no tiene ese interruptor, quita `public` de *Exposed schemas*.

### 2.4 Juntar los tres datos de conexión
| Dato | Dónde | Para qué variable |
|---|---|---|
| Cadena de conexión | Botón **Connect** (arriba) → **Session pooler** | `DATABASE_URL` |
| Project URL | Project Settings → Data API | `SUPABASE_URL` |
| Llave secreta | Project Settings → **API Keys** → *secret key* (`sb_secret_…`) o, en *Legacy*, `service_role` | `SUPABASE_SERVICE_KEY` |

**Arma la `DATABASE_URL`** a partir de la del *Session pooler*:
```
Supabase te da:  postgresql://postgres.abcdxyz:[YOUR-PASSWORD]@aws-0-us-east-1.pooler.supabase.com:5432/postgres
Tú usas:         postgresql+asyncpg://nexus_app.abcdxyz:<contraseña de nexus_app>@aws-0-us-east-1.pooler.supabase.com:5432/postgres
```
Hay tres cambios: el driver `+asyncpg`, el usuario `nexus_app.<ref>` y la contraseña de `nexus_app`.

> ⚠️ **Puerto 5432 (Session pooler), nunca 6543 (Transaction pooler).** El backend fija el comercio actual con `set_config(..., false)`, que dura **toda la sesión** de la conexión. En modo transacción, el pooler reparte las transacciones entre conexiones distintas: el contexto de RLS de una tienda podría quedar en la conexión que luego usa otra. En modo sesión, cada conexión del backend es una conexión real de Postgres, igual que en tu PC.
>
> **¿Por qué el pooler y no la conexión directa?** En el plan gratis, la conexión directa de Supabase solo funciona por IPv6, y Render no sale a internet por IPv6.

> 🔒 La llave secreta (`SUPABASE_SERVICE_KEY`) puede hacer **todo** en el proyecto. Solo va en Render. La app nunca la ve: el teléfono le manda la foto al backend y es el backend quien la sube.

---

## 3. Migraciones: crear las tablas desde tu PC

Render gratis no tiene un "comando previo al deploy", y de todos modos conviene que las migraciones sean un paso consciente. Las corres tú, desde `backend/`, apuntando a Supabase:

```powershell
cd backend
$env:DATABASE_URL = "postgresql+asyncpg://nexus_app.<ref>:<contraseña>@aws-0-us-east-1.pooler.supabase.com:5432/postgres"
.venv\Scripts\alembic upgrade head
```

- `$env:DATABASE_URL` vive solo en **esa ventana** de PowerShell y le gana al `backend/.env`. Cierra la ventana al terminar o haz `Remove-Item Env:DATABASE_URL`, para no correr por error algo contra producción creyendo que es local.
- `alembic/env.py` cambia `asyncpg` por `psycopg2` por su cuenta, así que es la misma URL que usará la app.
- Al terminar, en el SQL Editor de Supabase ejecuta la **PARTE 2** del script de bootstrap. Tiene que mostrar 48 tablas de `nexus_app`, 0 permisos expuestos y RLS 33/27, igual que local.

**¿Panel de fundadores?** Si lo vas a usar en la prueba, crea tu operador con la misma variable apuntando a Supabase:
```powershell
.venv\Scripts\python.exe -m scripts.platform_operator create --email tu@correo --name "Eduardo"
```

---

## 4. Ensayo general en tu PC (recomendado)

Antes de subir nada, corre el backend **en tu PC pero contra Supabase**. Si algo falla aquí (contraseña, pooler, bucket), lo ves en tu consola y no en los logs remotos de Render:

```powershell
cd backend
$env:DATABASE_URL = "postgresql+asyncpg://nexus_app.<ref>:...@...:5432/postgres"
$env:STORAGE_BACKEND = "supabase"
$env:SUPABASE_URL = "https://<ref>.supabase.co"
$env:SUPABASE_SERVICE_KEY = "sb_secret_..."
$env:DB_POOL_SIZE = "5"; $env:DB_MAX_OVERFLOW = "5"
.venv\Scripts\uvicorn app.main:app --port 8001
```
1. `http://127.0.0.1:8001/health` debe responder `"database": "connected"`.
2. Registra una tienda desde `http://127.0.0.1:8001/docs` (`POST /auth/register`), autorízate con el token y sube una foto en `POST /inventory/upload-image`. La respuesta debe ser `https://<ref>.supabase.co/storage/v1/object/public/product-images/<tenant>/<archivo>.jpg`. Ábrela en el navegador.
3. En Supabase → Storage → `product-images` debe aparecer la carpeta del comercio.

Si quieres empezar con la base limpia, borra esa tienda de prueba o ignórala.

---

## 5. Render: el API y la vitrina

### 5.1 Crear los servicios desde el Blueprint
1. Render → **New → Blueprint** → elige el repo → Render detecta `render.yaml`.
2. Te pedirá los valores marcados `sync: false`:

| Variable | Servicio | Valor |
|---|---|---|
| `DATABASE_URL` | nexus-api | La del paso 2.4 |
| `SUPABASE_URL` | nexus-api | `https://<ref>.supabase.co` |
| `SUPABASE_SERVICE_KEY` | nexus-api | La llave secreta |
| `ALLOWED_ORIGINS` | nexus-api | `https://nexus-tienda.onrender.com` |
| `BREVO_API_KEY`, `EMAIL_FROM_ADDRESS` | nexus-api | Paso 6 (si aún no lo tienes, pon cualquier texto y corrígelo después) |
| `API_URL` | nexus-tienda | `https://nexus-api.onrender.com` |
| `CATALOG_BASE_URL` | nexus-tienda | `https://nexus-tienda.onrender.com/tienda` |

3. *Apply*. Render crea los dos servicios y lanza el primer deploy. El API tarda unos 2 o 3 minutos; la vitrina, de 5 a 8, porque descarga Flutter.

> **El huevo y la gallina de las URLs:** la URL pública sale del nombre del servicio (`nexus-api` → `nexus-api.onrender.com`). Si el nombre ya está ocupado en Render, te asigna uno con sufijo (por ejemplo `nexus-api-x1y2.onrender.com`). Cuando termine, mira las URLs reales en el panel. Si no coinciden, corrige `ALLOWED_ORIGINS`, `API_URL` y `CATALOG_BASE_URL` en *Environment* y haz **Manual Deploy**. La vitrina **tiene que recompilarse**, porque las URLs están horneadas en el JavaScript.

### 5.2 Qué hace cada valor del `render.yaml`
- `rootDir: backend`: Render trabaja dentro de esa carpeta del monorepo.
- `PYTHON_VERSION=3.12.10`: la misma de tu `.venv`. Sin ella, Render usa su versión por defecto y algún paquete podría no tener wheel para esa versión.
- `ENVIRONMENT=production`: cierra el CORS a `ALLOWED_ORIGINS`, apaga el log de SQL, apaga la vitrina servida por el backend (solo es para desarrollo) y hace que el correo `console` se niegue a "enviar".
- `generateValue: true`: Render inventa `SECRET_KEY`, `PLATFORM_JWT_SECRET` y `PLATFORM_TOTP_KEY` una sola vez. Si los cambias después, se cierran todas las sesiones.
- `DB_POOL_SIZE=5` y `DB_MAX_OVERFLOW=5`: hasta 10 conexiones, dentro de las ~15 del pooler gratis, y deja espacio para que tú corras migraciones al mismo tiempo.
- `healthCheckPath: /health`: Render solo da por bueno un deploy nuevo si `/health` responde. Si no responde, mantiene el anterior.
- Vitrina `routes: rewrite /* → /index.html`: el enlace `/tienda/mi-tienda/pedido/P-123` no es un archivo real. Render devuelve `index.html` y Flutter decide qué pantalla mostrar.

### 5.3 Verificar
- `https://nexus-api.onrender.com/health` → `{"status":"online","database":"connected",...}`
- `https://nexus-api.onrender.com/docs` → Swagger. Queda público en esta prueba; para el despliegue comercial conviene apagarlo.
- Render → nexus-api → **Logs**: ahí sale todo lo que en tu PC salía en la consola de `uvicorn`.

---

## 6. Correo (Brevo)

Sin correo no funcionan los códigos de acceso ni la recuperación de cuenta. En producción, `EMAIL_BACKEND=console` se niega a enviar a propósito, para que nadie crea que un correo salió cuando no salió.

1. Brevo → **Senders** → agrega y verifica tu correo como remitente. No hace falta un dominio propio.
2. **SMTP & API → API Keys →** crea una llave.
3. En Render, cambia `BREVO_API_KEY` y `EMAIL_FROM_ADDRESS` (el correo verificado) y haz *Manual Deploy*.

El plan gratis permite 300 correos al día.

---

## 7. Mantener despierto el API (ping)

Render gratis **duerme el API tras 15 minutos sin tráfico**, y la primera petición después tarda de 30 a 60 s en despertarlo. La app corta las peticiones a los 10 s, así que ese primer intento fallaría.

**Solución sin código:** [cron-job.org](https://cron-job.org) → nuevo cron job → URL `https://nexus-api.onrender.com/health` → **cada 10 minutos**.

- Las cuentas: Render da 750 h al mes de instancia gratis y el mes tiene como máximo 744 h. Alcanza para **un** servicio despierto todo el tiempo. La vitrina es estática y no gasta horas.
- Beneficio extra: `/health` hace `SELECT 1` en la base, y esa actividad evita que Supabase **pause el proyecto** después de 7 días sin uso.

---

## 8. El APK de la tienda de prueba

```powershell
powershell -ExecutionPolicy Bypass -File tools\build_apk_prueba.ps1 `
    -ApiUrl https://nexus-api.onrender.com `
    -CatalogUrl https://nexus-tienda.onrender.com/tienda
```
- El script primero revisa que `/health` responda y después compila con las URLs horneadas.
- Resultado: `frontend\build\app\outputs\flutter-apk\app-release.apk`. Cópialo al teléfono e instálalo (permitiendo "orígenes desconocidos").
- Va firmado con la llave de depuración. Sirve para la prueba, pero Play Store exige una llave de *release* propia.

---

## 9. Prueba de humo en el teléfono

1. Registra la tienda de prueba desde el APK.
2. Crea un producto **con foto tomada con la cámara**. En Supabase → Storage debe aparecer en `product-images/<id del comercio>/`.
3. Edita la foto con el **modo avión activado**. Debe aparecer "No se pudo subir la foto…" con el botón **Reintentar** y el producto debe conservar su foto anterior. Desactiva el modo avión y toca **Reintentar**.
4. Comparte el enlace del catálogo y ábrelo en otro teléfono. La vitrina debe cargar, con las fotos.
5. Haz un pedido desde la vitrina. Debe llegar al tendero **en vivo**, por WebSocket (`wss://`).
6. Cobra el pedido en caja y haz el corte.
7. Prueba "¿Olvidaste tu contraseña?". Debe llegar el correo de Brevo.
8. Deja de usar la app 20 minutos con el ping apagado y vuelve a usarla. Así ves el arranque en frío con tus propios ojos y entiendes para qué sirve el paso 7.

---

## 10. El día a día después del primer deploy

- **Código nuevo:** cada push a `main` dispara un deploy automático de ambos servicios. Si prefieres desplegar a mano, en cada servicio ve a Settings → *Auto-Deploy: Off* y usa *Manual Deploy*.
  > Ojo: `main` es compartida con Alan. Con el auto-deploy encendido, sus pushes también despliegan.
- **Migraciones nuevas:** el orden importa. **Primero** `alembic upgrade head` contra Supabase (paso 3) y **después** el deploy del código que usa esas columnas. Al revés, el código nuevo consultaría columnas que todavía no existen.
- **Volver atrás:** Render → nexus-api → *Events* → elige un deploy anterior → *Rollback*. La base **no** vuelve atrás sola.
- **Respaldos:** Supabase gratis no guarda respaldos descargables. Antes de un cambio delicado, haz tu propio respaldo:
  ```powershell
  pg_dump "postgresql://nexus_app.<ref>:...@...:5432/postgres" -Fc -f respaldo.dump
  ```

---

## 11. Problemas comunes

| Síntoma | Causa probable | Arreglo |
|---|---|---|
| Deploy del API falla en el build | Versión de Python o un paquete | Revisa los *Logs* del build; confirma `PYTHON_VERSION` |
| Build de la vitrina falla al descargar o compilar Flutter | Imagen de build de Render o versión de Flutter | Revisa que `FLUTTER_VERSION` exista como tag (`3.47.2`). Plan B: `flutter build web` en tu PC con los mismos `--dart-define` y sube `build/web` a un hosting estático de arrastrar y soltar |
| `/health` → `"database": "disconnected"` | `DATABASE_URL` mal armada | Revisa el usuario `nexus_app.<ref>`, el puerto 5432, el driver `+asyncpg` y que la contraseña no tenga caracteres que haya que escapar |
| `password authentication failed for user "nexus_app"` | Falta el `.<ref>` en el usuario, o la contraseña no es la de `nexus_app` | El usuario del pooler **siempre** lleva el `.<ref>` del proyecto |
| `remaining connection slots are reserved` / `too many clients` | Demasiadas conexiones | Baja `DB_POOL_SIZE`/`DB_MAX_OVERFLOW`; cierra los `uvicorn` locales que apunten a Supabase |
| La subida de foto da 502 | Bucket o llave | Logs de Render: el mensaje dice si fue 401 (llave), 404 (bucket) o 413 (tamaño) |
| La vitrina carga pero no trae datos | CORS o `API_URL` | Consola del navegador (F12): un error de CORS significa que `ALLOWED_ORIGINS` no tiene la URL exacta de la vitrina (con `https`, sin `/` final) |
| La vitrina muestra 404 en `/tienda/...` | Falta el rewrite | Revisa *Redirects/Rewrites* del static site: `/* → /index.html` |
| La app tarda en responder la primera vez | Render dormido | Revisa que el ping de cron-job.org esté activo |
| Supabase "Project paused" | 7 días sin actividad | *Restore* en el panel; revisa el ping |
| Al migrar: `permission denied to create extension` | Faltó la parte 1 del bootstrap | Ejecútala como `postgres` en el SQL Editor y vuelve a migrar |

---

## 12. Límites del plan gratis (a vigilar)

| Servicio | Límite | Qué lo consume en Nexus |
|---|---|---|
| Render (API) | 512 MB de RAM, 750 h/mes, duerme a los 15 min | Las peticiones del API. Las fotos ya no pasan por aquí al verse |
| Supabase Postgres | 500 MB | Hoy, tu base local con datos de QA pesa 44 MB |
| Supabase Storage | 1 GB | Cada foto pesa unos 150–400 KB (la app comprime a 1280 px). Unas 3,000 fotos |
| Supabase salida de datos | ~5 GB/mes | Descargas de fotos. Las fotos llevan caché de 1 año, así que cada teléfono las baja una vez |
| Brevo | 300 correos/día | Códigos de acceso, recuperación, soporte |

Supabase → *Reports / Usage* muestra el consumo de los tres.

---

## 13. Cuando pasen a un plan de pago

La arquitectura no cambia: está pensada para que el salto sea de **configuración**.

| Hoy (gratis) | Al pagar | Qué se toca |
|---|---|---|
| Render free + ping | Render Starter: no duerme | Quitar el ping. Nada de código |
| Supabase free | Supabase Pro (respaldos diarios, sin pausa) | Nada |
| Otro Postgres (RDS, Neon, etc.) | — | `DATABASE_URL` y el script de rol. Hay que conservar el modo sesión o la conexión directa por lo de RLS |
| Fotos en Supabase Storage | S3 / R2 / el que traiga el plan | Una función nueva en `app/core/storage.py` y `STORAGE_BACKEND`. La app no cambia, porque solo recibe `{"url": ...}` |
| Vitrina en `onrender.com` | Dominio propio | Nuevas `ALLOWED_ORIGINS`, `CATALOG_BASE_URL` y `API_URL`, y recompilar la vitrina y el APK |

---

## 14. Decisiones abiertas antes de dar el APK a la tienda

- **Red comunitaria y "clonar catálogo"** siguen con datos simulados por defecto (`COMMUNITY_MOCK`, `CLONE_MOCK` = `true`). En la tienda de prueba mostrarían productos ficticios. Hay que decidir si se ocultan o si se conectan al backend real (el de clonar todavía no existe en el servidor).
- **Panel de fundadores** (`lib/main_admin.dart`): no está en el Blueprint. Si se quiere en esta prueba, es otro *static site* igual a la vitrina, con `flutter build web -t lib/main_admin.dart`, y su URL debe agregarse a `ALLOWED_ORIGINS`.
