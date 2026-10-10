-- =====================================================================
-- Tesorería · OP anuladas: al eliminar un pago queda registrado como anulado (oct 2026)
-- Proyecto Supabase: wcpkpwxhqdcdljfwzcmy. Correr A MANO en el SQL Editor, DESPUÉS de
-- 2026-10_pagos_eliminar_flag.sql (ya corrido) y ANTES de publicar el index.html que usa
-- compras_anular_pago().
--
-- Pedido de Micaela: que una OP eliminada no desaparezca sin rastro, sino que quede registrada
-- como anulada (qué era, quién, cuándo y por qué), SIN contar como erogación ni para la caja ni
-- para los asientos.
--
-- Diseño: el pago se COPIA a compras_pagos_anulados y se BORRA de compras_pagos, en una sola
-- operación. Así todo lo que hoy lee compras_pagos (saldo de caja, OGs pagadas, asientos,
-- tableros) sigue viendo solo los pagos vigentes, sin tener que tocarlo.
--
-- Qué cambia:
--   1) Tabla nueva compras_pagos_anulados (copia completa del pago en `datos` + quién/cuándo/motivo).
--      RLS: solo lectura para el sector compras; nadie escribe directo (solo la función).
--   2) Función compras_anular_pago(p_id, p_motivo): exige el flag puede_eliminar_pagos y un motivo;
--      copia y borra en la misma transacción. Si algo falla, no se borra nada.
--   No modifica compras_pagos ni sus policies.
--
-- Reversible:
--   drop function if exists public.compras_anular_pago(bigint, text);
--   drop table if exists public.compras_pagos_anulados;   -- (se pierde el registro de anuladas)
-- =====================================================================

begin;

-- 1) Registro de anuladas
create table if not exists public.compras_pagos_anulados (
  id            bigserial primary key,
  pago_id       bigint not null,            -- id que tenía en compras_pagos
  op_numero     text,
  og_id         bigint,
  og_numero     text,
  fecha_pago    date,
  moneda_pago   text,
  importe_pago  numeric,
  asiento_num   text,                       -- N° de asiento de Tango que tenía cargado (si tenía)
  datos         jsonb not null,             -- copia completa de la fila de compras_pagos
  motivo        text not null,
  anulado_por   text not null,
  anulado_en    timestamptz not null default now()
);

alter table public.compras_pagos_anulados enable row level security;

drop policy if exists compras_pagos_anulados_sel on public.compras_pagos_anulados;
create policy compras_pagos_anulados_sel on public.compras_pagos_anulados
  for select to authenticated
  using (public.tiene_sector('compras'::public.sector_portal));
-- Sin policies de insert/update/delete: solo escribe la función de abajo.

-- 2) Anular = copiar + borrar, todo junto
create or replace function public.compras_anular_pago(p_id bigint, p_motivo text)
returns public.compras_pagos_anulados
language plpgsql security definer
set search_path = public
as $$
declare
  v_autor  text := coalesce((select nullif(p.email,'') from public.perfiles p where p.id = auth.uid()), auth.jwt()->>'email', '');
  v_motivo text := nullif(btrim(coalesce(p_motivo,'')),'');
  r        public.compras_pagos;
  v_out    public.compras_pagos_anulados;
begin
  if not public.tiene_sector('compras'::public.sector_portal) then
    raise exception 'Sin acceso al sector Compras';
  end if;
  if not public.compras_puede_eliminar_pagos() then
    raise exception 'No tenés permiso para eliminar pagos';
  end if;
  if v_motivo is null then
    raise exception 'Falta el motivo de la anulación';
  end if;

  select * into r from public.compras_pagos where id = p_id for update;
  if not found then raise exception 'No existe el pago %', p_id; end if;

  insert into public.compras_pagos_anulados
    (pago_id, op_numero, og_id, og_numero, fecha_pago, moneda_pago, importe_pago, asiento_num, datos, motivo, anulado_por)
  values
    (r.id, r.op_numero::text, r.og_id, r.numero::text, r.fecha, r.moneda_pago, r.importe_pago,
     nullif(btrim(coalesce(r.asiento_num::text,'')),''), to_jsonb(r), v_motivo, v_autor)
  returning * into v_out;

  delete from public.compras_pagos where id = p_id;
  return v_out;
end;
$$;
revoke all on function public.compras_anular_pago(bigint, text) from public, anon;
grant execute on function public.compras_anular_pago(bigint, text) to authenticated;

commit;

-- Control (informativo, no cambia nada): cómo se numeran las OP.
-- Si column_default es un nextval(...) (secuencia), el N° de una OP anulada NO se vuelve a usar.
-- Si está vacío, el N° lo pone un trigger u otra lógica: avisale a Claude qué sale acá.
select column_name, column_default
  from information_schema.columns
 where table_schema = 'public' and table_name = 'compras_pagos' and column_name = 'op_numero';
