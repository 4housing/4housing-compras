-- =====================================================================
-- Solicitudes de pago · volver una Pagada a En gestión (oct 2026)
-- Proyecto Supabase: wcpkpwxhqdcdljfwzcmy. Correr A MANO en el SQL Editor, DESPUÉS de
-- 2026-10_solpago_gestion.sql (ya corrido) y ANTES de publicar el index.html de adminfin
-- que trae el botón "Volver a En gestión".
--
-- Qué cambia (solo la función compras_solpago_adminfin, misma firma):
--   Acción nueva 'reabrir': una solicitud Pagada vuelve a 'En gestión' (por ejemplo, no se pudo pagar
--   o se marcó por error). Pide motivo (p_texto), borra fecha_pago, conserva fecha_pago_estimada y deja
--   el cambio en el historial. Lo puede hacer quien edita adminfin (puede_editar_sector('adminfin')).
--   El resto de las acciones queda igual que en 2026-10_solpago_gestion.sql.
-- No crea tablas, columnas ni policies.
--
-- Reversible: volver a correr la sección 2 de 2026-10_solpago_gestion.sql (versión anterior de la función).
-- =====================================================================

begin;

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
  if s.estado = 'Pagada' and p_accion not in ('comentario','reabrir') then raise exception 'La solicitud ya está Pagada'; end if;
  if p_accion = 'reabrir' and s.estado <> 'Pagada' then raise exception 'Solo se puede volver a En gestión una solicitud Pagada'; end if;
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
  elsif p_accion = 'reabrir' then   -- deshacer Pagada (no se pudo pagar / se marcó por error) → En gestión
    if v_texto is null then raise exception 'Falta el motivo'; end if;
    v_hist := jsonb_build_object('fecha', now(), 'autor', v_autor, 'estado_nuevo', 'En gestión',
              'texto', 'Volvió a En gestión (estaba Pagada' || coalesce(' el ' || to_char(s.fecha_pago,'DD/MM/YYYY'), '') || '). Motivo: ' || v_texto);
    update public.compras_solicitudes_pago
       set estado = 'En gestión', fecha_pago = null,
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

-- Verificación: la función tiene la acción nueva
select proname, position('reabrir' in prosrc) > 0 as tiene_reabrir from pg_proc where proname = 'compras_solpago_adminfin';
