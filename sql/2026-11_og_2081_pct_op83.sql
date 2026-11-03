-- OG 2081: el % del pago OP 83 (id 94) quedó calculado sobre un total anterior de la OG (1.575.000)
-- y no sobre el actual (1.800.000). Se pagaron 900.000 reales => 900.000 / 1.800.000 = 50 %.
-- EXCEPCIÓN puntual, una sola vez. Correr A MANO en el SQL Editor.
-- Supuesto (no verificado): compras_pagos.pct es numérico y el % pagado de la OG se calcula sumando pct.
-- Aborta sin cambiar nada si el pago no coincide con lo esperado.
begin;
do $$
declare v_n int;
begin
  update compras_pagos
     set pct = 50
   where id = 94 and og_id = 91 and numero::text = '2081'
     and importe_pago = 900000 and round(pct::numeric, 4) = 57.1429;
  get diagnostics v_n = row_count;
  if v_n <> 1 then raise exception 'Se esperaba actualizar 1 pago (id 94), fueron %', v_n; end if;
end $$;
commit;

-- Verificación: los dos pagos tienen que dar 50 y 50.
select id, numero, fecha, pct, importe_pago from compras_pagos where og_id = 91 order by id;
