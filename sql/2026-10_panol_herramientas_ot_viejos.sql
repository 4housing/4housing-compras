-- =====================================================================
-- Abastecimiento · Asignar OT a los pedidos de herramientas anteriores a las OT (oct 2026)
-- Proyecto Supabase: wcpkpwxhqdcdljfwzcmy. Correr A MANO en el SQL Editor,
-- DESPUÉS de sql/2026-10_panol_herramientas_ot.sql (necesita las columnas solicitud_id y nro_ot de compras_panol_herr).
--
-- Qué hace: cada pedido de herramientas que quedó sin OT (todos los estados, salvo los envíos a mantenimiento) se agrupa por solicitante,
-- destino y minuto de carga (lo que se cargó junto en un mismo pedido), y a cada grupo se le crea una OT nueva con el próximo número disponible
-- (OT-xxxxx, la misma numeración de siempre). El estado de la OT sale del de las herramientas: Entregada si ya se prestaron todas,
-- Parcial si algunas, Anulada si todas se anularon, Pendiente si ninguna.
-- No toca las demás columnas ni las OT que ya existen. Los envíos a mantenimiento NO se tocan (ver nota al final).
--
-- Reversible (solo mientras no se hayan usado las OT creadas):
--   update public.compras_panol_herr set solicitud_id = null, nro_ot = null where solicitud_id in (select id from public.compras_panol_solicitudes where comentario = 'Pedido de herramientas anterior a las OT');
--   delete from public.compras_panol_solicitudes where comentario = 'Pedido de herramientas anterior a las OT';
-- =====================================================================
do $$
declare r record; v_id bigint; v_nro text; v_est text; v_n int := 0;
begin
  for r in
    select solicitante, solicitante_email, destino_cod, destino_txt, date_trunc('minute', creado_en) as minuto,
           min(creado_en) as creado_en, min(desde) as fnec,
           bool_and(estado = 'Anulada') as todas_anuladas,
           bool_and(estado in ('Prestada','Devuelta','Anulada')) as sin_pendientes,
           bool_or(estado in ('Prestada','Devuelta')) as alguna_entregada
      from public.compras_panol_herr
     where solicitud_id is null and estado <> 'Mantenimiento'
     group by solicitante, solicitante_email, destino_cod, destino_txt, date_trunc('minute', creado_en)
     order by min(creado_en), min(id)
  loop
    v_est := case when r.todas_anuladas then 'Anulada'
                  when r.sin_pendientes then 'Entregada'
                  when r.alguna_entregada then 'Parcial'
                  else 'Pendiente' end;
    insert into public.compras_panol_solicitudes (nro_ot, solicitante, solicitante_email, destino_cod, destino_txt, fecha_necesidad, comentario, estado, creado_en, historial)
    values ('', r.solicitante, r.solicitante_email, r.destino_cod, r.destino_txt, r.fnec, 'Pedido de herramientas anterior a las OT', v_est, r.creado_en,
            jsonb_build_array(jsonb_build_object('accion','Creada','detalle','OT asignada a un pedido de herramientas anterior a las OT','por','migración','fecha', now())))
    returning id, nro_ot into v_id, v_nro;

    update public.compras_panol_herr
       set solicitud_id = v_id, nro_ot = v_nro
     where solicitud_id is null and estado <> 'Mantenimiento'
       and solicitante is not distinct from r.solicitante
       and solicitante_email is not distinct from r.solicitante_email
       and destino_cod is not distinct from r.destino_cod
       and destino_txt is not distinct from r.destino_txt
       and date_trunc('minute', creado_en) = r.minuto;
    v_n := v_n + 1;
  end loop;
  raise notice 'OT creadas: %', v_n;
end $$;

-- Verificación: pedidos de herramientas que siguen sin OT (debe quedar solo lo de mantenimiento)
select estado, count(*) as cantidad from public.compras_panol_herr where solicitud_id is null group by estado order by estado;
-- Las OT que se crearon
select nro_ot, solicitante, destino_cod, estado, fecha_necesidad from public.compras_panol_solicitudes where comentario = 'Pedido de herramientas anterior a las OT' order by id;

-- Nota: los envíos a mantenimiento (estado 'Mantenimiento') no son pedidos de nadie y no llevan OT. Si también querés una OT para cada uno, avisame.
