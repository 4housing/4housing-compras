-- PROPUESTA — NO EJECUTAR TODAVÍA. Para revisión de Pablo/Mica antes de correr nada.
--
-- Objetivo: que Compras deje de tener su propio sistema de roles
-- (compras_usuarios_autorizados) y use el mismo modelo que el resto de las
-- apps del portal (perfiles_sector.permisos), administrable desde admin.html.
--
-- Ver la explicación completa (qué cambia, qué riesgos hay, qué preguntas
-- quedan abiertas) en la conversación de Claude Code. Este archivo es solo
-- el borrador de SQL; los cambios de index.html y admin.html van aparte,
-- después de que se apruebe este diseño.
--
-- IMPORTANTE: esto NO toca ninguna política de RLS existente. Las 8 políticas
-- que llaman a compras_flag(...) (compras_caja, compras_pagos, compras_cuentas,
-- compras_cuentas_contables, compras_aux_opciones, compras_aux_tipos,
-- compras_tipos_aux, compras_idx_sueldos) siguen intactas: compras_flag()
-- se REDEFINE con el mismo nombre y firma, así que no hay que tocarlas.
--
-- IMPORTANTE: compras_usuarios_autorizados NO se borra en esta migración.
-- Sigue siendo la fuente del campo `nombre` (formato "Apellido, Nombre") que
-- usa el matching de comprador/certificador contra las OG viejas — ver nota
-- más abajo, es un hallazgo real de los datos de producción.

begin;

-- ========================================================================
-- 1) Volcar los flags de compras_usuarios_autorizados a perfiles_sector
--    (sector='compras'), para cada email que YA tiene perfil en el portal.
--
--    Mapeo elegido:
--      es_admin             -> permisos.es_admin              (flag propio)
--      ve_confidencial      -> permisos.ve_confidencial       (flag propio)
--      es_certificador      -> permisos.es_certificador       (flag propio)
--      puede_cargar_asiento -> permisos.puede_cargar_asiento  (flag propio)
--      puede_eliminar_pagos -> permisos.puede_eliminar_pagos  (flag propio)
--      es_comprador         -> 'compras' y 'seguimiento' en editar
--      es_tesorero          -> 'tesoreria' en editar
--      es_panol             -> 'panol' en editar
--      es_finanzas          -> (no se migra: no lo usa ni la app ni ningún RLS,
--                                es un flag muerto; se puede confirmar y
--                                eliminar la columna en una limpieza aparte)
--
--    ver: todas las secciones (hoy Compras no filtra por ver, así que no hay
--    forma de restringir sin cambiar la app primero — nadie pierde acceso).
--
--    cargo: 'admin' si es_admin; si no, 'editor' si algo quedó en editar;
--    si no, 'lector'. (Dato administrativo nomás: hoy ningún gate de Compras
--    lee el cargo directamente, solo permisos — pero así queda consistente
--    con cómo se ve en la pantalla de ADMIN.)
--
--    OJO — esto PISA el cargo/permisos que ya tuviera cada usuario en
--    perfiles_sector para sector='compras'. Es intencional: los datos que hay
--    ahí hoy son de relleno (se cargaron cuando se habilitó el sector, pero
--    la app de Compras nunca los leyó), así que no hay nada real que perder.
--    Verificado contra producción: la mayoría tiene cargo='miembro' (un valor
--    que ni siquiera es uno de los 3 roles que ofrece la pantalla de ADMIN
--    para Compras) y permisos={} — no reflejan accesos reales de nadie.

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
      'es_admin',             case when d.es_admin then true else null end,
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
-- perfiles_sector). Revisar a mano: ¿son gente sin login real (certificadores
-- históricos que nunca usaron la app, p.ej. los que tienen ".SIN-LOGIN" en el
-- email) o faltó darles de alta en el portal?
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
             when 'admin'        then coalesce((ps.permisos->>'es_admin')::boolean, false)
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
--   - Confirmar con Pablo/Mica los 4 emails con ".SIN-LOGIN" y
--     alexiscarranza@4housing.com.ar (no tiene perfil — ¿duplicado de
--     administracion@4housing.com.ar, que sí lo tiene?).
--   - Una vez confirmado que todo sigue andando igual un tiempo, eliminar las
--     columnas booleanas de compras_usuarios_autorizados (dejar solo
--     email/nombre, que sigue haciendo falta — ver nota abajo) y dar de baja
--     compras_flag() en favor de leer perfiles_sector directo donde haga falta.
--   - Confirmar y eliminar la columna es_finanzas (no se usa en ningún lado).
