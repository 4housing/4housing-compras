-- =====================================================================
-- Pañol · cierre de mes con precios congelados (oct 2026)
-- Proyecto Supabase: wcpkpwxhqdcdljfwzcmy. Correr A MANO en el SQL Editor,
-- ANTES de publicar el index.html que usa esta tabla.
--
-- Qué hace (aditivo):
--   1) Crea compras_panol_cierres: un renglón por período (aaaamm) con su estado Abierto/Cerrado, quién y cuándo
--      lo cerró y un historial (cada cierre / reapertura con usuario, fecha y hora, comentario y resumen).
--      Un período sin renglón se considera Abierto.
--   2) Trigger sobre compras_panol_egresos: en un período CERRADO no se puede insertar, modificar ni eliminar nada
--      (el precio queda congelado aunque alguien salte la pantalla). La única excepción es marcar una erogación
--      como exportada a Tango (columnas exportado / exportado_en). Para tocar un mes cerrado hay que reabrirlo.
--   RLS de la tabla nueva: solo authenticated con public.tiene_sector('compras'::public.sector_portal). Nada para anon.
--   OJO: quién puede cerrar y reabrir (administradores) se controla en la app, no en la base: cualquier usuario del
--   sector compras podría escribir en esta tabla por API. Si hace falta, se endurece después con compras_flag('es_admin').
--
-- Reversible:
--   drop trigger compras_panol_egresos_cierre_guard on public.compras_panol_egresos;
--   drop function public.compras_panol_egresos_cierre_guard();
--   drop table public.compras_panol_cierres;
-- =====================================================================

begin;

create table if not exists public.compras_panol_cierres (
  periodo     integer primary key,                 -- aaaamm (ej. 202610)
  estado      text not null default 'Abierto' check (estado in ('Abierto','Cerrado')),
  cerrado_en  timestamptz,
  cerrado_por text,
  comentario  text,
  historial   jsonb not null default '[]'::jsonb  -- [{accion, fecha, por, comentario, resumen}]
);

alter table public.compras_panol_cierres enable row level security;
revoke all on public.compras_panol_cierres from anon;
grant select, insert, update on public.compras_panol_cierres to authenticated;
drop policy if exists compras_panol_cierres_sel on public.compras_panol_cierres;
drop policy if exists compras_panol_cierres_ins on public.compras_panol_cierres;
drop policy if exists compras_panol_cierres_upd on public.compras_panol_cierres;
create policy compras_panol_cierres_sel on public.compras_panol_cierres for select to authenticated using (public.tiene_sector('compras'::public.sector_portal));
create policy compras_panol_cierres_ins on public.compras_panol_cierres for insert to authenticated with check (public.tiene_sector('compras'::public.sector_portal));
create policy compras_panol_cierres_upd on public.compras_panol_cierres for update to authenticated using (public.tiene_sector('compras'::public.sector_portal)) with check (public.tiene_sector('compras'::public.sector_portal));

-- Candado de período cerrado
create or replace function public.compras_panol_egresos_cierre_guard()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  p_old   integer;
  p_new   integer;
  cerrado integer;      -- período cerrado involucrado (null si ninguno)
begin
  if tg_op = 'INSERT' then
    p_new := new.periodo;
  elsif tg_op = 'DELETE' then
    p_old := old.periodo;
  else
    p_old := old.periodo;
    p_new := new.periodo;
  end if;

  select c.periodo into cerrado from public.compras_panol_cierres c where c.estado = 'Cerrado' and c.periodo in (p_old, p_new) limit 1;

  if cerrado is not null then
    -- único cambio permitido en un período cerrado: marcar como exportado a Tango (nada más cambia)
    if tg_op = 'UPDATE' and p_old = p_new
       and (to_jsonb(new) - 'exportado' - 'exportado_en') = (to_jsonb(old) - 'exportado' - 'exportado_en') then
      return new;
    end if;
    raise exception 'El período % está cerrado: no se puede insertar, modificar ni eliminar erogaciones (un administrador puede reabrirlo en Pañol > Cierres).', cerrado;
  end if;

  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;

drop trigger if exists compras_panol_egresos_cierre_guard on public.compras_panol_egresos;
create trigger compras_panol_egresos_cierre_guard
  before insert or update or delete on public.compras_panol_egresos
  for each row execute function public.compras_panol_egresos_cierre_guard();

commit;
