-- =====================================================================
-- Pañol · aprobación de observaciones de precio (oct 2026)
-- Proyecto Supabase: wcpkpwxhqdcdljfwzcmy. Correr A MANO en el SQL Editor,
-- ANTES de publicar el index.html que usa estas columnas.
--
-- Qué hace (aditivo): agrega a compras_panol_egresos las columnas con las que se aprueba una observación de precio
-- (REVISAR vs TANGO, REVISAR TC, FECHA POSTERIOR AL MES) sin borrarla:
--   alerta_ok        observaciones aprobadas (separadas por coma); `alerta` queda solo con las pendientes
--   alerta_ok_por    quién las aprobó ('usuario' o 'usuario (automático)')
--   alerta_ok_en     cuándo
--   alerta_ok_precio precio unitario ARS al aprobar: si el precio cambia después, la aprobación deja de valer
-- En un período cerrado el trigger de cierres impide cambiarlas (como cualquier otro dato).
--
-- Reversible: alter table public.compras_panol_egresos drop column alerta_ok, drop column alerta_ok_por, drop column alerta_ok_en, drop column alerta_ok_precio;
-- =====================================================================
alter table public.compras_panol_egresos
  add column if not exists alerta_ok        text,
  add column if not exists alerta_ok_por    text,
  add column if not exists alerta_ok_en     timestamptz,
  add column if not exists alerta_ok_precio numeric;
