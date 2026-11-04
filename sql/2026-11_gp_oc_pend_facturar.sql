-- Gestión de Proyectos: el "Comprado" de una OC cerrada (parcial) se calcula con la cantidad pendiente de facturar + facturada.
-- Correr A MANO en el SQL Editor de Supabase ANTES de publicar el HTML. Aditivo: no toca datos existentes.
-- Después hay que reimportar el Informe OC de cada proyecto (la columna "Cantidad Pendiente de Facturar" del Informe).
alter table public.compras_gp_oc add column if not exists cantidad_pend_facturar numeric;
