-- =====================================================================
-- Abastecimiento (ex Pañol): sector y responsable por renglón (oct 2026)
-- Proyecto Supabase: wcpkpwxhqdcdljfwzcmy. Correr A MANO en el SQL Editor,
-- DESPUÉS de sql/2026-10_panol_solicitudes.sql y sql/2026-10_panol_kits.sql, y ANTES de publicar el index.html que usa estas columnas.
--
-- Qué hace (aditivo):
--   1) compras_panol_solicitud_items.sector: 'Pañol' o 'Depósito'. La app lo sugiere por el código del artículo:
--      GCFER, GCLIM, GCEPP, GCEQU, GCHRR o GCSPM => Pañol; cualquier otro => Depósito (sin código => Pañol). Los renglones que ya existen se completan igual.
--   2) compras_panol_responsables: las personas que arman lo solicitado, y de qué sector son el responsable por defecto
--      (Garay, Ivan => Pañol; Rivero, Nicolas => Depósito). Se cargan por nombre desde compras_usuarios_autorizados (de ahí sale el mail con el que entran).
--   3) compras_panol_solicitud_items.responsable_nombre / responsable_email: quién arma y entrega ese renglón. Se completa por sector al crear la OT
--      y se puede transferir a otro responsable (un renglón, varios o la OT completa). Los renglones que ya existen quedan con el responsable de su sector.
-- RLS: la tabla nueva queda con la compuerta de sector compras (como las demás). Quién puede entregar o transferir se controla en la app.
--
-- Reversible:
--   alter table public.compras_panol_solicitud_items drop column sector, drop column responsable_nombre, drop column responsable_email;
--   drop table public.compras_panol_responsables;
-- =====================================================================
begin;

alter table public.compras_panol_solicitud_items
  add column if not exists sector text check (sector in ('Pañol','Depósito')),
  add column if not exists responsable_nombre text,
  add column if not exists responsable_email text;

create table if not exists public.compras_panol_responsables (
  id              bigint generated always as identity primary key,
  nombre          text not null,
  email           text not null,
  sector_defecto  text check (sector_defecto in ('Pañol','Depósito')),   -- null = puede recibir renglones por transferencia pero no es el de ningún sector
  activo          boolean not null default true,
  creado_en       timestamptz not null default now()
);
create unique index if not exists compras_panol_responsables_email_uq on public.compras_panol_responsables (lower(email));
create unique index if not exists compras_panol_responsables_sector_uq on public.compras_panol_responsables (sector_defecto) where sector_defecto is not null and activo;

alter table public.compras_panol_responsables enable row level security;
revoke all on public.compras_panol_responsables from anon;
grant select, insert, update, delete on public.compras_panol_responsables to authenticated;
drop policy if exists compras_panol_responsables_all on public.compras_panol_responsables;
create policy compras_panol_responsables_all on public.compras_panol_responsables for all to authenticated
  using (public.tiene_sector('compras'::public.sector_portal)) with check (public.tiene_sector('compras'::public.sector_portal));

-- Carga de los dos responsables por nombre (toma el mail de usuarios autorizados). Si algún nombre no existe ahí, no inserta nada: ver el select final.
insert into public.compras_panol_responsables (nombre, email, sector_defecto)
select u.nombre, u.email, 'Pañol' from public.compras_usuarios_autorizados u
 where u.nombre ilike 'Garay, Ivan%' and u.email is not null
on conflict do nothing;
insert into public.compras_panol_responsables (nombre, email, sector_defecto)
select u.nombre, u.email, 'Depósito' from public.compras_usuarios_autorizados u
 where u.nombre ilike 'Rivero, Nicolas%' and u.email is not null
on conflict do nothing;

-- Sector de los renglones que ya existen
update public.compras_panol_solicitud_items
   set sector = case
                  when cod_articulo is null or btrim(cod_articulo) = '' then 'Pañol'
                  when upper(left(btrim(cod_articulo), 5)) in ('GCFER','GCLIM','GCEPP','GCEQU','GCHRR','GCSPM') then 'Pañol'
                  else 'Depósito'
                end
 where sector is null;

-- Responsable de los renglones que ya existen: el de su sector (solo los que todavía tienen algo pendiente)
update public.compras_panol_solicitud_items i
   set responsable_nombre = r.nombre, responsable_email = r.email
  from public.compras_panol_responsables r
 where r.sector_defecto = i.sector and r.activo
   and i.responsable_email is null
   and coalesce(i.cantidad,0) - coalesce(i.cantidad_anulada,0) - coalesce(i.cantidad_entregada,0) > 0;

commit;

-- Verificar que quedaron los dos responsables (si falta alguno, el nombre no coincide con compras_usuarios_autorizados: avisame el nombre exacto):
select sector_defecto, nombre, email, activo from public.compras_panol_responsables order by sector_defecto;
