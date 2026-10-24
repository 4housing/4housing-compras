-- =====================================================================
-- Pedido de armado de pago: detalle por renglón y fecha requerida (oct 2026)
-- Proyecto Supabase: wcpkpwxhqdcdljfwzcmy. Correr A MANO en el SQL Editor, DESPUÉS de
-- 2026-10_op_armada.sql (ya corrido) y ANTES de publicar el index.html.
--
-- El comprador pide el armado por renglón de la OG (como al certificar), con % o monto y la fecha en
-- que necesita los valores:
--   compras_ogs.pago_pedido_detalle  jsonb  [{idx, desc, pct, monto, fecha}]
--   compras_ogs.pago_pedido_fecha    date   (la más próxima de los renglones, para ordenar en Tesorería)
--   compras_ogs.pago_pedido_monto    ya existe: queda como la suma de los renglones.
-- No crea tablas ni cambia policies.
--
-- Reversible:
--   alter table public.compras_ogs drop column pago_pedido_detalle, drop column pago_pedido_fecha;
-- =====================================================================

begin;

alter table public.compras_ogs
  add column if not exists pago_pedido_detalle jsonb,
  add column if not exists pago_pedido_fecha   date;

commit;

-- Verificación: tienen que aparecer las 2 columnas
select column_name, data_type from information_schema.columns
where table_name = 'compras_ogs' and column_name in ('pago_pedido_detalle','pago_pedido_fecha')
order by 1;
