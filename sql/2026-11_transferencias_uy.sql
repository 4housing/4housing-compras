-- =====================================================================
-- Transferencias por Santander UY (nov 2026) — etapa 1: OG "se paga desde Santander UY" y pedido del comprador
-- Proyecto Supabase: wcpkpwxhqdcdljfwzcmy. Correr A MANO en el SQL Editor, ANTES de publicar el index.html.
--
-- Circuito (decidido con Micaela):
--   1) En la OG se marca "Se paga desde: Santander UY" (solo OG en US$). No pasa por la caja de Tesorería.
--   2) El comprador pide la transferencia a Finanzas con la FAC (CFE) adjunta: queda en Compras ↔ Finanzas →
--      Pagos solicitados (misma tabla compras_solicitudes_pago, tipo = 'transferencia_uy').
--   3) (etapas siguientes) Finanzas registra la factura en Contabilidad UY y el pago; el pago de la OG en Compras
--      se registra solo (para el costo del proyecto). El asiento lo hace Contabilidad UY, no Compras.
-- No crea tablas ni cambia policies (compras_ogs y compras_solicitudes_pago ya tienen las suyas).
--
-- Reversible:
--   alter table public.compras_ogs drop constraint if exists compras_ogs_pago_desde_chk;
--   alter table public.compras_ogs drop column if exists pago_desde;
--   alter table public.compras_solicitudes_pago drop constraint if exists compras_solicitudes_pago_tipo_chk;
--   alter table public.compras_solicitudes_pago drop column if exists tipo, drop column if exists og_id,
--     drop column if exists fac_fecha, drop column if exists rut_emisor, drop column if exists iva,
--     drop column if exists fecha_requerida, drop column if exists cuy_comprobante_id, drop column if exists compras_pago_id;
-- =====================================================================

begin;

-- 1) OG: de dónde sale la plata (vacío = caja de Tesorería, como siempre)
alter table public.compras_ogs add column if not exists pago_desde text;
alter table public.compras_ogs drop constraint if exists compras_ogs_pago_desde_chk;
alter table public.compras_ogs
  add constraint compras_ogs_pago_desde_chk check (pago_desde is null or pago_desde in ('caja','santander_uy'));

-- 2) Pedido de transferencia: misma tabla que los pedidos de pago, con su tipo y los datos de la FAC (CFE)
alter table public.compras_solicitudes_pago
  add column if not exists tipo               text not null default 'tango',  -- tango (lo de siempre) | transferencia_uy
  add column if not exists og_id              bigint,       -- OG que se paga (transferencia_uy)
  add column if not exists fac_fecha          date,         -- fecha de la factura (CFE)
  add column if not exists rut_emisor         text,
  add column if not exists iva                numeric,      -- IVA de la factura, en la moneda del pedido
  add column if not exists fecha_requerida    date,         -- para cuándo la necesita el comprador
  add column if not exists cuy_comprobante_id text,         -- (etapa 2) comprobante creado en Contabilidad UY
  add column if not exists compras_pago_id    bigint;       -- (etapa 3) pago de la OG registrado en Compras
alter table public.compras_solicitudes_pago drop constraint if exists compras_solicitudes_pago_tipo_chk;
alter table public.compras_solicitudes_pago
  add constraint compras_solicitudes_pago_tipo_chk check (tipo in ('tango','transferencia_uy'));
create index if not exists compras_solicitudes_pago_og_idx on public.compras_solicitudes_pago (og_id) where og_id is not null;

commit;

-- Verificación: tienen que aparecer las 9 columnas
select table_name, column_name, data_type from information_schema.columns
where table_schema = 'public'
  and ((table_name = 'compras_ogs' and column_name = 'pago_desde')
    or (table_name = 'compras_solicitudes_pago' and column_name in
        ('tipo','og_id','fac_fecha','rut_emisor','iva','fecha_requerida','cuy_comprobante_id','compras_pago_id')))
order by 1, 2;
