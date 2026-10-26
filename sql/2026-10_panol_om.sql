-- =====================================================================
-- Abastecimiento · Órdenes de Mantenimiento (OM) de herramientas (oct 2026)
-- Proyecto Supabase: wcpkpwxhqdcdljfwzcmy. Correr A MANO en el SQL Editor,
-- DESPUÉS de sql/2026-10_panol_herramientas.sql y sql/2026-10_panol_herramientas_ot.sql, y ANTES de publicar el index.html que usa estas tablas.
--
-- Qué hace (aditivo):
--   1) compras_panol_om_motivos: motivos de envío a reparación (desplegable; se administra en Diccionario). Precargados:
--      Mantenimiento preventivo, Mantenimiento correctivo, Falla técnica, Otros.
--   2) compras_panol_om: cada envío de una herramienta a mantenimiento genera una OM con su número (OM-0001, OM-0002…). Guarda motivo, observaciones,
--      fecha de necesidad (opcional), tipo de servicio, proveedor elegido, fecha de regreso estimada y real, costo final (ARS / USD), N° de OC/OG y el historial.
--   3) compras_panol_om_cotizaciones: las cotizaciones pedidas para cada OM (proveedor, importe, moneda, fecha, plazo); una se marca como elegida.
--   4) compras_panol_herr.om_id y nro_om: vinculan la herramienta en mantenimiento con su OM.
--   5) Los envíos a mantenimiento que ya existen reciben su OM (estado Abierta, motivo Otros, la observación anterior queda en observaciones).
-- RLS: solo authenticated con public.tiene_sector('compras'::public.sector_portal). Nada para anon.
--   OJO: quién abre, cotiza y cierra una OM (es_panol o administrador) se controla en la app.
--
-- Reversible:
--   alter table public.compras_panol_herr drop column om_id, drop column nro_om;
--   drop table public.compras_panol_om_cotizaciones; drop table public.compras_panol_om; drop table public.compras_panol_om_motivos;
-- =====================================================================
begin;

create table if not exists public.compras_panol_om_motivos (
  id         bigint generated always as identity primary key,
  nombre     text not null,
  activo     boolean not null default true,
  creado_en  timestamptz not null default now(),
  creado_por text
);
create unique index if not exists compras_panol_om_motivos_nombre_uq on public.compras_panol_om_motivos (upper(btrim(nombre)));
insert into public.compras_panol_om_motivos (nombre) values ('Mantenimiento preventivo'),('Mantenimiento correctivo'),('Falla técnica'),('Otros')
on conflict do nothing;

create table if not exists public.compras_panol_om (
  id                       bigint generated always as identity primary key,
  nro_om                   text not null,
  cod_articulo             text not null,                 -- GCHRR…
  serie                    text,                          -- la unidad que se envía
  herr_id                  bigint,                        -- renglón en compras_panol_herr (la herramienta en mantenimiento)
  fecha_envio              date not null,
  fecha_necesidad          date,                          -- si se necesita volver a contar con la herramienta en una fecha
  motivo                   text,
  observaciones            text,
  estado                   text not null default 'Abierta' check (estado in ('Abierta','En cotización','En reparación','Cerrada','Anulada')),
  tipo_servicio            text,                          -- qué servicio requiere (lo define quien abre la OM)
  proveedor                text,                          -- el de la cotización elegida
  fecha_regreso_estimada   date,                          -- la que informa quien hace el servicio
  fecha_regreso            date,                          -- real, al cerrar
  costo_ars                numeric,
  costo_usd                numeric,
  nro_oc                   text,                          -- OC / OG de la reparación
  observaciones_cierre     text,
  historial                jsonb not null default '[]'::jsonb,
  creado_en                timestamptz not null default now(),
  creado_por               text,
  actualizado_en           timestamptz,
  actualizado_por          text,
  cerrado_en               timestamptz
);
create index if not exists compras_panol_om_art_idx   on public.compras_panol_om (cod_articulo, serie);
create index if not exists compras_panol_om_estado_idx on public.compras_panol_om (estado);

