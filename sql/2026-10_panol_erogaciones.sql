-- =====================================================================
-- Pañol · solapa Erogaciones (oct 2026)
-- Proyecto Supabase: wcpkpwxhqdcdljfwzcmy. Correr A MANO en el SQL Editor,
-- ANTES de publicar el index.html que usa estas columnas/tabla.
--
-- Qué hace (todo aditivo, no toca datos existentes):
--   1) compras_panol_egresos: columnas nuevas para registrar la erogación como en el Excel
--      EROGACIONES (serie/módulo, galpón, proceso, SOLP, horario) + trazabilidad del precio
--      (fuente, fecha de referencia, proveedor, OC, desvíos) + alerta.
--      cod_articulo y cod_deposito pasan a admitir NULL: si el artículo todavía no está dado
--      de alta en Tango, el pañol lo carga con nombre libre (articulo_libre) y queda con
--      alerta 'ARTICULO SIN ALTA' hasta que se cree como corresponde.
--   2) compras_hist_precios: historial de precios de compra por artículo (sale del informe de Tango
--      "Informe APP Costeos"). La app lo reemplaza entero en cada importación (igual que
--      compras_oc_informe) y de ahí toma el último precio con fecha <= fin de mes.
--      RLS: solo authenticated con public.tiene_sector('compras'::public.sector_portal). Nada para anon.
--
-- Reversible:
--   drop table public.compras_hist_precios;
--   alter table public.compras_panol_egresos
--     drop column serie, drop column galpon, drop column proceso, drop column solp, drop column horario,
--     drop column articulo_libre, drop column alerta, drop column fuente_precio, drop column precio_fecha_ref,
--     drop column precio_proveedor, drop column precio_oc, drop column desvio_tc, drop column var_tango;
--   (los NOT NULL de cod_articulo/cod_deposito no se vuelven a poner solos: si hay filas con NULL, corregirlas antes)
-- =====================================================================

begin;

-- 1) Columnas nuevas en los egresos de pañol
alter table public.compras_panol_egresos
  add column if not exists serie            text,     -- módulo / contenedor (serie). 'GENERICO MODULO' si el destino lo pide y no se indicó
  add column if not exists galpon           text,
  add column if not exists proceso          text,     -- HABITUAL / RE TRABAJO / DESVIO
  add column if not exists solp             text,
  add column if not exists horario          text,     -- hora de entrega (HH:MM)
  add column if not exists articulo_libre   text,     -- nombre del artículo no dado de alta todavía
  add column if not exists alerta           text,     -- códigos separados por coma: SIN PRECIO, FECHA POSTERIOR AL MES, REVISAR vs TANGO, REVISAR TC, ARTICULO SIN ALTA
  add column if not exists fuente_precio    text,     -- 'OC' / 'Tango' / 'Manual'
  add column if not exists precio_fecha_ref date,
  add column if not exists precio_proveedor text,
  add column if not exists precio_oc        text,
  add column if not exists desvio_tc        numeric,  -- TC implícito (ARS/USD) vs dólar oficial BNA venta, fracción (0.05 = 5%)
  add column if not exists var_tango        numeric;  -- precio de OC vs último costo Tango, fracción

alter table public.compras_panol_egresos alter column cod_articulo drop not null;
alter table public.compras_panol_egresos alter column cod_deposito drop not null;

-- 2) Historial de precios de compra
create table if not exists public.compras_hist_precios (
  id            bigint generated always as identity primary key,
  cod_articulo  text not null,
  fecha         date not null,           -- fecha de emisión de la OC
  proveedor     text,
  nro_oc        text,
  cantidad      numeric,
  precio_ars    numeric not null,        -- Total / cantidad pedida
  precio_usd    numeric,                 -- precio_ars / cotización de la OC
  tc            numeric,                 -- cotización de la OC
  estado        text,                    -- estado del renglón en Tango
  importado_en  timestamptz not null default now(),
  importado_por text
);
create index if not exists compras_hist_precios_art_idx on public.compras_hist_precios (cod_articulo, fecha);

alter table public.compras_hist_precios enable row level security;
revoke all on public.compras_hist_precios from anon;
grant select, insert, delete on public.compras_hist_precios to authenticated;

drop policy if exists compras_hist_precios_sel on public.compras_hist_precios;
drop policy if exists compras_hist_precios_ins on public.compras_hist_precios;
drop policy if exists compras_hist_precios_del on public.compras_hist_precios;
create policy compras_hist_precios_sel on public.compras_hist_precios for select to authenticated using (public.tiene_sector('compras'::public.sector_portal));
create policy compras_hist_precios_ins on public.compras_hist_precios for insert to authenticated with check (public.tiene_sector('compras'::public.sector_portal));
create policy compras_hist_precios_del on public.compras_hist_precios for delete to authenticated using (public.tiene_sector('compras'::public.sector_portal));

commit;
