-- =====================================================================
-- Proveedores · origen (Tango / Manual) y eliminar proveedores cargados a mano (oct 2026)
-- Proyecto Supabase: wcpkpwxhqdcdljfwzcmy. Correr A MANO en el SQL Editor ANTES de publicar
-- el index.html que trae la columna "Origen" y el botón "Eliminar" en Diccionarios > Proveedores.
--
-- Pedido de Micaela: distinguir lo cargado a mano de lo que viene de Tango, y poder eliminar un
-- proveedor duplicado. Reglas: cualquiera del sector puede eliminar, pero SOLO los cargados a mano
-- y SOLO si nunca se usaron en una OG (tampoco si están en una solicitud de pago).
--
-- Qué cambia:
--   1) compras_proveedores: columnas origen ('tango' | 'manual'), creado_por, creado_en.
--      Los proveedores que ya existen quedan con origen vacío ("Sin dato"): la próxima vez que
--      se use "Sincronizar con Tango", la app marca como Tango a todos los que están en el export
--      (y opcionalmente como Manual a los que no están). No se adivina nada acá.
--   2) Función compras_eliminar_proveedor(p_codigo): valida las reglas y borra.
--   3) Policy RESTRICTIVA de DELETE en compras_proveedores con using(false): nadie borra directo,
--      solo a través de la función. (Hoy la app no borra proveedores por ningún otro lado.)
--   4) Marca como Manual los proveedores que se sabe que se cargaron a mano. COMPLETAR el/los
--      código(s) antes de correr (no se guardan en el repo porque es público).
--
-- Reversible:
--   drop policy if exists compras_proveedores_del_solo_funcion on public.compras_proveedores;
--   drop function if exists public.compras_eliminar_proveedor(text);
--   alter table public.compras_proveedores drop column if exists origen,
--     drop column if exists creado_por, drop column if exists creado_en;
-- =====================================================================

begin;

-- 1) Origen y alta
alter table public.compras_proveedores
  add column if not exists origen     text,
  add column if not exists creado_por text,
  add column if not exists creado_en  timestamptz;

alter table public.compras_proveedores
  alter column creado_en set default now();   -- solo para altas nuevas; los existentes quedan vacíos

alter table public.compras_proveedores drop constraint if exists compras_proveedores_origen_chk;
alter table public.compras_proveedores
  add constraint compras_proveedores_origen_chk check (origen is null or origen in ('tango','manual'));

-- 2) Eliminar (solo manuales y sin uso)
create or replace function public.compras_eliminar_proveedor(p_codigo text)
returns text
language plpgsql security definer
set search_path = public
as $$
declare
  v_cod    text := btrim(coalesce(p_codigo,''));
  v_origen text;
  v_n_og   int;
  v_n_sp   int;
begin
  if not public.tiene_sector('compras'::public.sector_portal) then
    raise exception 'Sin acceso al sector Compras';
  end if;
  if v_cod = '' then raise exception 'Falta el código del proveedor'; end if;

  select origen into v_origen from public.compras_proveedores where codigo = v_cod for update;
  if not found then raise exception 'No existe el proveedor %', v_cod; end if;
  if coalesce(v_origen,'') <> 'manual' then
    raise exception 'Solo se pueden eliminar proveedores cargados a mano (% es %)', v_cod, coalesce(v_origen,'sin dato de origen');
  end if;

  select count(*) into v_n_og from public.compras_ogs
   where upper(btrim(coalesce(proveedor_cod,''))) = upper(v_cod);
  if v_n_og > 0 then
    raise exception 'No se puede eliminar %: se usó en % OG', v_cod, v_n_og;
  end if;

  select count(*) into v_n_sp from public.compras_solicitudes_pago
   where upper(btrim(coalesce(proveedor_cod,''))) = upper(v_cod);
  if v_n_sp > 0 then
    raise exception 'No se puede eliminar %: está en % solicitud(es) de pago', v_cod, v_n_sp;
  end if;

  delete from public.compras_proveedores where codigo = v_cod;
  return v_cod;
end;
$$;
revoke all on function public.compras_eliminar_proveedor(text) from public, anon;
grant execute on function public.compras_eliminar_proveedor(text) to authenticated;

-- 3) Borrado directo bloqueado (restrictiva = se suma a las policies que ya hay)
drop policy if exists compras_proveedores_del_solo_funcion on public.compras_proveedores;
create policy compras_proveedores_del_solo_funcion on public.compras_proveedores
  as restrictive for delete to authenticated
  using (false);

-- 4) Proveedores que se sabe que son carga manual. COMPLETAR el/los código(s), tal cual figuran.
update public.compras_proveedores
   set origen = 'manual'
 where codigo in ('CODIGO_MANUAL');

commit;

-- Que la API reconozca las columnas nuevas enseguida
notify pgrst, 'reload schema';

-- Control: cuántos quedaron por origen (lo esperable hoy: casi todos "sin dato" y el/los manual(es))
select coalesce(origen,'sin dato') as origen, count(*) from public.compras_proveedores group by 1 order by 1;
