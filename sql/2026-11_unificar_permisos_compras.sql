-- Unificar permisos de Compras con el modelo del portal (perfiles_sector),
-- para administrarse desde admin.html como el resto de las apps.
--
-- Diseño aprobado por Pablo (conversación de Claude Code, nov/2026):
--   - es_admin             -> rol "Admin" del sector compras (perfiles_sector.cargo),
--                             el mismo selector que ya usan todas las apps.
--   - es_comprador         -> 'compras' y 'seguimiento' en permisos.editar
--   - es_tesorero          -> 'tesoreria' en permisos.editar
--   - es_panol             -> 'panol' en permisos.editar
--   - ve_confidencial      -> permisos.ve_confidencial (flag suelto, no hay pestaña:
--     es_certificador      -> permisos.es_certificador  mismo mecanismo que
--     puede_cargar_asiento -> permisos.puede_cargar_asiento  "Edita costos" en LABO
--     puede_eliminar_pagos -> permisos.puede_eliminar_pagos  o ve_sueldos en Planif.)
--   - es_finanzas          -> no se migra: no lo usa ni la app ni ningún RLS (flag
--                             muerto, confirmado por grep). Se puede eliminar la
--                             columna en una limpieza aparte.
--
-- NO se ejecuta solo: lo corre Pablo a mano en el SQL Editor de Supabase,
-- después de revisar. Los cambios de index.html (loadRole) y admin.html
-- (checkboxes de los 4 flags sueltos) van en el mismo PR, pero no dependen de
-- que este SQL ya haya corrido para poder revisarse.
--
-- IMPORTANTE: esto NO toca ninguna política de RLS existente. Las 8 políticas
-- que llaman a compras_flag(...) (compras_caja, compras_pagos, compras_cuentas,
-- compras_cuentas_contables, compras_aux_opciones, compras_aux_tipos,
-- compras_tipos_aux, compras_idx_sueldos) siguen intactas: compras_flag()
-- se REDEFINE con el mismo nombre y firma, así que no hay que tocarlas.
--
-- IMPORTANTE: compras_usuarios_autorizados NO se borra en esta migración.
-- Sigue siendo la fuente del campo `nombre` (formato "Apellido, Nombre"), que
-- es lo que compara el matching de comprador/certificador contra las OG ya
-- cargadas. El `perfiles.nombre` del portal en muchos casos es solo el
-- usuario de mail (ej. "agustinarodriguez"), no sirve para ese matching —
-- verificado contra los datos reales antes de proponer esto.

begin;

-- ========================================================================
-- 1) Volcar los flags de compras_usuarios_autorizados a perfiles_sector
--    (sector='compras'), para cada email que YA tiene perfil en el portal.
--
--    ver: todas las secciones (hoy Compras no filtra por ver, así que no hay
--    forma de restringir sin cambiar la app primero — nadie pierde acceso).
--
--    OJO — esto PISA el cargo/permisos que ya tuviera cada usuario en
--    perfiles_sector para sector='compras'. Es intencional: verificado contra
--    producción, lo que hay ahí hoy es de relleno (cargo='miembro' —ni
--    siquiera uno de los 3 roles que ofrece ADMIN para Compras— y
--    permisos={}), no reflejan el acceso real de nadie: la app nunca los leyó.
--
--    alexiscarranza@4housing.com.ar (sin perfil en el portal) y
--    administracion@4housing.com.ar son la misma persona (confirmado por
--    Pablo) usando dos mails distintos; administracion@ ya tiene todos los
--    flags que tenía alexiscarranza@ y además comprador/certificador, así que
--    no se pierde nada al no migrar la fila sin perfil.

