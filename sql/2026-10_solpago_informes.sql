-- =====================================================================
-- Solicitudes de pago: Pendientes de facturar + Pagos a realizar + espejo en Administración (oct 2026)
-- Proyecto Supabase: wcpkpwxhqdcdljfwzcmy. Correr A MANO en el SQL Editor,
-- ANTES de publicar el index.html que usa estas tablas.
--
-- Qué hace:
--   1) Crea compras_pend_facturar   (foto del reporte de Tango "Pendientes de facturar").
--   2) Crea compras_pagos_realizar  (foto del reporte de Tango "Pagos a realizar").
--      Cada importación desde la app borra todo y vuelve a insertar (igual que compras_oc_informe).
--      RLS: solo authenticated con public.tiene_sector('compras'::public.sector_portal). Nada para anon.
--      Pagos a realizar lo importa SOLO Administración y Finanzas (sector adminfin), con la función
--      compras_pagos_realizar_importar(); Compras lo lee.
--   3) compras_solicitudes_pago:
--      - columnas nuevas: neto_oc, leido_en, leido_por, fecha_pago_estimada, fecha_pago, pagos_realizar_visto_en;
--      - estado nuevo 'FAC cargada' (FAC adjunta desde Pendientes de facturar, todavía sin pedir el pago).
--        En wcpk la tabla NO tiene CHECK sobre estado (portal/sql/compras/110_esquema_compras.sql), así que
--        no hay nada que cambiar; el bloque del paso 3 lo verifica igual por las dudas.
--   4) Espejo en Administración y Finanzas (app 4housing-adminfin, sector adminfin):
--      - adminfin LEE compras_solicitudes_pago, compras_pagos_realizar y los PDF del bucket facturas;
--      - adminfin NO escribe directo en las tablas: confirma lectura, informa fecha estimada de pago y
--        comenta solo a través de compras_solpago_adminfin() (función que toca únicamente esos campos);
--      - al importar Pagos a realizar, la solicitud cuya factura estaba en el informe anterior y ya no
--        está pasa a 'Pagada' (no se borra). Una factura que todavía nunca apareció no se toca.
--      Escritura: puede_editar_sector('adminfin') → los cargos lector/lectura solo ven.
--
-- Reversible:
--   drop table public.compras_pend_facturar; drop table public.compras_pagos_realizar;
--   alter table public.compras_solicitudes_pago drop column neto_oc, drop column leido_en, drop column leido_por,
--     drop column fecha_pago_estimada, drop column fecha_pago, drop column pagos_realizar_visto_en;
--   drop function public.compras_solpago_adminfin(bigint,text,date,text);
--   drop function public.compras_pagos_realizar_importar(jsonb);
--   drop policy compras_solpago_adminfin_sel on public.compras_solicitudes_pago;
--   drop policy adminfin_facturas_sel on storage.objects;
--
-- Requisito: el sector 'adminfin' ya existe en el enum (portal/sql/090_sector_adminfin_rrhh.sql).
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
grant select on public.compras_pagos_realizar to authenticated;   -- se escribe solo con compras_pagos_realizar_importar()

drop policy if exists compras_pend_facturar_sel on public.compras_pend_facturar;
drop policy if exists compras_pend_facturar_ins on public.compras_pend_facturar;
drop policy if exists compras_pend_facturar_del on public.compras_pend_facturar;
create policy compras_pend_facturar_sel on public.compras_pend_facturar for select to authenticated using (public.tiene_sector('compras'::public.sector_portal));
create policy compras_pend_facturar_ins on public.compras_pend_facturar for insert to authenticated with check (public.tiene_sector('compras'::public.sector_portal));
create policy compras_pend_facturar_del on public.compras_pend_facturar for delete to authenticated using (public.tiene_sector('compras'::public.sector_portal));

drop policy if exists compras_pagos_realizar_sel on public.compras_pagos_realizar;
create policy compras_pagos_realizar_sel on public.compras_pagos_realizar for select to authenticated
  using (public.tiene_sector('compras'::public.sector_portal) or public.tiene_sector('adminfin'::public.sector_portal));

-- 3) compras_solicitudes_pago: columnas nuevas + estado 'FAC cargada'
alter table public.compras_solicitudes_pago
  add column if not exists neto_oc                 numeric,      -- pendiente de facturar de la OC al cargar la FAC
  add column if not exists leido_en                timestamptz,  -- Administración confirmó lectura
  add column if not exists leido_por               text,
  add column if not exists fecha_pago_estimada     date,         -- informada por Administración
  add column if not exists fecha_pago              date,         -- cuando pasó a Pagada por el informe
  add column if not exists pagos_realizar_visto_en timestamptz;  -- la FAC figuró en Pagos a realizar

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

