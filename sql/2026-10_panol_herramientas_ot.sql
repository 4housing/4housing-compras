-- =====================================================================
-- Abastecimiento · Herramientas pedidas junto con una OT (oct 2026)
-- Proyecto Supabase: wcpkpwxhqdcdljfwzcmy. Correr A MANO en el SQL Editor,
-- DESPUÉS de sql/2026-10_panol_herramientas.sql y sql/2026-10_panol_solicitudes.sql, y ANTES de publicar el index.html que usa estas columnas.
--
-- Qué hace (aditivo): compras_panol_herr.solicitud_id y nro_ot. Cuando una OT se carga con herramientas (opcional), cada pedido de herramienta queda
-- vinculado a esa OT: se ve en el detalle de la OT y en la solapa Herramientas, y si se anula la OT se anulan los pedidos que todavía no se entregaron.
-- Los pedidos de herramientas que ya existen no se tocan (quedan sin OT).
--
-- Reversible:
--   alter table public.compras_panol_herr drop column solicitud_id, drop column nro_ot;
-- =====================================================================
begin;

alter table public.compras_panol_herr
  add column if not exists solicitud_id bigint references public.compras_panol_solicitudes(id) on delete set null,
  add column if not exists nro_ot text;

create index if not exists compras_panol_herr_solicitud_idx on public.compras_panol_herr (solicitud_id);

commit;
