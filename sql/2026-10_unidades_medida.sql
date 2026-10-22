-- =====================================================================
-- Unidades de medida (diccionario) (oct 2026)
-- Proyecto Supabase: wcpkpwxhqdcdljfwzcmy. Correr A MANO en el SQL Editor,
-- ANTES de publicar el index.html que usa esta tabla.
--
-- Qué hace (aditivo):
--   Crea compras_unidades_medida con las 16 unidades del reporte de Tango "Unidades de medida"
--   (Código, Descripción, Cantidad de decimales, Sigla, Tipo de unidad). Todas arrancan habilitadas;
--   en la app (Pañol → Diccionario pañol → Unidades de medida) se pueden inhabilitar, editar o importar de nuevo desde Tango.
--   RLS: solo authenticated con public.tiene_sector('compras'::public.sector_portal). Nada para anon.
--
-- Reversible: drop table public.compras_unidades_medida;
-- =====================================================================
begin;

create table if not exists public.compras_unidades_medida (
  id           bigint generated always as identity primary key,
  codigo       text not null,
  descripcion  text,
  decimales    integer,
  sigla        text,
  tipo         text,
  activo       boolean not null default true,
  creado_en    timestamptz not null default now(),
  creado_por   text
);
create unique index if not exists compras_unidades_medida_codigo_uq on public.compras_unidades_medida (upper(btrim(codigo)));

insert into public.compras_unidades_medida (codigo, descripcion, decimales, sigla, tipo, creado_por) values
  ('AÑOS','Años',0,'AS','Tiempo','sql'),
  ('CAJA','CAJA',2,'CAJ',null,'sql'),
  ('DIAS','DIAS',2,'DI','Tiempo','sql'),
  ('HS','HORAS',2,'HS','Tiempo','sql'),
  ('KG','KILOGRAMOS',2,'KG','Masa','sql'),
  ('LT','LITRO',2,'LT','Volumen','sql'),
  ('M2','METROS CUADRADOS',2,'M2','Superficie','sql'),
  ('M3','METROS CUBICOS',2,'M3','Volumen','sql'),
  ('MESES','Meses',0,'MS','Tiempo','sql'),
  ('ML','METRO LINEAL',2,'ML','Longitud','sql'),
  ('P2','PIES CUADRADOS',2,'P2','Superficie','sql'),
  ('SINUNIDAD','Sin unidad de medida asignada',2,'***',null,'sql'),
  ('TIRA','TIRA',4,'TIR',null,'sql'),
  ('TN','TONELADA',2,'TN','Masa','sql'),
  ('UNI','UNIDAD',4,'UNI',null,'sql'),
  ('UNI3','UNIDAD 3D',3,'UN3',null,'sql')
on conflict do nothing;

alter table public.compras_unidades_medida enable row level security;
revoke all on public.compras_unidades_medida from anon;
grant select, insert, update, delete on public.compras_unidades_medida to authenticated;
drop policy if exists compras_unidades_medida_all on public.compras_unidades_medida;
create policy compras_unidades_medida_all on public.compras_unidades_medida for all to authenticated
  using (public.tiene_sector('compras'::public.sector_portal)) with check (public.tiene_sector('compras'::public.sector_portal));

commit;
