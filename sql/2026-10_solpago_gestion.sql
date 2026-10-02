-- =====================================================================
-- Solicitudes de pago · gestión (oct 2026)
-- Proyecto Supabase: wcpkpwxhqdcdljfwzcmy. Correr A MANO en el SQL Editor, DESPUÉS de
-- 2026-10_solpago_informes.sql y 2026-10_solpago_carga_adminfin.sql (ya corridos) y
-- ANTES de publicar los index.html de Compras y adminfin.
--
-- Qué cambia:
--   1) Columna nueva compras_solicitudes_pago.salio_informe_en (date): la FAC dejó de figurar en
--      Pagos a realizar. Ya NO pasa sola a Pagada: queda un comentario ("se estima pagada, anulada u
--      otro motivo") y la marca; el estado lo sigue definiendo Administración.
--   2) Estado nuevo 'Cancelada': Compras cancela el pedido de pago (con motivo). No quiere decir que no
--      se haya pagado. Lo hace Compras directo sobre la tabla (ya tiene permiso por compras_sector).
--   3) compras_solpago_adminfin(): acción nueva 'pagada' (estado Pagada + fecha de pago real).
--      'leido' = pasar a En gestión. Sobre una 'Cancelada' Administración solo puede comentar o marcar Pagada.
-- No crea tablas ni cambia policies.
--
-- Reversible:
--   alter table public.compras_solicitudes_pago drop column salio_informe_en;
--   y volver a correr la sección 3 de 2026-10_solpago_carga_adminfin.sql y la 4.c de 2026-10_solpago_informes.sql
--   (versiones anteriores de las dos funciones).
-- =====================================================================

begin;

alter table public.compras_solicitudes_pago add column if not exists salio_informe_en date;

-- 1) Importar Pagos a realizar: sin Pagada automática
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
         (fecha_emision, fecha_contable, tipo_comprobante, proveedor_cod, comprobante_numero, total_pend_cte, total_pend_ext, importado_en, importado_por)
  select x.fecha_emision, x.fecha_contable, x.tipo_comprobante, x.proveedor_cod, x.comprobante_numero, x.total_pend_cte, x.total_pend_ext, now(), v_autor
    from jsonb_to_recordset(p_filas) as x(fecha_emision date, fecha_contable date, tipo_comprobante text, proveedor_cod text,
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

-- 2) Acciones de Administración: + 'pagada'
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
  if s.estado = 'Pagada' and p_accion <> 'comentario' then raise exception 'La solicitud ya está Pagada'; end if;
  if s.estado = 'Cancelada' and p_accion not in ('comentario','pagada') then raise exception 'Compras canceló este pedido de pago'; end if;

  if p_accion = 'leido' then   -- pasar a En gestión
    v_hist := jsonb_build_object('fecha', now(), 'autor', v_autor, 'texto', 'Administración la pasó a En gestión.' || coalesce(' ' || v_texto, ''), 'estado_nuevo', 'En gestión');
    update public.compras_solicitudes_pago
       set leido_en = coalesce(leido_en, now()), leido_por = coalesce(leido_por, v_autor), estado = 'En gestión',
           historial = coalesce(historial,'[]'::jsonb) || jsonb_build_array(v_hist), actualizado_en = now()
     where id = p_id returning * into s;
  elsif p_accion = 'pagada' then
    if p_fecha is null then raise exception 'Falta la fecha de pago'; end if;
    v_hist := jsonb_build_object('fecha', now(), 'autor', v_autor, 'estado_nuevo', 'Pagada',
              'texto', 'Pagada el ' || to_char(p_fecha,'DD/MM/YYYY') || '.' || coalesce(' ' || v_texto, ''));
    update public.compras_solicitudes_pago
       set estado = 'Pagada', fecha_pago = p_fecha, leido_en = coalesce(leido_en, now()), leido_por = coalesce(leido_por, v_autor),
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

commit;

-- 3) Verificación: la columna nueva y las dos funciones
select column_name from information_schema.columns where table_name = 'compras_solicitudes_pago' and column_name = 'salio_informe_en';
select proname, pg_get_function_identity_arguments(oid) from pg_proc where proname in ('compras_pagos_realizar_importar','compras_solpago_adminfin');
