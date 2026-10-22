-- =====================================================================
-- Pañol · precio de referencia por artículo y por mes (oct 2026)
-- Proyecto Supabase: wcpkpwxhqdcdljfwzcmy. Correr A MANO en el SQL Editor,
-- ANTES de publicar el index.html que usa esta tabla.
--
-- Qué hace (aditivo): crea compras_panol_precios_mes. En la solapa Precios de Pañol se corrige el precio con el que se valorizan las
-- erogaciones de un artículo en un mes; ese precio queda guardado acá y lo toman también las erogaciones que se carguen después de ese
-- artículo y mes. Una fila por (periodo, artículo). Si el período está CERRADO, el trigger impide crear, cambiar o borrar su precio
-- (queda congelado, igual que las erogaciones).
-- RLS: solo authenticated con public.tiene_sector('compras'::public.sector_portal). Nada para anon.
--
-- Reversible:
--   drop trigger compras_panol_precios_mes_cierre_guard on public.compras_panol_precios_mes;
--   drop function public.compras_panol_precios_mes_cierre_guard();
--   drop table public.compras_panol_precios_mes;
-- Requiere que ya exista compras_panol_cierres (sql/2026-10_panol_cierres.sql).
-- =====================================================================
begin;

create table if not exists public.compras_panol_precios_mes (
  id             bigint generated always as identity primary key,
  periodo        integer not null,            -- aaaamm
  cod_articulo   text not null,
  precio_ars     numeric not null,
  precio_usd     numeric,
  tc             numeric,                     -- tipo de cambio usado para pasar de ARS a USD (o al revés)
  modificado_por text,
  modificado_en  timestamptz not null default now(),
  unique (periodo, cod_articulo)
);

alter table public.compras_panol_precios_mes enable row level security;
revoke all on public.compras_panol_precios_mes from anon;
grant select, insert, update, delete on public.compras_panol_precios_mes to authenticated;
drop policy if exists compras_panol_precios_mes_all on public.compras_panol_precios_mes;
create policy compras_panol_precios_mes_all on public.compras_panol_precios_mes for all to authenticated
  using (public.tiene_sector('compras'::public.sector_portal)) with check (public.tiene_sector('compras'::public.sector_portal));

create or replace function public.compras_panol_precios_mes_cierre_guard()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  p integer;
begin
  p := case when tg_op = 'DELETE' then old.periodo else new.periodo end;
  if exists (select 1 from public.compras_panol_cierres c where c.periodo = p and c.estado = 'Cerrado')
     or (tg_op = 'UPDATE' and exists (select 1 from public.compras_panol_cierres c where c.periodo = old.periodo and c.estado = 'Cerrado')) then
    raise exception 'El período % está cerrado: los precios no se pueden modificar (un administrador puede reabrirlo en Pañol > Cierres).', p;
  end if;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;
drop trigger if exists compras_panol_precios_mes_cierre_guard on public.compras_panol_precios_mes;
create trigger compras_panol_precios_mes_cierre_guard
  before insert or update or delete on public.compras_panol_precios_mes
  for each row execute function public.compras_panol_precios_mes_cierre_guard();

commit;
