-- Dólar diario: diagnóstico antes de completar días faltantes con ArgentinaDatos. SOLO LECTURA.
-- Correr a mano en el SQL Editor de wcpk. Devuelve un solo resultado.
--   ogs_sin_tc: OG que NO tienen TC guardado (tc_pesos vacío) y lo calculan en el momento con el blue
--               diario del día anterior a su fecha. Son las únicas que podrían cambiar al completar días.
--   ogs_sin_tc_en_hueco: de esas, cuántas caen hoy en un día anterior SIN cotización blue (son las que
--               efectivamente cambiarían de TC si se completa ese día).
--   blue/oficial: filas, primera y última fecha, y días hábiles (lun-vie) sin dato desde 2020-01-01.
select 'ogs_sin_tc' as que, count(*)::text as n, min(fecha)::text as desde, max(fecha)::text as hasta
from public.compras_ogs where tc_pesos is null
union all
select 'ogs_sin_tc_en_hueco', count(*)::text, min(o.fecha)::text, max(o.fecha)::text
from public.compras_ogs o
where o.tc_pesos is null and o.fecha is not null
  and not exists (select 1 from public.compras_usd_diario u where u.fecha::date = (o.fecha::date - 1))
union all
select 'blue_diario', count(*)::text, min(fecha)::text, max(fecha)::text from public.compras_usd_diario
union all
select 'blue_habiles_sin_dato_desde_2020', count(*)::text, min(d)::date::text, max(d)::date::text
from generate_series('2020-01-01'::date, current_date - 1, interval '1 day') d
where extract(isodow from d) < 6 and not exists (select 1 from public.compras_usd_diario u where u.fecha::date = d::date)
union all
select 'oficial_diario', count(*)::text, min(fecha)::text, max(fecha)::text from public.compras_usd_diario_oficial
union all
select 'oficial_habiles_sin_dato_desde_2020', count(*)::text, min(d)::date::text, max(d)::date::text
from generate_series('2020-01-01'::date, current_date - 1, interval '1 day') d
where extract(isodow from d) < 6 and not exists (select 1 from public.compras_usd_diario_oficial u where u.fecha::date = d::date);
