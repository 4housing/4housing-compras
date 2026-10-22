-- =====================================================================
-- Pañol · mini diccionario (galpones y operarios) (oct 2026)
-- Proyecto Supabase: wcpkpwxhqdcdljfwzcmy. Correr A MANO en el SQL Editor,
-- ANTES de publicar el index.html que usa estas tablas.
--
-- Qué hace (todo aditivo):
--   1) compras_panol_galpones  : galpones del pañol. Arranca con LA HUELLA 610 y CIR2.
--   2) compras_panol_operarios : operarios (puesto, nombre, nombre de pila). Se carga desde la app
--      (a mano o importando la hoja "NOMBRE OPERARIOS" del Excel de erogaciones). NO se siembra acá:
--      son datos de personas y este repo es público.
--   La app deja eliminar solo lo que nunca se usó en una erogación; lo usado solo se inhabilita.
--   RLS: solo authenticated con public.tiene_sector('compras'::public.sector_portal). Nada para anon.
--
-- Reversible:
--   drop table public.compras_panol_galpones; drop table public.compras_panol_operarios;
-- =====================================================================

begin;

create table if not exists public.compras_panol_galpones (
  id          bigint generated always as identity primary key,
  nombre      text not null,
  activo      boolean not null default true,
  creado_en   timestamptz not null default now(),
  creado_por  text
);
create unique index if not exists compras_panol_galpones_nombre_uq on public.compras_panol_galpones (upper(btrim(nombre)));

create table if not exists public.compras_panol_operarios (
  id           bigint generated always as identity primary key,
  nombre       text not null,        -- columna NOMBRE del Excel (apellido): es el valor que se guarda en la erogación
  nombre_pila  text,                 -- columna EXCEL del Excel
  puesto       text,                 -- ADMIN / OPERARIO / CONTRATISTA / LIMPIEZA / OFICINA / (vacío)
  activo       boolean not null default true,
  creado_en    timestamptz not null default now(),
  creado_por   text
);
create unique index if not exists compras_panol_operarios_nombre_uq on public.compras_panol_operarios (upper(btrim(nombre)));

insert into public.compras_panol_galpones (nombre, creado_por) values ('LA HUELLA 610', 'sql'), ('CIR2', 'sql')
on conflict do nothing;

-- RLS: sector compras, solo authenticated
alter table public.compras_panol_galpones  enable row level security;
alter table public.compras_panol_operarios enable row level security;
revoke all on public.compras_panol_galpones  from anon;
revoke all on public.compras_panol_operarios from anon;
grant select, insert, update, delete on public.compras_panol_galpones  to authenticated;
grant select, insert, update, delete on public.compras_panol_operarios to authenticated;

drop policy if exists compras_panol_galpones_all  on public.compras_panol_galpones;
drop policy if exists compras_panol_operarios_all on public.compras_panol_operarios;
create policy compras_panol_galpones_all on public.compras_panol_galpones for all to authenticated
  using (public.tiene_sector('compras'::public.sector_portal)) with check (public.tiene_sector('compras'::public.sector_portal));
create policy compras_panol_operarios_all on public.compras_panol_operarios for all to authenticated
  using (public.tiene_sector('compras'::public.sector_portal)) with check (public.tiene_sector('compras'::public.sector_portal));

commit;
