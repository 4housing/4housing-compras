-- =====================================================================
-- Pedido de armado: quién lo anuló y cuándo (nov 2026)
-- Proyecto Supabase: wcpkpwxhqdcdljfwzcmy. Correr A MANO en el SQL Editor, ANTES de publicar el index.html.
--
-- Cuando Tesorería anula un pedido de armado (botón "Anular pedido" o al registrar el pago por el camino
-- normal) o el comprador lo quita ("Quitar pedido"), la app guarda quién y cuándo. El comprador lo ve en la
-- ventana del botón $ ("Último pedido anulado por …").
-- No crea tablas ni cambia policies (compras_ogs ya está en compras_sector).
-- Si el index.html se publica antes que este SQL, la app anula igual pero sin registrar quién (y avisa).
--
-- Reversible:
--   alter table public.compras_ogs drop column if exists pago_pedido_anulado_por,
--     drop column if exists pago_pedido_anulado_en;
-- =====================================================================

begin;

alter table public.compras_ogs
  add column if not exists pago_pedido_anulado_por text,
  add column if not exists pago_pedido_anulado_en  timestamptz;

commit;

-- Verificación: tienen que aparecer las 2 columnas
select column_name, data_type from information_schema.columns
where table_schema = 'public' and table_name = 'compras_ogs' and column_name like 'pago_pedido_anulado_%'
order by 1;
