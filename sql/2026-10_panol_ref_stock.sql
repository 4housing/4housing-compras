-- =====================================================================
-- Pañol · referencia de "stock completo" para conciliar el mes (oct 2026)
-- Proyecto Supabase: wcpkpwxhqdcdljfwzcmy. Correr A MANO en el SQL Editor,
-- ANTES de publicar el index.html que usa esta tabla.
--
-- Qué hace (aditivo): crea compras_panol_ref_stock, donde la app guarda las líneas de la hoja MOVIMIENTO STOCK COMPLETO del Excel de
-- valorización (una carga por período; al volver a cargar el mismo período se reemplaza). Sirve solo para comparar contra las erogaciones:
-- no modifica ninguna erogación ni ningún precio.
-- RLS: solo authenticated con public.tiene_sector('compras'::public.sector_portal). Nada para anon.
--
-- Reversible: drop table public.compras_panol_ref_stock;
-- =====================================================================
begin;

create table if not exists public.compras_panol_ref_stock (
  id           bigint generated always as identity primary key,
  periodo      integer not null,            -- aaaamm
  destino_cod  text,                        -- código de clasificación ya resuelto (ej. PL0090); null si no se pudo resolver
  if_txt       text,                        -- IF tal como figura en el Excel
  cod_articulo text,                        -- código Tango resuelto; null si no se reconoció
  articulo     text not null,
  um           text,
  cantidad     numeric not null default 0,
  precio_ars   numeric,
  total_ars    numeric,
  precio_usd   numeric,
  total_usd    numeric,
  observacion  text,
  cargado_por  text,
  cargado_en   timestamptz not null default now()
);
create index if not exists compras_panol_ref_stock_periodo_idx on public.compras_panol_ref_stock (periodo);

alter table public.compras_panol_ref_stock enable row level security;
revoke all on public.compras_panol_ref_stock from anon;
grant select, insert, update, delete on public.compras_panol_ref_stock to authenticated;
drop policy if exists compras_panol_ref_stock_all on public.compras_panol_ref_stock;
create policy compras_panol_ref_stock_all on public.compras_panol_ref_stock for all to authenticated
  using (public.tiene_sector('compras'::public.sector_portal)) with check (public.tiene_sector('compras'::public.sector_portal));

commit;
