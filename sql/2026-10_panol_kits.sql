-- =====================================================================
-- Pañol · Modelos de Kits (solicitud de OT según tarea) y permiso de Pañol (oct 2026)
-- Proyecto Supabase: wcpkpwxhqdcdljfwzcmy. Correr A MANO en el SQL Editor,
-- DESPUÉS de sql/2026-10_panol_solicitudes.sql y ANTES de publicar el index.html que usa estas tablas.
--
-- Qué hace (aditivo):
--   1) compras_panol_kits y compras_panol_kit_items: cada modelo es una tarea (1 módulo, 1 bastidor de piso…) con sus materiales y la cantidad
--      estimada PARA UNA unidad de la tarea.
--   2) compras_panol_solicitudes: columnas kit_id y kit_cantidad (de qué modelo salió y cuántas unidades) y creado_por (quién la cargó).
--   3) compras_usuarios_autorizados.es_panol: permiso de Pañol (preparar y entregar solicitudes, bloquearlas, administrar los modelos y
--      elegir "a nombre de quién" se pide). Lo tienen estos usuarios y el administrador. Se asigna con el UPDATE comentado al final.
-- RLS: solo authenticated con public.tiene_sector('compras'::public.sector_portal). Nada para anon.
--   OJO: quién administra los modelos y el permiso de Pañol se controlan en la app; cualquier usuario con el sector compras podría escribir
--   estas tablas por API.
--
-- Reversible:
--   alter table public.compras_panol_solicitudes drop column kit_id, drop column kit_cantidad, drop column creado_por;
--   alter table public.compras_usuarios_autorizados drop column es_panol;
--   drop table public.compras_panol_kit_items; drop table public.compras_panol_kits;
-- =====================================================================
begin;

create table if not exists public.compras_panol_kits (
  id              bigint generated always as identity primary key,
  nombre          text not null,              -- la tarea
  unidad          text,                       -- unidad de trabajo: módulo, bastidor de piso, bastidor de muro…
  comentario      text,
  activo          boolean not null default true,
  creado_en       timestamptz not null default now(),
  creado_por      text,
  actualizado_en  timestamptz,
  actualizado_por text
);
create unique index if not exists compras_panol_kits_nombre_uq on public.compras_panol_kits (upper(btrim(nombre)));

create table if not exists public.compras_panol_kit_items (
  id             bigint generated always as identity primary key,
  kit_id         bigint not null references public.compras_panol_kits(id) on delete cascade,
  cod_articulo   text,
  articulo_libre text,
  cantidad       numeric not null check (cantidad > 0),   -- por UNA unidad de la tarea
  um             text,
  comentario     text
);
create index if not exists compras_panol_kit_items_kit_idx on public.compras_panol_kit_items (kit_id);

alter table public.compras_panol_kits      enable row level security;
alter table public.compras_panol_kit_items enable row level security;
revoke all on public.compras_panol_kits      from anon;
revoke all on public.compras_panol_kit_items from anon;
grant select, insert, update, delete on public.compras_panol_kits      to authenticated;
grant select, insert, update, delete on public.compras_panol_kit_items to authenticated;
drop policy if exists compras_panol_kits_all      on public.compras_panol_kits;
drop policy if exists compras_panol_kit_items_all on public.compras_panol_kit_items;
create policy compras_panol_kits_all on public.compras_panol_kits for all to authenticated
  using (public.tiene_sector('compras'::public.sector_portal)) with check (public.tiene_sector('compras'::public.sector_portal));
create policy compras_panol_kit_items_all on public.compras_panol_kit_items for all to authenticated
  using (public.tiene_sector('compras'::public.sector_portal)) with check (public.tiene_sector('compras'::public.sector_portal));

alter table public.compras_panol_solicitudes
  add column if not exists kit_id       bigint,
  add column if not exists kit_cantidad numeric,
  add column if not exists creado_por   text;

alter table public.compras_usuarios_autorizados
  add column if not exists es_panol boolean not null default false;

commit;

-- ---------------------------------------------------------------------
-- Dar el permiso de Pañol (correr APARTE, después de verificar los nombres):
--   1) Mirá quiénes son:  select nombre, email, es_panol from public.compras_usuarios_autorizados where nombre ilike '%komina%';
--   2) Si son los que corresponden:
--      update public.compras_usuarios_autorizados set es_panol = true where nombre ilike '%komina%';
--   (Si Iván o Nicolás no figuran en esa tabla, primero hay que darlos de alta como usuarios autorizados de la app.)
-- ---------------------------------------------------------------------