create or replace function public.compras_panol_om_nro()
returns trigger language plpgsql as $$
begin
  if new.nro_om is null or btrim(new.nro_om) = '' then new.nro_om := 'OM-' || lpad(new.id::text, 4, '0'); end if;
  return new;
end; $$;
drop trigger if exists compras_panol_om_nro on public.compras_panol_om;
create trigger compras_panol_om_nro before insert on public.compras_panol_om
  for each row execute function public.compras_panol_om_nro();

create table if not exists public.compras_panol_om_cotizaciones (
  id          bigint generated always as identity primary key,
  om_id       bigint not null references public.compras_panol_om(id) on delete cascade,
  proveedor   text not null,
  importe     numeric,
  moneda      text not null default 'ARS' check (moneda in ('ARS','USD')),
  fecha       date,
  plazo_dias  integer,
  comentario  text,
  elegida     boolean not null default false,
  creado_en   timestamptz not null default now(),
  creado_por  text
);
create index if not exists compras_panol_om_cot_om_idx on public.compras_panol_om_cotizaciones (om_id);

alter table public.compras_panol_herr
  add column if not exists om_id bigint references public.compras_panol_om(id) on delete set null,
  add column if not exists nro_om text;

alter table public.compras_panol_om_motivos       enable row level security;
alter table public.compras_panol_om               enable row level security;
alter table public.compras_panol_om_cotizaciones  enable row level security;
revoke all on public.compras_panol_om_motivos      from anon;
revoke all on public.compras_panol_om              from anon;
revoke all on public.compras_panol_om_cotizaciones from anon;
grant select, insert, update, delete on public.compras_panol_om_motivos      to authenticated;
grant select, insert, update, delete on public.compras_panol_om              to authenticated;
grant select, insert, update, delete on public.compras_panol_om_cotizaciones to authenticated;
drop policy if exists compras_panol_om_motivos_all on public.compras_panol_om_motivos;
drop policy if exists compras_panol_om_all         on public.compras_panol_om;
drop policy if exists compras_panol_om_cot_all     on public.compras_panol_om_cotizaciones;
create policy compras_panol_om_motivos_all on public.compras_panol_om_motivos for all to authenticated
  using (public.tiene_sector('compras'::public.sector_portal)) with check (public.tiene_sector('compras'::public.sector_portal));
create policy compras_panol_om_all on public.compras_panol_om for all to authenticated
  using (public.tiene_sector('compras'::public.sector_portal)) with check (public.tiene_sector('compras'::public.sector_portal));
create policy compras_panol_om_cot_all on public.compras_panol_om_cotizaciones for all to authenticated
  using (public.tiene_sector('compras'::public.sector_portal)) with check (public.tiene_sector('compras'::public.sector_portal));

-- Los envíos a mantenimiento que ya existen reciben su OM
do $$
declare r record; v_id bigint; v_nro text; v_n int := 0;
begin
  for r in select id, cod_articulo, serie, desde, comentario, creado_por, creado_en
             from public.compras_panol_herr where estado = 'Mantenimiento' and om_id is null order by id
  loop
    insert into public.compras_panol_om (nro_om, cod_articulo, serie, herr_id, fecha_envio, motivo, observaciones, estado, creado_en, creado_por, historial)
    values ('', r.cod_articulo, r.serie, r.id, r.desde, 'Otros', r.comentario, 'Abierta', r.creado_en, r.creado_por,
            jsonb_build_array(jsonb_build_object('accion','Creada','detalle','OM asignada a un envío a mantenimiento anterior a las OM','por','migración','fecha', now())))
    returning id, nro_om into v_id, v_nro;
    update public.compras_panol_herr set om_id = v_id, nro_om = v_nro where id = r.id;
    v_n := v_n + 1;
  end loop;
  raise notice 'OM creadas para envíos anteriores: %', v_n;
end $$;

commit;

-- Verificación
select m.nombre as motivo, m.activo from public.compras_panol_om_motivos m order by m.id;
select nro_om, cod_articulo, serie, fecha_envio, estado, motivo from public.compras_panol_om order by id;
select estado, count(*) filter (where om_id is null) as sin_om from public.compras_panol_herr where estado = 'Mantenimiento' group by estado;
