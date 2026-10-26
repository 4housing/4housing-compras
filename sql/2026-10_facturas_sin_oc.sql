-- =====================================================================
-- Compras ↔ Finanzas · Facturas sin OC (oct 2026)
-- Proyecto Supabase: wcpkpwxhqdcdljfwzcmy. Correr A MANO en el SQL Editor, DESPUÉS de
-- 2026-10_solpago_reabrir.sql (ya corrido) y ANTES de publicar los index.html de Compras y adminfin.
--
-- Qué hace:
--   1) Tabla nueva compras_facturas_sin_oc: Finanzas carga una factura que llegó sin OC (con el PDF) y la
--      asigna a un comprador o la deja "Sin asignar" (bandeja común de Compras). Compras informa la OC que
--      generó (o dice "No corresponde"); Finanzas la cierra. Historial con usuario, fecha y hora.
--      Estados: Sin asignar · Asignada · OC informada · No corresponde · Cerrada.
--      Leen: sectores compras y adminfin. Alta y baja: quien edita adminfin. Modifican: compras y quien edita adminfin.
--   2) PDF: quien edita adminfin puede subir/borrar en el bucket "facturas", solo dentro de la carpeta sin-oc/.
--      (Compras ya lee y sube en ese bucket; adminfin ya lee.)
--   3) compras_compradores(): lista de compradores (nombre, como figura en las OG) para asignar desde adminfin.
--      Devuelve solo los nombres, no los permisos de cada usuario.
--   4) Pagos a realizar: columna nueva fecha_vencimiento (el reporte de Tango ahora la trae) y la función
--      de importación la guarda. El resto de la función queda igual que en 2026-10_solpago_gestion.sql.
--
-- Reversible:
--   drop table public.compras_facturas_sin_oc;
--   drop policy adminfin_facturas_sinoc_ins on storage.objects; drop policy adminfin_facturas_sinoc_del on storage.objects;
--   drop function public.compras_compradores();
--   alter table public.compras_pagos_realizar drop column fecha_vencimiento;  -- y volver a correr la sección 1 de 2026-10_solpago_gestion.sql
-- =====================================================================

begin;

-- 1) Facturas sin OC
create table if not exists public.compras_facturas_sin_oc (
  id              bigint generated always as identity primary key,
  proveedor_cod   text,
  proveedor       text,
  nro_factura     text not null,
  fecha_factura   date,
  monto           numeric,
  moneda          text not null default 'ARS' check (moneda in ('ARS','USD')),
  adjunto_path    text,          -- bucket facturas, carpeta sin-oc/
  adjunto_nombre  text,
  comprador       text,          -- nombre como en compras_usuarios_autorizados; vacío = sin asignar
  estado          text not null default 'Sin asignar'
                  check (estado in ('Sin asignar','Asignada','OC informada','No corresponde','Cerrada')),
  oc_numero       text,          -- OC que informó Compras (N° corto, como en compras_oc_informe)
  oc_informada_por text,
  oc_informada_en timestamptz,
  pedir_pago      boolean not null default false,   -- Compras tildó "incluir en solicitar pago"
  solicitud_pago_id bigint,      -- pedido de pago que se generó con ese tilde
  historial       jsonb not null default '[]'::jsonb,
  creado_en       timestamptz not null default now(),
  creado_por      text,
  actualizado_en  timestamptz
);
create index if not exists compras_facturas_sin_oc_estado_idx on public.compras_facturas_sin_oc (estado);

alter table public.compras_facturas_sin_oc enable row level security;
revoke all on public.compras_facturas_sin_oc from anon;
grant select, insert, update, delete on public.compras_facturas_sin_oc to authenticated;

drop policy if exists compras_fsoc_sel on public.compras_facturas_sin_oc;
drop policy if exists compras_fsoc_ins on public.compras_facturas_sin_oc;
drop policy if exists compras_fsoc_upd on public.compras_facturas_sin_oc;
drop policy if exists compras_fsoc_del on public.compras_facturas_sin_oc;
create policy compras_fsoc_sel on public.compras_facturas_sin_oc for select to authenticated
  using (public.tiene_sector('compras'::public.sector_portal) or public.tiene_sector('adminfin'::public.sector_portal));
create policy compras_fsoc_ins on public.compras_facturas_sin_oc for insert to authenticated
  with check (public.puede_editar_sector('adminfin'::public.sector_portal));
create policy compras_fsoc_upd on public.compras_facturas_sin_oc for update to authenticated
  using (public.tiene_sector('compras'::public.sector_portal) or public.puede_editar_sector('adminfin'::public.sector_portal))
  with check (public.tiene_sector('compras'::public.sector_portal) or public.puede_editar_sector('adminfin'::public.sector_portal));
create policy compras_fsoc_del on public.compras_facturas_sin_oc for delete to authenticated
  using (public.puede_editar_sector('adminfin'::public.sector_portal));

-- 2) PDF en el bucket facturas, carpeta sin-oc/ (adminfin sube y borra solo ahí)
drop policy if exists adminfin_facturas_sinoc_ins on storage.objects;
drop policy if exists adminfin_facturas_sinoc_del on storage.objects;
create policy adminfin_facturas_sinoc_ins on storage.objects for insert to authenticated
  with check (bucket_id = 'facturas' and (storage.foldername(name))[1] = 'sin-oc'
              and public.puede_editar_sector('adminfin'::public.sector_portal));
