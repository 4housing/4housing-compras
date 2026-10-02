-- =====================================================================
-- Solicitudes de pago · los informes los carga Administración y Finanzas (oct 2026)
-- Proyecto Supabase: wcpkpwxhqdcdljfwzcmy. Correr A MANO en el SQL Editor, DESPUÉS de
-- 2026-10_solpago_informes.sql (ya corrido) y ANTES de publicar los index.html de Compras y adminfin.
--
-- Qué hace:
--   1) compras_informes_meta: constancia de cada informe (fecha del reporte de Tango, quién y cuándo lo subió).
--   2) Informe OC y Pendientes de facturar: Compras pasa a SOLO LEER; los carga adminfin con
--      compras_informe_cargar() (en tandas: la primera reemplaza, las siguientes agregan).
--   3) Pagos a realizar: compras_pagos_realizar_importar() ahora recibe la fecha del reporte y deja la constancia.
--   4) adminfin lee compras_oc_informe, compras_pend_facturar y compras_proveedores (para los nombres).
--   La solicitud de pago la hace SOLO Compras (adjuntar FAC / tildar); adminfin responde la gestión con
--   compras_solpago_adminfin() (confirmar lectura, fecha estimada de pago, mensajes), que no cambia.
--   Escritura de adminfin siempre con puede_editar_sector('adminfin') → lector/lectura solo ven.
--
-- Reversible (volver a como estaba con 2026-10_solpago_informes.sql):
--   drop table public.compras_informes_meta;
--   drop function public.compras_informe_cargar(text,jsonb,boolean,date);
--   drop function public.compras_pagos_realizar_importar(jsonb,date);  -- y recrear la de (jsonb) del archivo anterior
--   drop policy compras_oc_informe_sel on public.compras_oc_informe;
--   create policy compras_sector on public.compras_oc_informe for all to authenticated
--     using (public.tiene_sector('compras'::public.sector_portal)) with check (public.tiene_sector('compras'::public.sector_portal));
--   (pend_facturar: recrear compras_pend_facturar_ins/_del del archivo anterior)
--   drop policy compras_prov_adminfin_sel on public.compras_proveedores;
-- =====================================================================

-- 0) (opcional, mirar antes) policies actuales de las tablas que se tocan
select tablename, policyname, cmd from pg_policies
where tablename in ('compras_oc_informe','compras_pend_facturar','compras_proveedores','compras_solicitudes_pago')
order by 1,2;

begin;

-- 1) Constancia de cada informe
create table if not exists public.compras_informes_meta (
  informe        text primary key check (informe in ('oc_informe','pend_facturar','pagos_realizar')),
  fecha_reporte  date,          -- fecha del reporte de Tango (la carga quien lo sube)
  importado_en   timestamptz,
  importado_por  text,
  filas          integer
);
alter table public.compras_informes_meta enable row level security;
revoke all on public.compras_informes_meta from anon;
grant select on public.compras_informes_meta to authenticated;   -- se escribe solo desde las funciones
drop policy if exists compras_informes_meta_sel on public.compras_informes_meta;
create policy compras_informes_meta_sel on public.compras_informes_meta for select to authenticated
  using (public.tiene_sector('compras'::public.sector_portal) or public.tiene_sector('adminfin'::public.sector_portal));

-- 2) Informe OC y Pendientes de facturar: lectura para compras y adminfin; sin escritura directa
drop policy if exists compras_sector on public.compras_oc_informe;
drop policy if exists compras_oc_informe_sel on public.compras_oc_informe;
create policy compras_oc_informe_sel on public.compras_oc_informe for select to authenticated
  using (public.tiene_sector('compras'::public.sector_portal) or public.tiene_sector('adminfin'::public.sector_portal));

drop policy if exists compras_pend_facturar_ins on public.compras_pend_facturar;
drop policy if exists compras_pend_facturar_del on public.compras_pend_facturar;
drop policy if exists compras_pend_facturar_sel on public.compras_pend_facturar;
create policy compras_pend_facturar_sel on public.compras_pend_facturar for select to authenticated
  using (public.tiene_sector('compras'::public.sector_portal) or public.tiene_sector('adminfin'::public.sector_portal));
revoke insert, update, delete on public.compras_pend_facturar from authenticated;

-- Proveedores: adminfin solo lee (para mostrar la razón social)
drop policy if exists compras_prov_adminfin_sel on public.compras_proveedores;
create policy compras_prov_adminfin_sel on public.compras_proveedores for select to authenticated
  using (public.tiene_sector('adminfin'::public.sector_portal));

-- Carga en tandas de Informe OC / Pendientes de facturar (p_reset=true en la primera tanda)
create or replace function public.compras_informe_cargar(p_informe text, p_filas jsonb, p_reset boolean, p_fecha_reporte date default null)
returns jsonb
language plpgsql security definer
set search_path = public
as $$
declare
  v_autor text := coalesce((select nullif(p.email,'') from public.perfiles p where p.id = auth.uid()), auth.jwt()->>'email', '');
  v_n int; v_total int;
