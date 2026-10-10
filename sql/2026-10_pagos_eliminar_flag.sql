-- =====================================================================
-- Tesorería · quién puede ELIMINAR pagos (OP) (oct 2026)
-- Proyecto Supabase: wcpkpwxhqdcdljfwzcmy. Correr A MANO en el SQL Editor, ANTES de publicar
-- el index.html que trae el botón "Eliminar" en Órdenes de pago.
--
-- Pedido de Micaela: eliminar un pago (fila de compras_pagos) lo pueden hacer solo personas
-- puntuales (hoy: Micaela y Gustavo), no todo Tesorero/Admin. Se maneja desde
-- compras_usuarios_autorizados, igual que puede_cargar_asiento.
--
-- Qué cambia:
--   1) Columna nueva compras_usuarios_autorizados.puede_eliminar_pagos (boolean, default false).
--   2) Función compras_puede_eliminar_pagos(): true si el usuario logueado tiene ese flag.
--      Es security definer para poder leer compras_usuarios_autorizados aunque el RLS de esa
--      tabla no le deje leer su fila.
--   3) Policy RESTRICTIVA de DELETE en compras_pagos: además de las policies que ya existen
--      (tiene_sector('compras')), para borrar hay que tener el flag. No toca ni reemplaza las
--      policies existentes de select/insert/update.
--   4) Activa el flag para Micaela y Gustavo (COMPLETAR los mails antes de correr; los mails
--      no se guardan en el repo porque es público).
--
-- Reversible:
--   drop policy if exists compras_pagos_del_solo_flag on public.compras_pagos;
--   drop function if exists public.compras_puede_eliminar_pagos();
--   alter table public.compras_usuarios_autorizados drop column if exists puede_eliminar_pagos;
-- =====================================================================

begin;

-- 1) Flag
alter table public.compras_usuarios_autorizados
  add column if not exists puede_eliminar_pagos boolean not null default false;

-- 2) Chequeo del usuario logueado (por mail del login, igual que usa la app)
create or replace function public.compras_puede_eliminar_pagos()
returns boolean
language sql stable security definer
set search_path = public
as $$
  select exists (
    select 1 from public.compras_usuarios_autorizados u
    where lower(u.email) = lower(coalesce(auth.jwt()->>'email',''))
      and u.puede_eliminar_pagos
  );
$$;
revoke all on function public.compras_puede_eliminar_pagos() from public, anon;
grant execute on function public.compras_puede_eliminar_pagos() to authenticated;

-- 3) Borrar pagos: solo con el flag (restrictiva = se suma a las policies que ya hay)
drop policy if exists compras_pagos_del_solo_flag on public.compras_pagos;
create policy compras_pagos_del_solo_flag on public.compras_pagos
  as restrictive for delete to authenticated
  using (public.compras_puede_eliminar_pagos());

-- 4) Quiénes pueden. COMPLETAR los dos mails (tal cual figuran en compras_usuarios_autorizados).
update public.compras_usuarios_autorizados
   set puede_eliminar_pagos = true
 where lower(email) in (lower('MAIL_DE_MICAELA'), lower('MAIL_DE_GUSTAVO'));

-- Control: tienen que salir exactamente las 2 personas.
select email, nombre, puede_eliminar_pagos
  from public.compras_usuarios_autorizados
 where puede_eliminar_pagos;

commit;
