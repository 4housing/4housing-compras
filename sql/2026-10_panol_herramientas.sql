-- =====================================================================
-- Pañol · Herramientas: pedidos, préstamos y mantenimiento (oct 2026)
-- Proyecto Supabase: wcpkpwxhqdcdljfwzcmy. Correr A MANO en el SQL Editor,
-- ANTES de publicar el index.html que usa esta tabla.
--
-- Qué hace (aditivo, no toca nada existente):
--   Crea compras_panol_herr: una fila por UNIDAD de herramienta (artículo GCHRR…) que se pide, se presta o está en mantenimiento.
--   - Un pedido de 3 atornilladores genera 3 filas 'Solicitada' sin serie; al entregar, Pañol le asigna la SERIE de cada una
--     (la serie es la de compras_series_activas, ej. XA-006-001-2026; el Auxiliar de Tango se deduce por esa serie).
--   - estado: Solicitada -> Prestada -> Devuelta. 'Mantenimiento' = enviada a reparar (desde / hasta estimada). 'Anulada'.
--   - La herramienta no se consume: no genera egreso ni costo.
-- RLS: solo authenticated con public.tiene_sector('compras'::public.sector_portal). Nada para anon.
--   OJO: quién entrega / devuelve (es_panol) se controla en la app; cualquier usuario con el sector compras podría escribir la tabla por API.
--
-- Reversible:  drop table public.compras_panol_herr;
-- =====================================================================
begin;

create table if not exists public.compras_panol_herr (
  id               bigint generated always as identity primary key,
  cod_articulo     text not null,                 -- GCHRR…
  serie            text,                          -- se asigna al entregar (o al mandar a mantenimiento)
  destino_cod      text,
  destino_txt      text,                          -- para dónde va (obra / IF / sector)
  solicitante      text,
  solicitante_email text,
  desde            date not null,
  hasta            date not null,                 -- fecha de devolución prevista (o de regreso estimado si está en mantenimiento)
  estado           text not null default 'Solicitada'
                   check (estado in ('Solicitada','Prestada','Devuelta','Mantenimiento','Anulada')),
  entregado_a      text,                          -- a quién entregó Pañol la herramienta
  entregado_por    text,
  entregado_en     timestamptz,
  devuelto_en      timestamptz,
  comentario       text,                          -- en mantenimiento: motivo / taller
  historial        jsonb not null default '[]'::jsonb,
  creado_en        timestamptz not null default now(),
  creado_por       text,
  actualizado_en   timestamptz,
  actualizado_por  text,
  constraint compras_panol_herr_fechas check (hasta >= desde)
);
create index if not exists compras_panol_herr_art_idx    on public.compras_panol_herr (cod_articulo);
create index if not exists compras_panol_herr_serie_idx  on public.compras_panol_herr (serie);
create index if not exists compras_panol_herr_estado_idx on public.compras_panol_herr (estado);

alter table public.compras_panol_herr enable row level security;
revoke all on public.compras_panol_herr from anon;
grant select, insert, update, delete on public.compras_panol_herr to authenticated;
drop policy if exists compras_panol_herr_all on public.compras_panol_herr;
create policy compras_panol_herr_all on public.compras_panol_herr for all to authenticated
  using (public.tiene_sector('compras'::public.sector_portal)) with check (public.tiene_sector('compras'::public.sector_portal));

commit;
