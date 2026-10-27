-- =====================================================================
-- OG 2086 (Terrón e Hijos) cargada SIN artículo + diagnóstico de otros casos (oct 2026)
-- Proyecto Supabase: wcpkpwxhqdcdljfwzcmy. Correr A MANO en el SQL Editor,
-- paso por paso. PUEDE IR ANTES O DESPUÉS del index.html (no agrega tablas/columnas).
--
-- SUPUESTOS (no verificados contra la base real — revisá los resultados del PASO 1):
--   * compras_ogs.items es jsonb (lista de renglones) y compras_ogs.numero se compara como texto.
--   * compras_og_certificados tiene og_id, pct y avances (jsonb, {"0": 100} = renglón 1 al 100%).
--   * compras_articulos tiene codigo y descripcion.
-- =====================================================================

-- ---------------------------------------------------------------------
-- PASO 1 — DIAGNÓSTICO (solo lectura): ¿hay más OGs así?
-- 1a) OGs sin ningún renglón, con cuántos certificados y pagos tienen.
-- ---------------------------------------------------------------------
select o.id, o.numero, o.proveedor, o.monto_total, o.fecha,
       (select count(*) from compras_og_certificados c where c.og_id = o.id) as certificados,
       (select count(*) from compras_pagos p where p.og_id = o.id)           as pagos
  from compras_ogs o
 where coalesce(jsonb_array_length(o.items), 0) = 0
 order by o.numero::int;

-- 1b) OGs con renglones, pero algún renglón sin artículo.
select o.id, o.numero, o.proveedor, i.ord as renglon, i.it->>'hito' as detalle, i.it->>'precio_unit' as precio
  from compras_ogs o,
       jsonb_array_elements(o.items) with ordinality as i(it, ord)
 where coalesce(btrim(i.it->>'cod_art'), '') = ''
   and coalesce(btrim(i.it->>'articulo'), '') = ''
 order by o.numero::int, i.ord;

-- 1c) El artículo para la 2086 (el código arranca con GCCHA0700; tiene que dar 1 sola fila).
select codigo, descripcion from compras_articulos where codigo like 'GCCHA0700%';

-- ---------------------------------------------------------------------
-- PASO 2 — CORRECCIÓN DE LA OG 2086 (EXCEPCIÓN, una sola vez).
-- Aborta sin cambiar nada si: la 2086 ya tiene renglones, no hay exactamente 1 artículo GCCHA0700%,
-- o la OG no tiene exactamente 1 certificado.
-- ---------------------------------------------------------------------
begin;
do $$
declare
  v_og   record;
  v_cod  text;
  v_desc text;
  v_n    int;
begin
  select * into v_og from compras_ogs where numero::text = '2086';
  if not found then raise exception 'No existe la OG 2086'; end if;
  if coalesce(jsonb_array_length(v_og.items), 0) > 0 then raise exception 'La OG 2086 ya tiene renglones: no se toca'; end if;

  select count(*) into v_n from compras_articulos where codigo like 'GCCHA0700%';
  if v_n <> 1 then raise exception 'Se esperaba 1 artículo GCCHA0700%%, hay %. Completá el código exacto a mano.', v_n; end if;
  select codigo, descripcion into v_cod, v_desc from compras_articulos where codigo like 'GCCHA0700%';

  select count(*) into v_n from compras_og_certificados where og_id = v_og.id;
  if v_n <> 1 then raise exception 'Se esperaba 1 certificado en la OG 2086, hay %', v_n; end if;

  -- Renglón único por el monto total (la OG sin renglones se certificaba por monto_total).
  -- Ojo: precio_unit = monto_total sin bonificación de OG; si la 2086 tuviera bonif_pct <> 0, revisar a mano.
  if coalesce(v_og.bonif_pct, 0) <> 0 then raise exception 'La OG 2086 tiene bonificación: revisar a mano'; end if;

  update compras_ogs
     set items = jsonb_build_array(jsonb_build_object(
           'cod_art', v_cod, 'articulo', v_desc,
           'hito', 'CHAPA NEGRA LISA LAC CALIDAD A36 1500mm x 3000mm x Esp 9,5',
           'cert_modo', 'pct', 'centro_costos', coalesce(v_og.clasif_og, ''), 'modulos', '[]'::jsonb,
           'cant', 1, 'um', 'UNI', 'precio_unit', v_og.monto_total,
           'fecha_entrega', '', 'deposito', '', 'bonif_pct', 0, 'imp', '{}'::jsonb))
   where id = v_og.id;

  -- El certificado existente (a nivel OG, pct) pasa a avance por renglón: mismo porcentaje en el renglón 1.
  update compras_og_certificados
     set avances = jsonb_build_object('0', coalesce(pct, 0))
   where og_id = v_og.id;
end $$;

-- Verificación: tiene que mostrar 1 renglón y avances {"0": 100}.
select o.numero, o.monto_total, o.items, c.numero as cert, c.pct, c.avances
  from compras_ogs o join compras_og_certificados c on c.og_id = o.id
 where o.numero::text = '2086';
-- Si se ve bien: commit;   Si no: rollback;
