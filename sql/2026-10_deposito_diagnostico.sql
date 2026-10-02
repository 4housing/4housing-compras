-- Depósito: diagnóstico post-migración (aaqp -> wcpk). SOLO LECTURA, no modifica nada.
-- Correr a mano en el SQL Editor de Supabase del proyecto wcpk (wcpkpwxhqdcdljfwzcmy).
--
-- La vista "Depósito" (Stock y control de artículos) lee de la tabla 'deposito' (sin prefijo,
-- SCHEMAS.deposito.table). Si no existe, la app muestra 3 artículos de ejemplo en vez de un error.
-- Este script dice si existe alguna tabla de depósito en wcpk y cuántas filas tiene.
-- (compras_depositos es otra cosa: el diccionario de depósitos de Tango.)

-- Un solo resultado: tablas cuyo nombre contiene "deposito", con su cantidad de filas.
select t.table_name,
       (xpath('/row/n/text()',
              query_to_xml(format('select count(*) as n from public.%I', t.table_name), false, true, '')))[1]::text::int as filas
from information_schema.tables t
where t.table_schema = 'public' and t.table_name like '%deposito%'
order by t.table_name;
