-- =====================================================================
-- COSTEO_NEW en OGs (oct 2026)
-- Proyecto Supabase: wcpkpwxhqdcdljfwzcmy. Correr A MANO en el SQL Editor,
-- ANTES de publicar el index.html que usa la columna costeo_new.
--
-- Qué hace:
--   1) Agrega compras_ogs.costeo_new (sección del costeo de la que sale la compra).
--   2) Reclasifica las OG existentes: costeo_new = equivalente del COSTEO viejo.
--      El COSTEO viejo (columna costeo) NO se toca: queda como histórico.
-- No crea tablas ni cambia RLS (compras_ogs ya está gateada por tiene_sector('compras')).
-- Reversible: alter table public.compras_ogs drop column costeo_new;
-- =====================================================================

-- 0) (opcional) Vista previa: cuántas OG hay por COSTEO viejo y a qué irían
select o.costeo, m.nuevo, count(*) as ogs
from public.compras_ogs o
left join (values
  ('GC ESTRUCT MODULAR','Estructura Modular'), ('GC PANELES','Estructura Modular'),
  ('GC HIERROS','Acero / Hierro'), ('GC HERRERIA','Acero / Hierro'), ('GC CHAPA','Acero / Hierro'),
  ('GC AISLACION','Aislacion / Revestimiento'), ('GC REVESTIMIENTO','Aislacion / Revestimiento'), ('GC OBRA SECA','Aislacion / Revestimiento'),
  ('GC PISO','Piso'),
  ('GC CARPINTERIA','Aberturas'), ('GC VIDRIOS Y ESPEJOS','Aberturas'), ('GC HERRAJES','Aberturas'),
  ('GC INST ELECTRICA','Instalacion Electrica'), ('GC ART. ILUMINACION','Instalacion Electrica'),
  ('GC ARENADO Y PINTURA','Pintura'),
  ('GC INST SANITARIA','Sanitario'), ('GC SANITARIOS','Sanitario'), ('GC ART SANITARIOS','Sanitario'), ('GC INST GAS','Sanitario'),
  ('GC ELECTRODOMESTICOS','Cocina'),
  ('GC EQUIPAMIENTO','Equipamiento'),
  ('GC AMOBLAMIENTO','Mobiliario'),
  ('GC OBRA CIVIL','Obra Civil'), ('GC CORRALON','Obra Civil'),
  ('GC LOGISTICA','Logistica & Montaje'), ('GC MONTAJE','Logistica & Montaje'),
  ('GC INST TERMOMECANICA','Climatizacion')
) as m(viejo, nuevo)
  on upper(regexp_replace(trim(o.costeo), '\s+', ' ', 'g')) = m.viejo
group by 1,2 order by 3 desc;

begin;

-- 1) Columna nueva
alter table public.compras_ogs add column if not exists costeo_new text;

-- 2) Reclasificación (solo las que todavía no tienen costeo_new)
update public.compras_ogs o
set costeo_new = m.nuevo
from (values
  ('GC ESTRUCT MODULAR','Estructura Modular'), ('GC PANELES','Estructura Modular'),
  ('GC HIERROS','Acero / Hierro'), ('GC HERRERIA','Acero / Hierro'), ('GC CHAPA','Acero / Hierro'),
  ('GC AISLACION','Aislacion / Revestimiento'), ('GC REVESTIMIENTO','Aislacion / Revestimiento'), ('GC OBRA SECA','Aislacion / Revestimiento'),
  ('GC PISO','Piso'),
  ('GC CARPINTERIA','Aberturas'), ('GC VIDRIOS Y ESPEJOS','Aberturas'), ('GC HERRAJES','Aberturas'),
  ('GC INST ELECTRICA','Instalacion Electrica'), ('GC ART. ILUMINACION','Instalacion Electrica'),
  ('GC ARENADO Y PINTURA','Pintura'),
  ('GC INST SANITARIA','Sanitario'), ('GC SANITARIOS','Sanitario'), ('GC ART SANITARIOS','Sanitario'), ('GC INST GAS','Sanitario'),
  ('GC ELECTRODOMESTICOS','Cocina'),
  ('GC EQUIPAMIENTO','Equipamiento'),
  ('GC AMOBLAMIENTO','Mobiliario'),
  ('GC OBRA CIVIL','Obra Civil'), ('GC CORRALON','Obra Civil'),
  ('GC LOGISTICA','Logistica & Montaje'), ('GC MONTAJE','Logistica & Montaje'),
  ('GC INST TERMOMECANICA','Climatizacion')
) as m(viejo, nuevo)
where upper(regexp_replace(trim(o.costeo), '\s+', ' ', 'g')) = m.viejo
  and (o.costeo_new is null or o.costeo_new = '');

commit;

-- 3) Control: OG con COSTEO viejo que quedaron SIN equivalente (HONORARIOS, SERVICIOS,
--    ASERRADERO, POSVENTA u otros valores raros). Hay que definirlas a mano.
select costeo, count(*) as ogs
from public.compras_ogs
where coalesce(costeo,'') not in ('', 'No Aplica')
  and coalesce(costeo_new,'') = ''
group by 1 order by 2 desc;