-- 4) Espejo en Administración y Finanzas
-- 4.a · adminfin LEE las solicitudes (la policy compras_sector de 110 sigue igual; las policies se suman con OR)
drop policy if exists compras_solpago_adminfin_sel on public.compras_solicitudes_pago;
create policy compras_solpago_adminfin_sel on public.compras_solicitudes_pago
  for select to authenticated using (public.tiene_sector('adminfin'::public.sector_portal));

-- 4.b · adminfin LEE los PDF del bucket facturas (para la URL firmada). No sube ni borra.
drop policy if exists adminfin_facturas_sel on storage.objects;
create policy adminfin_facturas_sel on storage.objects
  for select to authenticated
  using (bucket_id = 'facturas' and public.tiene_sector('adminfin'::public.sector_portal));

-- Clave para cruzar factura ↔ informe: proveedor + N° de comprobante, sin espacios ni guiones, en mayúsculas.
create or replace function public.compras_clave_fac(p_prov text, p_nro text)
returns text language sql immutable
as $$ select upper(regexp_replace(coalesce(p_prov,''),'\s','','g')) || '|' || upper(regexp_replace(coalesce(p_nro,''),'[^A-Za-z0-9]','','g')) $$;

-- 4.c · Acciones de Administración sobre una solicitud (solo estos campos; nada de monto/OC/adjunto).
--   p_accion: 'leido'      → leido_en/por y, si estaba Pendiente, pasa a 'En gestión'
--             'fecha_pago' → fecha_pago_estimada = p_fecha (+ mensaje opcional p_texto)
--             'comentario' → agrega p_texto al historial
create or replace function public.compras_solpago_adminfin(p_id bigint, p_accion text, p_fecha date default null, p_texto text default null)
returns public.compras_solicitudes_pago
language plpgsql security definer
set search_path = public
as $$
declare
  v_autor text := coalesce((select nullif(p.email,'') from public.perfiles p where p.id = auth.uid()), auth.jwt()->>'email', '');
  v_texto text := nullif(btrim(coalesce(p_texto,'')),'');
  s public.compras_solicitudes_pago;
  v_hist jsonb;
begin
  if not public.puede_editar_sector('adminfin'::public.sector_portal) then
    raise exception 'Sin permiso de edición en Administración y Finanzas';
  end if;
  select * into s from public.compras_solicitudes_pago where id = p_id for update;
  if not found then raise exception 'No existe la solicitud %', p_id; end if;
  if s.estado = 'FAC cargada' then raise exception 'Compras todavía no pidió el pago de esta factura'; end if;

  if p_accion = 'leido' then
    v_hist := jsonb_build_object('fecha', now(), 'autor', v_autor, 'texto', 'Administración confirmó la lectura.');
    if s.estado = 'Pendiente' then v_hist := v_hist || jsonb_build_object('estado_nuevo','En gestión'); end if;
    update public.compras_solicitudes_pago
       set leido_en = coalesce(leido_en, now()), leido_por = coalesce(leido_por, v_autor),
           estado = case when estado = 'Pendiente' then 'En gestión' else estado end,
           historial = coalesce(historial,'[]'::jsonb) || jsonb_build_array(v_hist), actualizado_en = now()
     where id = p_id returning * into s;
  elsif p_accion = 'fecha_pago' then
    if p_fecha is null then raise exception 'Falta la fecha de pago'; end if;
    v_hist := jsonb_build_object('fecha', now(), 'autor', v_autor,
              'texto', 'Fecha estimada de pago: ' || to_char(p_fecha,'DD/MM/YYYY') || coalesce(' — ' || v_texto, ''));
    update public.compras_solicitudes_pago
       set fecha_pago_estimada = p_fecha,
           historial = coalesce(historial,'[]'::jsonb) || jsonb_build_array(v_hist), actualizado_en = now()
     where id = p_id returning * into s;
  elsif p_accion = 'comentario' then
    if v_texto is null then raise exception 'Falta el comentario'; end if;
    update public.compras_solicitudes_pago
       set historial = coalesce(historial,'[]'::jsonb) || jsonb_build_array(jsonb_build_object('fecha', now(), 'autor', v_autor, 'texto', v_texto)),
           actualizado_en = now()
     where id = p_id returning * into s;
  else
    raise exception 'Acción desconocida: %', p_accion;
  end if;
  return s;
