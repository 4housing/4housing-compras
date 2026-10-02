-- =====================================================================
-- Solicitudes de pago: Pendientes de facturar + Pagos a realizar (oct 2026)
-- Proyecto Supabase: wcpkpwxhqdcdljfwzcmy. Correr A MANO en el SQL Editor,
-- ANTES de publicar el index.html que usa estas tablas.
--
-- Qué hace:
--   1) Crea compras_pend_facturar   (foto del reporte de Tango "Pendientes de facturar").
--   2) Crea compras_pagos_realizar  (foto del reporte de Tango "Pagos a realizar").
--      Cada importación desde la app borra todo y vuelve a insertar (igual que compras_oc_informe).
--      RLS: solo authenticated con tiene_sector('compras'). Nada para anon.
--   3) compras_solicitudes_pago:
--      - columna nueva neto_oc (lo pendiente de facturar de la OC al cargar la FAC, para marcar diferencias);
--      - estado nuevo 'FAC cargada' (FAC adjunta desde Pendientes de facturar, todavía sin pedir el pago).
--        Si la tabla tiene un CHECK sobre estado, se reemplaza por uno que incluye el valor nuevo.
--
-- Reversible:
--   drop table public.compras_pend_facturar; drop table public.compras_pagos_realizar;
--   alter table public.compras_solicitudes_pago drop column neto_oc;
--   (y, si se había reemplazado, volver a crear el CHECK de estado original que muestra el paso 0)
-- =====================================================================

-- 0) (opcional, mirar antes) CHECKs actuales de compras_solicitudes_pago
select conname, pg_get_constraintdef(oid) as definicion
from pg_constraint
where conrelid = 'public.compras_solicitudes_pago'::regclass and contype = 'c';

begin;

-- 1) Pendientes de facturar
create table if not exists public.compras_pend_facturar (
  id                      bigint generated always as identity primary key,
  talonario               integer,
  oc_numero               text,      -- N° de OC corto (sin punto de venta ni ceros), igual que compras_oc_informe
  proveedor_cod           text,
  fecha_ingreso           date,
  comprador               text,
  clasif_cod              text,      -- auxiliar (Cód. clasificación del comprobante)
  clasif_desc             text,
  cod_articulo            text,
  descripcion             text,
  cantidad_pedida         numeric,
  cantidad_pend_facturar  numeric,
  total_pedido_sin_imp    numeric,
  pend_facturar_sin_imp   numeric,
  estado                  text,
  estado_renglon          text,
  costeo                  text,
  estructura              text,
  leyendas                text,
  condicion_compra        text,
  moneda                  text,      -- 'Corriente' / 'Extranjera' (tal cual Tango)
  importado_en            timestamptz not null default now(),
  importado_por           text
);
create index if not exists compras_pend_facturar_oc_idx on public.compras_pend_facturar (proveedor_cod, oc_numero);

-- 2) Pagos a realizar
create table if not exists public.compras_pagos_realizar (
  id                  bigint generated always as identity primary key,
  fecha_emision       date,
  fecha_contable      date,
  tipo_comprobante    text,
  proveedor_cod       text,
  comprobante_numero  text,
  total_pend_cte      numeric,
  total_pend_ext      numeric,
  importado_en        timestamptz not null default now(),
  importado_por       text
);
create index if not exists compras_pagos_realizar_comp_idx on public.compras_pagos_realizar (proveedor_cod, comprobante_numero);

-- RLS: sector compras, solo authenticated
alter table public.compras_pend_facturar  enable row level security;
alter table public.compras_pagos_realizar enable row level security;
revoke all on public.compras_pend_facturar  from anon;
revoke all on public.compras_pagos_realizar from anon;
grant select, insert, delete on public.compras_pend_facturar  to authenticated;
grant select, insert, delete on public.compras_pagos_realizar to authenticated;

drop policy if exists compras_pend_facturar_sel on public.compras_pend_facturar;
drop policy if exists compras_pend_facturar_ins on public.compras_pend_facturar;
drop policy if exists compras_pend_facturar_del on public.compras_pend_facturar;
create policy compras_pend_facturar_sel on public.compras_pend_facturar for select to authenticated using (tiene_sector('compras'));
create policy compras_pend_facturar_ins on public.compras_pend_facturar for insert to authenticated with check (tiene_sector('compras'));
create policy compras_pend_facturar_del on public.compras_pend_facturar for delete to authenticated using (tiene_sector('compras'));

drop policy if exists compras_pagos_realizar_sel on public.compras_pagos_realizar;
drop policy if exists compras_pagos_realizar_ins on public.compras_pagos_realizar;
drop policy if exists compras_pagos_realizar_del on public.compras_pagos_realizar;
create policy compras_pagos_realizar_sel on public.compras_pagos_realizar for select to authenticated using (tiene_sector('compras'));
create policy compras_pagos_realizar_ins on public.compras_pagos_realizar for insert to authenticated with check (tiene_sector('compras'));
create policy compras_pagos_realizar_del on public.compras_pagos_realizar for delete to authenticated using (tiene_sector('compras'));

-- 3) compras_solicitudes_pago: neto_oc + estado 'FAC cargada'
alter table public.compras_solicitudes_pago add column if not exists neto_oc numeric;

do $$
declare c record; habia boolean := false;
begin
  for c in
    select conname from pg_constraint
    where conrelid = 'public.compras_solicitudes_pago'::regclass and contype = 'c'
      and pg_get_constraintdef(oid) ilike '%estado%'
  loop
    execute format('alter table public.compras_solicitudes_pago drop constraint %I', c.conname);
    raise notice 'Se quitó el CHECK % (estado)', c.conname;
    habia := true;
  end loop;
  if habia then
    alter table public.compras_solicitudes_pago add constraint compras_solicitudes_pago_estado_chk
      check (estado in ('FAC cargada','Pendiente','En gestión','Pagada'));
    raise notice 'CHECK de estado recreado con FAC cargada';
  else
    raise notice 'No había CHECK sobre estado: no hace falta tocar nada';
  end if;
end $$;

commit;

-- 4) Verificación
select tablename, policyname, roles, cmd from pg_policies
where tablename in ('compras_pend_facturar','compras_pagos_realizar') order by 1,2;
