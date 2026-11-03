-- OG 2101 (Perisa): renglones certificados/pagados con centro_costos vacío (EXCEPCIÓN puntual, una sola vez).
-- Completa solo los renglones vacíos con la clasificación de la OG (clasif_og = IF4417 según el diagnóstico).
-- Supuesto (no verificado): compras_ogs.items es jsonb. Aborta sin cambiar nada si la OG no es la esperada.
begin;
do $$
declare v_og record; v_n int;
begin
  select * into v_og from compras_ogs where numero::text = '2101';
  if not found then raise exception 'No existe la OG 2101'; end if;
  if coalesce(btrim(v_og.clasif_og), '') = '' then raise exception 'La OG 2101 no tiene clasif_og'; end if;

  update compras_ogs o
     set items = (
       select jsonb_agg(
                case when coalesce(btrim(e.it->>'centro_costos'), '') = ''
                     then jsonb_set(e.it, '{centro_costos}', to_jsonb(btrim(v_og.clasif_og)))
                     else e.it end
                order by e.ord)
         from jsonb_array_elements(o.items) with ordinality as e(it, ord))
   where o.id = v_og.id;
  get diagnostics v_n = row_count;
  if v_n <> 1 then raise exception 'Se esperaba actualizar 1 OG, fueron %', v_n; end if;
end $$;
commit;

-- Verificación: los 2 renglones tienen que mostrar IF4417.
select o.numero, i.ord as renglon, i.it->>'centro_costos' as centro_costos
  from compras_ogs o, jsonb_array_elements(o.items) with ordinality as i(it, ord)
 where o.numero::text = '2101';
