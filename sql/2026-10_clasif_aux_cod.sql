-- Clasificación de renglón: código de auxiliar fijo por clasificación (oct 2026)
-- Proyecto Supabase wcpkpwxhqdcdljfwzcmy · correr en el SQL Editor ANTES de publicar el index.html
--
-- Para clasificaciones cuyo auxiliar en Tango tiene OTRO código que la clasificación.
-- Ej.: IF4430 → auxiliar 04 = A00008; VENAM → auxiliar 03 = "1) VENTMIN".
-- Vacío (null) = como hasta ahora: se usa el código de la clasificación (o la serie del módulo en el 04).
-- No toca RLS: la tabla ya tiene sus policies. Reversible:
--   alter table public.compras_clasif_renglon drop column if exists aux_cod;

alter table public.compras_clasif_renglon
  add column if not exists aux_cod text;

-- Control: tiene que salir una fila con aux_cod
select column_name, data_type
  from information_schema.columns
 where table_schema = 'public' and table_name = 'compras_clasif_renglon' and column_name = 'aux_cod';
