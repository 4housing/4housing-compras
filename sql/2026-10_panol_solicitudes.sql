-- =====================================================================
-- Pañol · solicitudes de OT (oct 2026)
-- Proyecto Supabase: wcpkpwxhqdcdljfwzcmy. Correr A MANO en el SQL Editor,
-- ANTES de publicar el index.html que usa estas tablas.
--
-- Qué hace (aditivo):
--   1) compras_panol_solicitudes: una fila por solicitud de OT (un archivo Excel = una OT): N° de OT, solicitante, destino, fecha de necesidad,
--      estado (Pendiente / En preparación / Parcial / Entregada / Anulada).
--   2) compras_panol_solicitud_items: los materiales pedidos (artículo, cantidad, U.M., fecha de necesidad, comentario), cuánto se entregó y cuánto se anuló.
--      La solicitud guarda también si Pañol la bloqueó (ya no se puede editar) y su historial (quién, qué y cuándo).
--   3) compras_panol_egresos: columnas ot y solicitud_id, para saber de qué OT salió cada egreso cuando Pañol entrega.
-- RLS: solo authenticated con public.tiene_sector('compras'::public.sector_portal). Nada para anon.
--   OJO: quién puede preparar / entregar / anular (Pañol) y que cada solicitante vea solo lo suyo se controla en la app, no en la base:
--   cualquier usuario con el sector compras podría leer o escribir estas tablas por API. Si hace falta, se endurece después.
--
-- Reversible:
--   alter table public.compras_panol_egresos drop column ot, drop column solicitud_id;
--   drop table public.compras_panol_solicitud_items; drop table public.compras_panol_solicitudes;
-- =====================================================================
begin;

create table if not exists public.compras_panol_solicitudes (
  id                 bigint generated always as identity primary key,
  nro_ot             text not null,
  solicitante        text,                       -- nombre que figura en el Excel
  solicitante_email  text,                       -- usuario que la subió
  destino_cod        text,                       -- código de clasificación (ej. PL0090); null si no se pudo resolver
  destino_txt        text,                       -- destino tal como figura en el Excel
  fecha_necesidad    date,
  comentario         text,
  estado             text not null default 'Pendiente' check (estado in ('Pendiente','En preparación','Parcial','Entregada','Anulada')),
  creado_en          timestamptz not null default now(),
  actualizado_en     timestamptz,
  actualizado_por    text,
  bloqueada          boolean not null default false,   -- Pañol definió que ya no se puede editar
  bloqueada_por      text,
  bloqueada_en       timestamptz,
  historial          jsonb not null default '[]'::jsonb  -- [{accion, detalle, por, fecha}]
);
create index if not exists compras_panol_solicitudes_estado_idx on public.compras_panol_solicitudes (estado, fecha_necesidad);

create table if not exists public.compras_panol_solicitud_items (
  id                  bigint generated always as identity primary key,
  solicitud_id        bigint not null references public.compras_panol_solicitudes(id) on delete cascade,
  cod_articulo        text,                      -- null si el artículo no está dado de alta
  articulo_libre      text,                      -- texto pedido cuando no hay código
  cantidad            numeric not null check (cantidad > 0),
  um                  text,
  fecha_necesidad     date,
  comentario          text,
  cantidad_entregada  numeric not null default 0,
  cantidad_anulada    numeric not null default 0,     -- unidades anuladas o cerradas: vigente = cantidad - cantidad_anulada
  galpon              text                            -- dónde se entrega (HUE 610, CIR2…)
);
create index if not exists compras_panol_solicitud_items_sol_idx on public.compras_panol_solicitud_items (solicitud_id);

-- Si las tablas ya existían de una corrida anterior, se agregan las columnas nuevas (se puede volver a correr sin problema)
alter table public.compras_panol_solicitudes
  add column if not exists bloqueada     boolean not null default false,
  add column if not exists bloqueada_por text,
  add column if not exists bloqueada_en  timestamptz,
  add column if not exists historial     jsonb not null default '[]'::jsonb;
alter table public.compras_panol_solicitud_items
  add column if not exists cantidad_anulada numeric not null default 0,
  add column if not exists galpon text;

-- El N° de OT lo asigna el sistema, en el orden en que se suben (OT-00001, OT-00002…)
create or replace function public.compras_panol_solicitudes_nro_ot()
returns trigger language plpgsql as $$
begin
  if new.nro_ot is null or btrim(new.nro_ot) = '' then new.nro_ot := 'OT-' || lpad(new.id::text, 5, '0'); end if;
  return new;
end;
$$;
drop trigger if exists compras_panol_solicitudes_nro_ot on public.compras_panol_solicitudes;
create trigger compras_panol_solicitudes_nro_ot before insert on public.compras_panol_solicitudes
  for each row execute function public.compras_panol_solicitudes_nro_ot();

-- Diccionario de solicitantes (lista desplegable del Excel de solicitud); arranca con los usuarios de la app
create table if not exists public.compras_panol_solicitantes (
  id          bigint generated always as identity primary key,
  nombre      text not null,
  email       text,
  activo      boolean not null default true,
  creado_en   timestamptz not null default now(),
  creado_por  text
);
create unique index if not exists compras_panol_solicitantes_nombre_uq on public.compras_panol_solicitantes (upper(btrim(nombre)));
alter table public.compras_panol_solicitantes enable row level security;
revoke all on public.compras_panol_solicitantes from anon;
grant select, insert, update, delete on public.compras_panol_solicitantes to authenticated;
drop policy if exists compras_panol_solicitantes_all on public.compras_panol_solicitantes;
create policy compras_panol_solicitantes_all on public.compras_panol_solicitantes for all to authenticated
  using (public.tiene_sector('compras'::public.sector_portal)) with check (public.tiene_sector('compras'::public.sector_portal));
insert into public.compras_panol_solicitantes (nombre, email, creado_por)
  select distinct on (upper(btrim(u.nombre))) btrim(u.nombre), u.email, 'sql' from public.compras_usuarios_autorizados u
  where u.nombre is not null and btrim(u.nombre) <> ''
  on conflict do nothing;

alter table public.compras_panol_solicitudes      enable row level security;
alter table public.compras_panol_solicitud_items  enable row level security;
revoke all on public.compras_panol_solicitudes     from anon;
revoke all on public.compras_panol_solicitud_items from anon;
grant select, insert, update, delete on public.compras_panol_solicitudes     to authenticated;
grant select, insert, update, delete on public.compras_panol_solicitud_items to authenticated;
drop policy if exists compras_panol_solicitudes_all     on public.compras_panol_solicitudes;
drop policy if exists compras_panol_solicitud_items_all on public.compras_panol_solicitud_items;
create policy compras_panol_solicitudes_all on public.compras_panol_solicitudes for all to authenticated
  using (public.tiene_sector('compras'::public.sector_portal)) with check (public.tiene_sector('compras'::public.sector_portal));
create policy compras_panol_solicitud_items_all on public.compras_panol_solicitud_items for all to authenticated
  using (public.tiene_sector('compras'::public.sector_portal)) with check (public.tiene_sector('compras'::public.sector_portal));

alter table public.compras_panol_egresos
  add column if not exists ot           text,
  add column if not exists solicitud_id bigint;

commit;
