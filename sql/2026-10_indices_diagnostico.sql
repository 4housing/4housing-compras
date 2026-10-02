-- Índices: diagnóstico post-migración (aaqp -> wcpk). SOLO LECTURA, no modifica nada.
-- Correr a mano en el SQL Editor de Supabase del proyecto wcpk (wcpkpwxhqdcdljfwzcmy).
--
-- Contexto: la app leía/escribía los índices en tablas sin prefijo (idx_ipc, idx_cac, ...).
-- La migración renombró las rutas literales a compras_*, pero las de Índices se arman
-- dinámicamente desde IDX_DEF y quedaron apuntando a idx_* (que no existen en wcpk).
-- El fix del index.html las apunta a compras_idx_*. Este script confirma que esas tablas
-- existen en wcpk, cuántos períodos tienen y que tengan RLS + policies.

-- 1) ¿Qué tablas de índices existen (con o sin prefijo)?
select table_schema, table_name
from information_schema.tables
where table_name like '%idx\_%' escape '\'
order by table_name;

-- 2) Cantidad de períodos y rango por tabla (si alguna no existe, este bloque falla:
--    en ese caso fijate el resultado del paso 1 y avisá cuál falta).
select 'compras_idx_ipc'           as tabla, count(*) as filas, min(periodo), max(periodo) from public.compras_idx_ipc
union all select 'compras_idx_cac',           count(*), min(periodo), max(periodo) from public.compras_idx_cac
union all select 'compras_idx_poli',          count(*), min(periodo), max(periodo) from public.compras_idx_poli
union all select 'compras_idx_uva',           count(*), min(periodo), max(periodo) from public.compras_idx_uva
union all select 'compras_idx_facpce',        count(*), min(periodo), max(periodo) from public.compras_idx_facpce
union all select 'compras_idx_dolar_oficial', count(*), min(periodo), max(periodo) from public.compras_idx_dolar_oficial
union all select 'compras_idx_dolar_blue',    count(*), min(periodo), max(periodo) from public.compras_idx_dolar_blue
union all select 'compras_idx_sueldos',       count(*), min(periodo), max(periodo) from public.compras_idx_sueldos;

-- 3) RLS activado y policies (deben ser para authenticated con tiene_sector('compras')).
select c.relname as tabla, c.relrowsecurity as rls_activo
from pg_class c join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public' and c.relname like 'compras\_idx\_%' escape '\'
order by 1;

select tablename, policyname, roles, cmd, qual, with_check
from pg_policies
where schemaname = 'public' and tablename like 'compras\_idx\_%' escape '\'
order by tablename, policyname;
