-- =====================================================================
-- Pañol · galpón por defecto en lo ya cargado (oct 2026)
-- Proyecto Supabase: wcpkpwxhqdcdljfwzcmy. Correr A MANO en el SQL Editor.
--
-- Qué hace: completa con 'LA HUELLA 610' el galpón de las erogaciones que lo tienen vacío (la app ya lo propone en las nuevas).
-- No pisa los que ya tienen galpón. Los períodos CERRADOS no se tocan: el candado de cierres lo impediría (si hay uno cerrado con vacíos,
-- hay que reabrirlo, correr esto y volver a cerrar).
--
-- 1) PRIMERO mirá cuántas filas va a tocar (solo lee):
--    select periodo, count(*) from public.compras_panol_egresos where coalesce(btrim(galpon),'')='' group by periodo order by periodo;
-- 2) Después corré el bloque de abajo.
-- Reversible solo en parte: las filas que estaban vacías quedarían con el galpón; no hay forma de distinguirlas después.
-- =====================================================================
begin;

insert into public.compras_panol_galpones (nombre, creado_por) values ('LA HUELLA 610', 'sql') on conflict do nothing;

update public.compras_panol_egresos e
   set galpon = 'LA HUELLA 610'
 where coalesce(btrim(e.galpon),'') = ''
   and not exists (select 1 from public.compras_panol_cierres c where c.periodo = e.periodo and c.estado = 'Cerrado');

commit;
