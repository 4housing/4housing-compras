-- SOLP: campo "Seguimiento" (quién le hace el seguimiento), separado de "Gestiona" (quién la compra)
-- Proyecto Supabase wcpkpwxhqdcdljfwzcmy · correr en el SQL Editor ANTES de publicar el index.html
--
-- Caso: Cami tiene una SOLP de su proyecto que gestiona Gonzalo. Gestiona = Gonzalo, Seguimiento = Cami.
-- Las SOLP existentes arrancan con Seguimiento = quien la gestiona hoy (decisión de Micaela, oct 2026).
-- No toca RLS: la tabla ya tiene sus policies. Reversible:
--   alter table public.compras_solp_items drop column if exists seguimiento;

begin;

alter table public.compras_solp_items
  add column if not exists seguimiento text;

update public.compras_solp_items
   set seguimiento = gestiona
 where seguimiento is null and gestiona is not null;

commit;

-- Que la API reconozca la columna nueva enseguida
notify pgrst, 'reload schema';

-- Control: cuántos ítems quedaron con seguimiento cargado (debería coincidir con los que tienen gestiona)
select count(*) filter (where seguimiento is not null) as con_seguimiento,
       count(*) filter (where gestiona is not null)    as con_gestiona,
       count(*)                                         as total
  from public.compras_solp_items;
