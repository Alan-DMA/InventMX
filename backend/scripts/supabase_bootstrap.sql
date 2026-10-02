-- =============================================================================
-- Preparación de Supabase para Nexus — despliegue de prueba (Oct 2026)
-- =============================================================================
-- Dónde: Supabase → SQL Editor (corre como el usuario `postgres`).
-- Cuándo: PARTE 1 una sola vez, ANTES de `alembic upgrade head`.
--         PARTE 2 después de las migraciones, para verificar.
-- Guía completa: docs/deployment/despliegue_prueba.md
-- =============================================================================


-- =============================================================================
-- PARTE 1 — antes de las migraciones
-- =============================================================================

-- 1. Rol de la aplicación -----------------------------------------------------
-- La app NO se conecta como `postgres`: en Supabase ese usuario tiene
-- BYPASSRLS, y con él las políticas de RLS (el aislamiento entre comercios)
-- no protegerían nada. `nexus_app` es igual al de tu Postgres local: dueño de
-- las tablas (las crea al migrar) y sin bypass.
--
-- Cambia la contraseña antes de ejecutar. Genérala con:
--   python -c "import secrets; print(secrets.token_urlsafe(24))"
-- (sólo letras, números, - y _ : así no hay que escaparla dentro de la URL)
CREATE ROLE nexus_app LOGIN PASSWORD 'CAMBIA_ESTA_CONTRASENA'
    NOSUPERUSER NOBYPASSRLS NOCREATEDB NOCREATEROLE;

-- CREATE en la base: la migración 0001 corre `CREATE SCHEMA IF NOT EXISTS
-- public` y Postgres revisa el permiso ANTES de ver que el esquema ya existe.
-- En local nexus_app es dueño de la base `nexus`; aquí la base es de Supabase.
GRANT CONNECT, CREATE ON DATABASE postgres TO nexus_app;
-- Crear tablas en `public` (las migraciones corren como nexus_app)
GRANT USAGE, CREATE ON SCHEMA public TO nexus_app;

-- 2. Extensiones que piden las migraciones -------------------------------------
-- nexus_app no puede crear extensiones; las deja listas `postgres`. pg_trgm va
-- en `public` porque el índice de búsqueda por nombre usa `gin_trgm_ops` y la
-- app sólo busca en `public`. gen_random_uuid() ya viene en Postgres.
CREATE EXTENSION IF NOT EXISTS pg_trgm WITH SCHEMA public;
-- La migración 0001 pide "uuid-ossp"; Supabase suele traerla ya instalada en
-- `extensions`. Si no existiera, nexus_app no podría crearla y la migración
-- fallaría con "permission denied to create extension".
CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA extensions;

-- 3. Bucket de fotos de productos ----------------------------------------------
-- Público: cualquiera con la URL puede VER la foto (igual que en la vitrina).
-- Subir sólo puede el backend con la llave secreta. Límite de 5 MB (el mismo
-- que valida la app) y sólo formatos de imagen.
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('product-images', 'product-images', true, 5242880,
        ARRAY['image/jpeg', 'image/png', 'image/webp'])
ON CONFLICT (id) DO NOTHING;

-- 4. Verificación de la parte 1 -------------------------------------------------
-- Esperado: nexus_app | false | false
SELECT rolname, rolsuper, rolbypassrls FROM pg_roles WHERE rolname = 'nexus_app';
-- Esperado: pg_trgm | public
SELECT e.extname, n.nspname AS esquema
FROM pg_extension e JOIN pg_namespace n ON n.oid = e.extnamespace
WHERE e.extname = 'pg_trgm';
-- Esperado: product-images | true | 5242880
SELECT id, public, file_size_limit FROM storage.buckets WHERE id = 'product-images';


-- =============================================================================
-- PARTE 2 — después de `alembic upgrade head` (sólo lectura, verifica)
-- =============================================================================

-- Todas las tablas son de nexus_app (esperado: una fila, nexus_app | 48, igual que local)
SELECT tableowner, count(*) FROM pg_tables WHERE schemaname = 'public' GROUP BY 1;

-- La Data API de Supabase (anon / authenticated) no tiene acceso a ninguna
-- tabla de Nexus (esperado: 0). Además se apaga en Project Settings → Data API.
SELECT count(*) AS permisos_expuestos
FROM information_schema.role_table_grants
WHERE table_schema = 'public' AND grantee IN ('anon', 'authenticated');

-- Tablas con RLS activa y forzada (comparar con local: 33 activas, 27 forzadas)
SELECT count(*) FILTER (WHERE c.relrowsecurity)      AS rls_activa,
       count(*) FILTER (WHERE c.relforcerowsecurity) AS rls_forzada,
       count(*)                                      AS tablas
FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public' AND c.relkind = 'r';
