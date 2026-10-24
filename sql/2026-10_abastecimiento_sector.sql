-- =====================================================================
-- Abastecimiento (ex Pañol): sector por renglón y permiso de Depósito (oct 2026)
-- Proyecto Supabase: wcpkpwxhqdcdljfwzcmy. Correr A MANO en el SQL Editor,
-- DESPUÉS de sql/2026-10_panol_solicitudes.sql y sql/2026-10_panol_kits.sql, y ANTES de publicar el index.html que usa estas columnas.
--
-- Qué hace (aditivo):
--   1) compras_panol_solicitud_items.sector: 'Pañol' o 'Depósito'. Cada renglón de una OT lo maneja Pañol (Iván y Nicolás Komina) o Depósito (Nicolás Rivero).
--      La app lo sugiere por el código del artículo: GCFER, GCLIM, GCEPP, GCEQU, GCHRR o GCSPM => Pañol; cualquier otro => Depósito (sin código => Pañol).
--      Los renglones que ya existen se completan con esa misma regla.
--   2) compras_usuarios_autorizados.es_deposito: permiso para preparar y entregar los renglones de Depósito. Se asigna con el UPDATE comentado al final.
-- RLS: no cambia (las tablas ya tienen la compuerta de sector compras). El permiso se controla en la app.
--
-- Reversible:
--   alter table public.compras_panol_solicitud_items drop column sector;
--   alter table public.compras_usuarios_autorizados drop column es_deposito;
-- =====================================================================
begin;

alter table public.compras_panol_solicitud_items
  add column if not exists sector text check (sector in ('Pañol','Depósito'));

update public.compras_panol_solicitud_items
   set sector = case
                  when cod_articulo is null or btrim(cod_articulo) = '' then 'Pañol'
                  when upper(left(btrim(cod_articulo), 5)) in ('GCFER','GCLIM','GCEPP','GCEQU','GCHRR','GCSPM') then 'Pañol'
                  else 'Depósito'
                end
 where sector is null;

alter table public.compras_usuarios_autorizados
  add column if not exists es_deposito boolean not null default false;

commit;

-- Después de correr lo de arriba, asignar el permiso a Nicolás Rivero (si ese mail está en compras_usuarios_autorizados):
-- update public.compras_usuarios_autorizados set es_deposito = true where lower(email) = 'depositos@4housing.com.ar';
-- select nombre, email, es_panol, es_deposito from public.compras_usuarios_autorizados where es_panol or es_deposito;
