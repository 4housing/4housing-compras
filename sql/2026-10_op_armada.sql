-- =====================================================================
-- OP armada antes de certificar / liberar (oct 2026)
-- Proyecto Supabase: wcpkpwxhqdcdljfwzcmy. Correr A MANO en el SQL Editor, ANTES de publicar el index.html.
--
-- Circuito:
--   1) El comprador de la OG pide "armar el pago" (aunque la OG no esté certificada) e indica el monto.
--      → compras_ogs.pago_pedido_monto / _por / _en / _nota
--   2) Tesorería emite la OP como "Armada" por hasta ese monto: tiene N° de OP, se imprime y
--      DESCUENTA DE LA CAJA (decisión de Mica), pero todavía no cuenta como pagada para la OG.
--      → compras_pagos.estado_op = 'Armada'
--   3) Cuando el comprador certifica y libera lo suficiente, Tesorería la marca "Pagada".
--      → compras_pagos.estado_op = 'Pagada', pagada_en, pagada_por
-- Los pagos de siempre quedan 'Pagada' (default), así que no cambia nada de lo existente.
-- No crea tablas ni cambia policies (compras_ogs y compras_pagos ya están en compras_sector).
--
-- Reversible:
--   alter table public.compras_pagos drop constraint compras_pagos_estado_op_chk;
--   alter table public.compras_pagos drop column estado_op, drop column pagada_en, drop column pagada_por;
--   alter table public.compras_ogs drop column pago_pedido_monto, drop column pago_pedido_por,
--     drop column pago_pedido_en, drop column pago_pedido_nota;
--   (antes, pasar a 'Pagada' o anular las OP que sigan 'Armada')
-- =====================================================================

begin;

alter table public.compras_ogs
  add column if not exists pago_pedido_monto numeric,       -- monto a armar, en la moneda de la OG
  add column if not exists pago_pedido_por   text,
  add column if not exists pago_pedido_en    timestamptz,
  add column if not exists pago_pedido_nota  text;

alter table public.compras_pagos
  add column if not exists estado_op  text not null default 'Pagada',
  add column if not exists pagada_en  timestamptz,
  add column if not exists pagada_por text;

alter table public.compras_pagos drop constraint if exists compras_pagos_estado_op_chk;
alter table public.compras_pagos add constraint compras_pagos_estado_op_chk check (estado_op in ('Armada','Pagada'));

commit;

-- Verificación: tienen que aparecer las 7 columnas
select table_name, column_name from information_schema.columns
where (table_name = 'compras_ogs'   and column_name like 'pago_pedido_%')
   or (table_name = 'compras_pagos' and column_name in ('estado_op','pagada_en','pagada_por'))
order by 1,2;