end $$;
revoke all on function public.compras_solpago_adminfin(bigint,text,date,text) from public, anon;
grant execute on function public.compras_solpago_adminfin(bigint,text,date,text) to authenticated;

-- 4.d · Importar Pagos a realizar (reemplaza la foto) y marcar Pagadas las facturas que salieron del informe.
--   p_filas: array JSON con fecha_emision, fecha_contable, tipo_comprobante, proveedor_cod,
--            comprobante_numero, total_pend_cte, total_pend_ext.
--   Devuelve {filas, pagadas, vistas}. Todo en una transacción: si algo falla no queda a medias.
create or replace function public.compras_pagos_realizar_importar(p_filas jsonb)
returns jsonb
language plpgsql security definer
set search_path = public
as $$
declare
  v_autor text := coalesce((select nullif(p.email,'') from public.perfiles p where p.id = auth.uid()), auth.jwt()->>'email', '');
  v_filas int; v_pagadas int; v_vistas int;
begin
  if not public.puede_editar_sector('adminfin'::public.sector_portal) then
    raise exception 'Sin permiso de edición en Administración y Finanzas';
  end if;
  if p_filas is null or jsonb_typeof(p_filas) <> 'array' or jsonb_array_length(p_filas) = 0 then
    raise exception 'El informe viene vacío';
  end if;

  delete from public.compras_pagos_realizar where true;
  insert into public.compras_pagos_realizar
         (fecha_emision, fecha_contable, tipo_comprobante, proveedor_cod, comprobante_numero, total_pend_cte, total_pend_ext, importado_en, importado_por)
  select x.fecha_emision, x.fecha_contable, x.tipo_comprobante, x.proveedor_cod, x.comprobante_numero, x.total_pend_cte, x.total_pend_ext, now(), v_autor
    from jsonb_to_recordset(p_filas) as x(fecha_emision date, fecha_contable date, tipo_comprobante text, proveedor_cod text,
                                          comprobante_numero text, total_pend_cte numeric, total_pend_ext numeric)
   where nullif(btrim(coalesce(x.comprobante_numero,'')),'') is not null;
  get diagnostics v_filas = row_count;

  -- Estaba en el informe anterior y ya no está → Pagada (fecha_pago = hoy: es cuando se detectó, no la fecha bancaria)
  update public.compras_solicitudes_pago s
     set estado = 'Pagada', fecha_pago = current_date, actualizado_en = now(),
         historial = coalesce(s.historial,'[]'::jsonb) || jsonb_build_array(jsonb_build_object(
           'fecha', now(), 'autor', v_autor, 'estado_nuevo', 'Pagada',
           'texto', 'La factura ya no figura en Pagos a realizar (importado el ' || to_char(current_date,'DD/MM/YYYY') || '): pasa a Pagada.'))
   where s.estado <> 'Pagada'
     and s.pagos_realizar_visto_en is not null
     and not exists (select 1 from public.compras_pagos_realizar r
                      where public.compras_clave_fac(r.proveedor_cod, r.comprobante_numero) = public.compras_clave_fac(s.proveedor_cod, s.nro_factura));
  get diagnostics v_pagadas = row_count;

  -- Las que sí figuran quedan marcadas como vistas (recién desde ahí pueden pasar a Pagada en otra importación)
  update public.compras_solicitudes_pago s
     set pagos_realizar_visto_en = coalesce(s.pagos_realizar_visto_en, now())
   where s.estado <> 'Pagada'
     and exists (select 1 from public.compras_pagos_realizar r
                  where public.compras_clave_fac(r.proveedor_cod, r.comprobante_numero) = public.compras_clave_fac(s.proveedor_cod, s.nro_factura));
  get diagnostics v_vistas = row_count;

  return jsonb_build_object('filas', v_filas, 'pagadas', v_pagadas, 'vistas', v_vistas);
end $$;
revoke all on function public.compras_pagos_realizar_importar(jsonb) from public, anon;
grant execute on function public.compras_pagos_realizar_importar(jsonb) to authenticated;

commit;

-- 5) Verificación
select tablename, policyname, roles, cmd from pg_policies
where tablename in ('compras_pend_facturar','compras_pagos_realizar','compras_solicitudes_pago')
   or (schemaname = 'storage' and policyname like '%facturas%')
order by 1,2;
