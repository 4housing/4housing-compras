-- Diagnóstico (SOLO LECTURA): renglones de OG con centro_costos vacío.
-- Supuesto (no verificado): compras_ogs.items es jsonb y cada renglón guarda 'centro_costos'.
-- Los renglones vacíos se completan con la clasificación de la OG (clasif_og) al guardar la OG desde la app.
select o.numero, o.anulada, o.clasif_og, o.proveedor, i.ord as renglon,
       i.it->>'cod_art' as cod_art, i.it->>'articulo' as articulo
  from compras_ogs o,
       jsonb_array_elements(o.items) with ordinality as i(it, ord)
 where coalesce(btrim(i.it->>'centro_costos'), '') = ''
 order by o.numero::int, i.ord;
