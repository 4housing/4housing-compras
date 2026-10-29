-- Diagnóstico (SOLO LECTURA) de compras_ogs.clasif_og — OGs que al editarlas
-- van a pedir corregir la Clasificación (OG) desde que es obligatoria.
-- Supuestos (no verificados): compras_ogs.clasif_og guarda solo el código;
-- compras_clasif_renglon tiene la columna codigo. La app guarda el código antes de " — ".

-- A) Cuántas OGs hay por estado de clasificación.
select case
         when coalesce(btrim(o.clasif_og), '') = '' then 'VACÍA'
         when c.codigo is null                      then 'NO EXISTE EN LA LISTA'
         else 'OK'
       end as estado,
       count(*) as ogs
  from compras_ogs o
  left join compras_clasif_renglon c on c.codigo = btrim(o.clasif_og)
 group by 1
 order by 1;

-- B) El detalle de las que hay que corregir (vacías o con código inexistente).
select o.id, o.numero, o.fecha, o.proveedor, o.comprador, o.monto_total,
       o.clasif_og as clasif_actual,
       case when coalesce(btrim(o.clasif_og), '') = '' then 'VACÍA' else 'NO EXISTE EN LA LISTA' end as problema
  from compras_ogs o
  left join compras_clasif_renglon c on c.codigo = btrim(o.clasif_og)
 where coalesce(btrim(o.clasif_og), '') = '' or c.codigo is null
 order by o.numero::int;