with datos as (
  select
    u.email,
    u.es_admin, u.es_comprador, u.es_tesorero, u.es_certificador,
    u.ve_confidencial, u.puede_cargar_asiento, u.puede_eliminar_pagos, u.es_panol,
    array['compras','seguimiento','tesoreria','solicitudes','deposito','panol',
          'mantenimiento','logistica','diccionarios','indices','precios']::text[] as todas_secciones,
    (
      (case when u.es_comprador then array['compras','seguimiento'] else array[]::text[] end) ||
      (case when u.es_tesorero  then array['tesoreria']             else array[]::text[] end) ||
      (case when u.es_panol     then array['panol']                else array[]::text[] end)
    ) as editar_calc
  from compras_usuarios_autorizados u
),
mapeado as (
  select
    p.id as perfil_id,
    d.todas_secciones as ver,
    d.editar_calc as editar,
    case
      when d.es_admin then 'admin'
      when array_length(d.editar_calc, 1) > 0 then 'editor'
      else 'lector'
    end as cargo,
    jsonb_strip_nulls(jsonb_build_object(
      'ver',  to_jsonb(d.todas_secciones),
      'editar', to_jsonb(d.editar_calc),
      'es_certificador',      case when d.es_certificador then true else null end,
      've_confidencial',      case when d.ve_confidencial then true else null end,
      'puede_cargar_asiento', case when d.puede_cargar_asiento then true else null end,
      'puede_eliminar_pagos', case when d.puede_eliminar_pagos then true else null end
    )) as permisos,
    d.email
  from datos d
  join auth.users au on lower(au.email) = lower(d.email)
  join perfiles p on p.id = au.id
)
insert into perfiles_sector (perfil_id, sector, cargo, permisos)
select perfil_id, 'compras', cargo, permisos from mapeado
on conflict (perfil_id, sector) do update
  set cargo = excluded.cargo, permisos = excluded.permisos;

-- Reporte de verificación: emails de compras_usuarios_autorizados que NO
-- tienen perfil en el portal (no se migraron, quedan sin fila en
-- perfiles_sector). Esperado: alexiscarranza@4housing.com.ar (duplicado de
-- administracion@, ver nota arriba) y los 4 emails ".SIN-LOGIN" (gente que
-- nunca entró a la app ella misma — certificadores/compradores históricos
-- solo de nombre en OGs viejas). Si aparece alguien más acá, falta darlo de
-- alta en el portal antes de confiar en esta migración para esa persona.
select u.email, u.nombre
from compras_usuarios_autorizados u
where not exists (
  select 1 from auth.users au join perfiles p on p.id = au.id
  where lower(au.email) = lower(u.email)
);

-- ========================================================================
-- 2) Redefinir compras_flag(): MISMO nombre y firma, ahora lee
--    perfiles_sector en vez de compras_usuarios_autorizados. Replica EXACTO
--    el comportamiento de hoy (sin OR con admin acá adentro — eso ya lo hace
--    cada punto de la app con el patrón `ROLE.admin || ROLE.X`, igual que
--    ahora; esta función solo cambia DE DÓNDE sale el dato, no la lógica).

create or replace function public.compras_flag(p_flag text)
returns boolean
language sql
stable
security definer
set search_path to 'public'
as $function$
  select coalesce((
    select case p_flag
             when 'admin'        then (ps.cargo = 'admin')
             when 'confidencial' then coalesce((ps.permisos->>'ve_confidencial')::boolean, false)
             when 'certificador' then coalesce((ps.permisos->>'es_certificador')::boolean, false)
             when 'tesorero'     then coalesce((ps.permisos->'editar') ? 'tesoreria', false)
             when 'comprador'    then coalesce((ps.permisos->'editar') ? 'compras', false)
             else false
           end
      from public.perfiles_sector ps
     where ps.perfil_id = auth.uid()
       and ps.sector = 'compras'
  ), false);
$function$;

commit;

-- ========================================================================
-- Pendiente (NO en este archivo, se hace en una limpieza aparte, más adelante
-- y con más margen de que no quede nadie afuera por error):
--   - Una vez confirmado que todo sigue andando igual un tiempo, eliminar las
--     columnas booleanas de compras_usuarios_autorizados (dejar solo
--     email/nombre, que sigue haciendo falta) y la columna es_finanzas.
--   - Dar de baja la fila de alexiscarranza@4housing.com.ar en
--     compras_usuarios_autorizados (duplicado de administracion@), conservando
--     su `nombre` si hace falta para algún matching histórico.