begin
  if not public.puede_editar_sector('adminfin'::public.sector_portal) then
    raise exception 'Sin permiso de edición en Administración y Finanzas';
  end if;
  if p_filas is null or jsonb_typeof(p_filas) <> 'array' then raise exception 'Formato de filas inválido'; end if;

  if p_informe = 'oc_informe' then
    if p_reset then delete from public.compras_oc_informe where true; end if;
    insert into public.compras_oc_informe (fecha_emision, clasif_cod, oc_numero, renglon, remito_numero, proveedor_cod, cod_articulo, descripcion,
      cantidad_pedida, cantidad_recibida, cantidad_pendiente, importe_neto, estado_oc, observacion, fecha_entrega, deposito, comprador,
      total_sin_iva_oc, total_con_iva_oc, condicion_compra, tipo_comprobante, comprobante_numero, desc_comprobante, estado_pago)
    select x.fecha_emision, x.clasif_cod, x.oc_numero, x.renglon, x.remito_numero, x.proveedor_cod, x.cod_articulo, x.descripcion,
      x.cantidad_pedida, x.cantidad_recibida, x.cantidad_pendiente, x.importe_neto, x.estado_oc, x.observacion, x.fecha_entrega, x.deposito, x.comprador,
      x.total_sin_iva_oc, x.total_con_iva_oc, x.condicion_compra, x.tipo_comprobante, x.comprobante_numero, x.desc_comprobante, x.estado_pago
    from jsonb_populate_recordset(null::public.compras_oc_informe, p_filas) x
    where nullif(btrim(coalesce(x.oc_numero,'')),'') is not null;
    get diagnostics v_n = row_count;
    select count(*) into v_total from public.compras_oc_informe;
  elsif p_informe = 'pend_facturar' then
    if p_reset then delete from public.compras_pend_facturar where true; end if;
    insert into public.compras_pend_facturar (talonario, oc_numero, proveedor_cod, fecha_ingreso, comprador, clasif_cod, clasif_desc, cod_articulo,
      descripcion, cantidad_pedida, cantidad_pend_facturar, total_pedido_sin_imp, pend_facturar_sin_imp, estado, estado_renglon, costeo,
      estructura, leyendas, condicion_compra, moneda, importado_en, importado_por)
    select x.talonario, x.oc_numero, x.proveedor_cod, x.fecha_ingreso, x.comprador, x.clasif_cod, x.clasif_desc, x.cod_articulo,
      x.descripcion, x.cantidad_pedida, x.cantidad_pend_facturar, x.total_pedido_sin_imp, x.pend_facturar_sin_imp, x.estado, x.estado_renglon, x.costeo,
      x.estructura, x.leyendas, x.condicion_compra, x.moneda, now(), v_autor
    from jsonb_populate_recordset(null::public.compras_pend_facturar, p_filas) x
    where nullif(btrim(coalesce(x.oc_numero,'')),'') is not null;
    get diagnostics v_n = row_count;
    select count(*) into v_total from public.compras_pend_facturar;
  else
    raise exception 'Informe desconocido: %', p_informe;
  end if;

  insert into public.compras_informes_meta (informe, fecha_reporte, importado_en, importado_por, filas)
  values (p_informe, coalesce(p_fecha_reporte, current_date), now(), v_autor, v_total)
  on conflict (informe) do update set fecha_reporte = excluded.fecha_reporte, importado_en = excluded.importado_en,
    importado_por = excluded.importado_por, filas = excluded.filas;
  return jsonb_build_object('insertadas', v_n, 'total', v_total);
end $$;
revoke all on function public.compras_informe_cargar(text,jsonb,boolean,date) from public, anon;
grant execute on function public.compras_informe_cargar(text,jsonb,boolean,date) to authenticated;

-- 3) Pagos a realizar: misma lógica que antes + fecha del reporte y constancia
drop function if exists public.compras_pagos_realizar_importar(jsonb);
create or replace function public.compras_pagos_realizar_importar(p_filas jsonb, p_fecha_reporte date default null)
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

  update public.compras_solicitudes_pago s
     set pagos_realizar_visto_en = coalesce(s.pagos_realizar_visto_en, now())
   where s.estado <> 'Pagada'
     and exists (select 1 from public.compras_pagos_realizar r
                  where public.compras_clave_fac(r.proveedor_cod, r.comprobante_numero) = public.compras_clave_fac(s.proveedor_cod, s.nro_factura));
  get diagnostics v_vistas = row_count;

  insert into public.compras_informes_meta (informe, fecha_reporte, importado_en, importado_por, filas)
  values ('pagos_realizar', coalesce(p_fecha_reporte, current_date), now(), v_autor, v_filas)
  on conflict (informe) do update set fecha_reporte = excluded.fecha_reporte, importado_en = excluded.importado_en,
    importado_por = excluded.importado_por, filas = excluded.filas;

  return jsonb_build_object('filas', v_filas, 'pagadas', v_pagadas, 'vistas', v_vistas);
end $$;
revoke all on function public.compras_pagos_realizar_importar(jsonb,date) from public, anon;
grant execute on function public.compras_pagos_realizar_importar(jsonb,date) to authenticated;


commit;

-- 4) Verificación
select tablename, policyname, cmd from pg_policies
where tablename in ('compras_oc_informe','compras_pend_facturar','compras_proveedores','compras_solicitudes_pago','compras_informes_meta')
   or (schemaname = 'storage' and policyname like '%facturas%')
order by 1,2;