create policy adminfin_facturas_sinoc_del on storage.objects for delete to authenticated
  using (bucket_id = 'facturas' and (storage.foldername(name))[1] = 'sin-oc'
         and public.puede_editar_sector('adminfin'::public.sector_portal));

-- 3) Compradores (solo nombres) para asignar desde adminfin
create or replace function public.compras_compradores()
returns table (nombre text)
language sql stable security definer
set search_path = public
as $$
  select distinct u.nombre from public.compras_usuarios_autorizados u
   where u.es_comprador and nullif(btrim(coalesce(u.nombre,'')),'') is not null
     and (public.tiene_sector('compras'::public.sector_portal) or public.tiene_sector('adminfin'::public.sector_portal))
   order by 1
$$;
revoke all on function public.compras_compradores() from public, anon;
grant execute on function public.compras_compradores() to authenticated;

-- 4) Pagos a realizar: + fecha de vencimiento
alter table public.compras_pagos_realizar add column if not exists fecha_vencimiento date;

create or replace function public.compras_pagos_realizar_importar(p_filas jsonb, p_fecha_reporte date default null)
returns jsonb
language plpgsql security definer
set search_path = public
as $$
declare
  v_autor text := coalesce((select nullif(p.email,'') from public.perfiles p where p.id = auth.uid()), auth.jwt()->>'email', '');
  v_fecha date := coalesce(p_fecha_reporte, current_date);
  v_filas int; v_salieron int; v_vistas int;
begin
  if not public.puede_editar_sector('adminfin'::public.sector_portal) then
    raise exception 'Sin permiso de edición en Administración y Finanzas';
  end if;
  if p_filas is null or jsonb_typeof(p_filas) <> 'array' or jsonb_array_length(p_filas) = 0 then
    raise exception 'El informe viene vacío';
  end if;

  delete from public.compras_pagos_realizar where true;
  insert into public.compras_pagos_realizar
         (fecha_vencimiento, fecha_emision, fecha_contable, tipo_comprobante, proveedor_cod, comprobante_numero, total_pend_cte, total_pend_ext, importado_en, importado_por)
  select x.fecha_vencimiento, x.fecha_emision, x.fecha_contable, x.tipo_comprobante, x.proveedor_cod, x.comprobante_numero, x.total_pend_cte, x.total_pend_ext, now(), v_autor
    from jsonb_to_recordset(p_filas) as x(fecha_vencimiento date, fecha_emision date, fecha_contable date, tipo_comprobante text, proveedor_cod text,
                                          comprobante_numero text, total_pend_cte numeric, total_pend_ext numeric)
   where nullif(btrim(coalesce(x.comprobante_numero,'')),'') is not null;
  get diagnostics v_filas = row_count;

  -- Estaba en un informe anterior y ya no está → comentario + marca (una sola vez); el estado no cambia
  update public.compras_solicitudes_pago s
     set salio_informe_en = v_fecha, actualizado_en = now(),
         historial = coalesce(s.historial,'[]'::jsonb) || jsonb_build_array(jsonb_build_object(
           'fecha', now(), 'autor', v_autor,
           'texto', 'Ya no figura en Pagos a realizar (reporte del ' || to_char(v_fecha,'DD/MM/YYYY') || '): se estima pagada, anulada u otro motivo.'))
   where s.estado not in ('Pagada','Cancelada')
     and s.pagos_realizar_visto_en is not null
     and s.salio_informe_en is null
     and not exists (select 1 from public.compras_pagos_realizar r
                      where public.compras_clave_fac(r.proveedor_cod, r.comprobante_numero) = public.compras_clave_fac(s.proveedor_cod, s.nro_factura));
  get diagnostics v_salieron = row_count;

  -- Las que figuran: vistas (y si habían salido y volvieron, se limpia la marca)
  update public.compras_solicitudes_pago s
     set pagos_realizar_visto_en = coalesce(s.pagos_realizar_visto_en, now()), salio_informe_en = null
   where exists (select 1 from public.compras_pagos_realizar r
                  where public.compras_clave_fac(r.proveedor_cod, r.comprobante_numero) = public.compras_clave_fac(s.proveedor_cod, s.nro_factura))
     and (s.pagos_realizar_visto_en is null or s.salio_informe_en is not null);
  get diagnostics v_vistas = row_count;

  insert into public.compras_informes_meta (informe, fecha_reporte, importado_en, importado_por, filas)
  values ('pagos_realizar', v_fecha, now(), v_autor, v_filas)
  on conflict (informe) do update set fecha_reporte = excluded.fecha_reporte, importado_en = excluded.importado_en,
    importado_por = excluded.importado_por, filas = excluded.filas;

  return jsonb_build_object('filas', v_filas, 'salieron', v_salieron, 'vistas', v_vistas);
end $$;
revoke all on function public.compras_pagos_realizar_importar(jsonb,date) from public, anon;
grant execute on function public.compras_pagos_realizar_importar(jsonb,date) to authenticated;

commit;

-- 5) Verificación: tabla con RLS (true), sus 4 policies, la columna nueva y las funciones
select relname, relrowsecurity from pg_class where relname = 'compras_facturas_sin_oc';
select policyname, cmd from pg_policies where tablename = 'compras_facturas_sin_oc' or policyname like 'adminfin_facturas_sinoc%' order by 1;
select column_name from information_schema.columns where table_name = 'compras_pagos_realizar' and column_name = 'fecha_vencimiento';
select proname from pg_proc where proname in ('compras_compradores','compras_pagos_realizar_importar');
