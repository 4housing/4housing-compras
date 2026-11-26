-- =====================================================================
-- Transferencias por Santander UY (nov 2026) — etapa 3: el pago de la OG en Compras se registra solo
-- Proyecto Supabase: wcpkpwxhqdcdljfwzcmy. Correr A MANO en el SQL Editor, DESPUÉS de
-- sql/2026-11_transferencias_uy.sql y de 4housing-adminfin/sql/2026-11_transferencias_uy_finanzas.sql (ya corridos),
-- y ANTES de publicar el index.html de Compras.
--
-- Trigger en compras_solicitudes_pago (pedidos tipo 'transferencia_uy'):
--   * Cuando Finanzas lo marca Pagada → se registra el pago de la OG en compras_pagos (para el costo del proyecto):
--     importe US$ del pedido, fecha de pago, TC de la OG, medio "Transferencia Santander UY", cuenta 11120025
--     (Santander UY USD), sin_caja = true (no descuenta de la caja de Tesorería). El N° de OP lo pone la base como
--     a cualquier pago. Queda el vínculo en compras_pago_id. Ese pago NO va a los asientos de Compras (la app lo
--     excluye): el asiento lo arma Contabilidad UY.
--   * Si Finanzas lo vuelve a En gestión (no se pudo pagar / error) → ese pago se anula: se copia a
--     compras_pagos_anulados (como "Eliminar pago") y se borra de compras_pagos.
-- La función es security definer: la usa quien marca Pagada en Administración y Finanzas (no edita pagos de Compras).
-- No crea tablas ni policies.
--
-- Reversible:
--   drop trigger if exists compras_transf_uy_pago on public.compras_solicitudes_pago;
--   drop function if exists public.compras_transf_uy_pago_trg();
-- =====================================================================

begin;

create or replace function public.compras_transf_uy_pago_trg()
returns trigger
language plpgsql security definer
set search_path = public
as $$
declare
  v_autor text := coalesce((select nullif(p.email,'') from public.perfiles p where p.id = auth.uid()), auth.jwt()->>'email', '');
  o   public.compras_ogs;
  r   public.compras_pagos;
  v_tot numeric;
  v_id  bigint;
begin
  if new.tipo is distinct from 'transferencia_uy' or new.og_id is null then return new; end if;

  -- Pasa a Pagada: registrar el pago de la OG
  if new.estado = 'Pagada' and coalesce(old.estado,'') <> 'Pagada' and new.compras_pago_id is null then
    select * into o from public.compras_ogs where id = new.og_id;
    if not found or o.moneda is distinct from 'Extranjera' then return new; end if;   -- solo OG en US$
    -- total de la OG (renglones con sus bonificaciones y la de la OG), para el % del pago
    select sum(coalesce((e->>'cant')::numeric,0) * coalesce((e->>'precio_unit')::numeric,0) * (1 - coalesce((e->>'bonif_pct')::numeric,0)/100))
      into v_tot from jsonb_array_elements(coalesce(o.items,'[]'::jsonb)) e;
    v_tot := coalesce(nullif(v_tot,0), o.monto_total) * (1 - coalesce(o.bonif_pct,0)/100);
    insert into public.compras_pagos
      (og_id, numero, fecha, pct, moneda_og, moneda_pago, tc, medio, caja_cod, sin_caja, importe_pago, observaciones, registrado_por, estado_op)
    values
      (o.id, o.numero, coalesce(new.fecha_pago, current_date),
       case when coalesce(v_tot,0) > 0 then round(coalesce(new.monto,0) / v_tot * 100, 6) end,
       'USD', 'USD', o.tc_pesos, 'Transferencia Santander UY', '11120025', true, coalesce(new.monto,0),
       'Transferencia Santander UY · pedido N° ' || new.id || coalesce(' · CFE ' || new.nro_factura, '') || ' · asiento en Contabilidad UY',
       v_autor, 'Pagada')
    returning id into v_id;
    new.compras_pago_id := v_id;
    new.historial := coalesce(new.historial,'[]'::jsonb) || jsonb_build_array(jsonb_build_object('fecha', now(), 'autor', v_autor,
                     'texto', 'Pago registrado en la OG ' || o.numero || ' de Compras.'));

  -- Deja de estar Pagada: se anula el pago que se había registrado
  elsif coalesce(old.estado,'') = 'Pagada' and new.estado <> 'Pagada' and new.compras_pago_id is not null then
    select * into r from public.compras_pagos where id = new.compras_pago_id for update;
    if found then
      insert into public.compras_pagos_anulados
        (pago_id, op_numero, og_id, og_numero, fecha_pago, moneda_pago, importe_pago, asiento_num, datos, motivo, anulado_por)
      values
        (r.id, r.op_numero::text, r.og_id, r.numero::text, r.fecha, r.moneda_pago, r.importe_pago,
         nullif(btrim(coalesce(r.asiento_num::text,'')),''), to_jsonb(r),
         'La transferencia Santander UY (pedido N° ' || new.id || ') volvió a En gestión en Finanzas', v_autor);
      delete from public.compras_pagos where id = r.id;
    end if;
    new.compras_pago_id := null;
  end if;
  return new;
end $$;
revoke all on function public.compras_transf_uy_pago_trg() from public, anon;

drop trigger if exists compras_transf_uy_pago on public.compras_solicitudes_pago;
create trigger compras_transf_uy_pago
  before update of estado on public.compras_solicitudes_pago
  for each row execute function public.compras_transf_uy_pago_trg();

commit;

-- Verificación: tiene que aparecer el trigger
select tgname from pg_trigger where tgrelid = 'public.compras_solicitudes_pago'::regclass and tgname = 'compras_transf_uy_pago';
